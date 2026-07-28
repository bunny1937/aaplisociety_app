import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import '../logging/app_logger.dart';
import '../storage/offline_outbox.dart';
import 'socket_bus.dart';

/// Drop-in replacement for [SocketService] on the Vercel deployment, which has
/// no Socket.IO server. Instead of a websocket, this polls
/// `GET /v1/notifications?since=` and routes every new notification through
/// [SocketBus] - bumping the exact same counters a live socket event used to -
/// so all listening screens refresh with no other code changes.
///
/// ## Why this is no longer a fixed 20s timer
///
/// FCM push is the PRIMARY delivery path and already bumps [SocketBus]. This
/// poller is only a backstop for pushes that never arrived (revoked token,
/// battery-optimised OEM, notifications disabled, silent-push throttling).
/// A backstop that fires every 20 seconds is not a backstop - it is the primary
/// path, and it was generating ~91% of all backend traffic:
///
///   1 device, 20s, 18 foreground minutes/day =    1,620 requests/month
///   1 guard tablet, 20s, 12h shift            =   64,800 requests/month
///
/// The guard tablet alone cost more than every resident combined, because it
/// sits in the foreground all shift and the old timer never backed off.
///
/// This version uses an adaptive backoff ladder. It polls quickly right after
/// something happens (when the user is most likely to be watching a gate entry
/// resolve), then decays toward [maxInterval] while nothing changes:
///
///   30s -> 60s -> 120s -> 300s  (reset to 30s on any activity)
///
/// Same guard tablet on this ladder: ~144 requests per 12h shift instead of
/// 2,160 - a ~93% cut - with no loss of correctness, because:
///   * FCM still delivers real events in ~1 second;
///   * [kick] forces an immediate poll whenever a push lands;
///   * the ladder resets to 30s the moment anything actually changes;
///   * a resume from background always polls immediately.
///
/// It also stops entirely when the app is backgrounded (the old timer kept
/// firing until the OS froze the isolate) and sends `If-None-Match` so an
/// unchanged feed comes back as a bodyless 304.
class RealtimePoller with WidgetsBindingObserver {
  RealtimePoller._();
  static final instance = RealtimePoller._();

  /// Cadence immediately after any activity - fast enough that a resident
  /// watching "Pending" resolve sees it without thinking about it.
  static const Duration minInterval = Duration(seconds: 30);

  /// Steady-state cadence once nothing has changed for a while. This is the
  /// number that decides your bill.
  static const Duration maxInterval = Duration(minutes: 5);

  /// Consecutive empty polls before the interval starts doubling.
  static const int emptyPollsBeforeBackoff = 2;

  Timer? _timer;
  Dio? _dio;
  void Function(String event, dynamic data)? _onEvent;

  String? _since; // ISO createdAt of the newest notification already seen
  String? _etag; // last ETag, echoed back as If-None-Match
  bool _seeded = false;
  bool _inFlight = false;
  bool _running = false;
  int _emptyPolls = 0;
  Duration _interval = minInterval;
  final _rand = Random();

  /// Current cadence, exposed for diagnostics / debug overlays.
  Duration get interval => _interval;
  bool get isRunning => _running;

  void start(Dio dio, {void Function(String event, dynamic data)? onEvent}) {
    stop();
    _dio = dio;
    _onEvent = onEvent;
    _running = true;
    _interval = minInterval;
    _emptyPolls = 0;
    WidgetsBinding.instance.addObserver(this);

    // Force every listening screen to refetch immediately on (re)start, exactly
    // like the old socket onReconnect did.
    SocketBus.visitorEvents.value++;
    SocketBus.billEvents.value++;
    SocketBus.noticeEvents.value++;
    SocketBus.notificationEvents.value++;

    _poll();
    _schedule();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_running) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _running = false;
    _dio = null;
    _onEvent = null;
    _since = null;
    _etag = null;
    _seeded = false;
    _emptyPolls = 0;
    _interval = minInterval;
  }

  /// Force an immediate poll and reset the backoff ladder.
  ///
  /// Call this from [PushService] the moment an FCM message arrives, and from
  /// any pull-to-refresh. This is what makes a 5-minute idle interval safe:
  /// real events do not wait for the timer, they arrive by push and then this
  /// pulls the authoritative list.
  void kick() {
    if (!_running) return;
    _emptyPolls = 0;
    _interval = minInterval;
    _poll();
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running) return;
    switch (state) {
      case AppLifecycleState.resumed:
        // Anything that happened while we were away arrives in one catch-up
        // poll, and the user is looking at the screen again, so go fast.
        kick();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Stop burning requests (and battery) behind the user's back. FCM keeps
        // working while backgrounded - that is its entire job.
        _timer?.cancel();
        _timer = null;
        break;
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_running) return;
    // +/-15% jitter so a society's worth of devices woken by the same push do
    // not all poll on the same second and manufacture an artificial peak.
    final ms = _interval.inMilliseconds;
    final jittered = ms + (_rand.nextDouble() * 0.3 - 0.15) * ms;
    _timer = Timer(Duration(milliseconds: jittered.round()), () {
      _poll();
      _schedule();
    });
  }

  void _slowDown() {
    _emptyPolls++;
    if (_emptyPolls < emptyPollsBeforeBackoff) return;
    if (_interval >= maxInterval) return;
    final next = _interval * 2;
    _interval = next > maxInterval ? maxInterval : next;
  }

  void _speedUp() {
    _emptyPolls = 0;
    _interval = minInterval;
  }

  Future<void> _poll() async {
    final dio = _dio;
    if (dio == null || _inFlight) return;
    _inFlight = true;
    try {
      if (OfflineOutbox.pendingCount > 0) {
        await OfflineOutbox.syncAndNotify(dio);
      }
      final res = await dio.get(
        '/notifications',
        queryParameters: {
          if (_since != null) 'since': _since,
          'limit': 50,
        },
        options: Options(
          headers: {
            if (_etag != null) 'If-None-Match': _etag,
          },
          // 304 is a success for us: it means "nothing new", with no body to
          // parse. Dio's default validateStatus rejects it.
          validateStatus: (s) => s != null && (s == 304 || (s >= 200 && s < 300)),
        ),
      );

      final tag = res.headers.value('etag');
      if (tag != null) _etag = tag;

      if (res.statusCode == 304) {
        _slowDown();
        return;
      }

      final data = res.data;
      final list =
          (data is Map ? data['notifications'] : null) as List? ?? const [];
      if (list.isEmpty) {
        _slowDown();
        return;
      }

      // Endpoint returns newest-first; advance the watermark to the newest.
      final newest = list.first as Map;
      final newestAt = newest['createdAt']?.toString();
      if (newestAt != null) _since = newestAt;

      // On the very first poll just seed the watermark; don't replay history
      // (would fire stale SOS toasts). The initial counter bump above already
      // refreshed the screens.
      if (!_seeded) {
        _seeded = true;
        _slowDown();
        return;
      }

      // Something genuinely happened - the user is probably mid-interaction, so
      // tighten the cadence again.
      _speedUp();

      // Route oldest -> newest so counters/toasts fire in chronological order.
      for (final n in list.reversed) {
        final m = n as Map;
        final type = m['type'] as String?;
        if (type == null) continue;
        final isNew = SocketBus.route(type, m);
        final cb = _onEvent;
        if (isNew && cb != null) cb(type, m);
      }
    } catch (e, st) {
      AppLogger.error('[poller] poll failed', error: e, stackTrace: st);
      // A failing server is the worst time to hammer it.
      _slowDown();
    } finally {
      _inFlight = false;
    }
  }
}
