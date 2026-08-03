import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import '../logging/app_logger.dart';
import '../storage/offline_outbox.dart';
import 'socket_bus.dart';

/// Drop-in replacement for [SocketService] on the Vercel deployment, which has
/// no Socket.IO server. Instead of a websocket, this polls
/// `GET /v1/notifications?since=` on a timer and routes every new notification
/// through [SocketBus] — bumping the exact same counters a live socket event
/// used to — so all listening screens refresh with no other code changes.
///
/// FCM push (see PushService) still delivers instant foreground updates and
/// also bumps SocketBus; this poller is the reliable backstop that catches
/// anything missed while the app had no push delivery.
///
/// ## Refresh tuning
///
/// This used to be a flat `Timer.periodic(20s)` that never stopped: it kept
/// firing while the app sat backgrounded in the recents list, and it kept
/// firing every 20 seconds at 3am when nothing in the society was happening.
/// On a serverless backend that is a paid invocation every 20 seconds per
/// installed app, forever, and on the phone it is a radio wake-up every 20
/// seconds - which is what drains the battery, not the request size.
///
/// Three changes:
/// 1. **Lifecycle aware.** Polling stops when the app leaves the foreground and
///    resumes with an immediate catch-up poll. Backgrounded delivery is FCM's
///    job, and FCM does it without waking our Dart isolate.
/// 2. **Adaptive cadence.** [activeInterval] while things are happening; after
///    [_idleAfterEmptyPolls] consecutive polls that return nothing, it backs
///    off to [idleInterval]. Any new notification snaps it straight back to the
///    fast cadence, so responsiveness when it matters is unchanged.
/// 3. **Backoff on failure.** A backend outage used to mean every installed
///    app hammering a failing endpoint on the same cadence forever. Now the
///    interval doubles on each consecutive error up to [maxBackoff].
///
/// The `since` watermark means a slower cadence never loses an event - the next
/// poll still returns everything since the last one.
///
/// ## Why the intervals moved (20s/90s -> 45s/300s)
///
/// This poller is, by a wide margin, the largest consumer of serverless
/// function invocations in the whole product. At the old cadence, one device
/// with 3 active hours and 5 idle hours a day generates roughly 740 requests a
/// day. At 100 installed devices that is ~2.2 million invocations a month,
/// against an included allowance of 1 million - the notification poller alone
/// exhausts the plan before a single resident opens a bill.
///
/// Each of those requests hits a `force-dynamic` Node function that opens a
/// Mongo connection, so it is also the main driver of the Atlas connection
/// count and of provisioned-memory GB-hours.
///
/// The important thing is that **this is not a responsiveness trade**: FCM push
/// is the primary delivery channel and is unaffected: a visitor at the gate
/// still lights up the phone instantly. The poller only exists to catch what
/// push missed (push disabled, token expired, doze mode). For a backstop,
/// 45 seconds is indistinguishable from 20 in practice, and 5 minutes of idle
/// cadence is more than sufficient.
///
/// Combined effect: ~740 -> ~250 requests/device/day, roughly a 3x reduction,
/// which moves the 1M ceiling from ~45 devices to ~130.
///
/// If you later add an Edge-cached watermark endpoint (returning 304 when
/// nothing changed), you can safely drop [activeInterval] back to 20s, because
/// the empty case stops costing a function invocation at all.
class RealtimePoller with WidgetsBindingObserver {
  RealtimePoller._();
  static final instance = RealtimePoller._();

  Timer? _timer;
  String? _since; // ISO createdAt of the newest notification already seen
  bool _seeded = false;
  bool _inFlight = false;
  bool _observing = false;
  int _emptyPolls = 0;
  int _consecutiveErrors = 0;
  Duration _cadence = activeInterval;
  Dio? _dio;
  void Function(String event, dynamic data)? _onEvent;

  /// Cadence while the society is active. FCM covers anything urgent, so this
  /// is a backstop interval, not a delivery guarantee.
  static const Duration activeInterval = Duration(seconds: 45);

  /// Cadence after a stretch of silence.
  static const Duration idleInterval = Duration(minutes: 5);

  /// Ceiling for error backoff, so an outage cannot turn every installed app
  /// into a retry storm against a backend that is already struggling.
  static const Duration maxBackoff = Duration(minutes: 10);

  /// Kept for any existing reference to the old constant name.
  static const Duration interval = activeInterval;

  /// ~3 minutes of nothing at the fast cadence before backing off.
  static const int _idleAfterEmptyPolls = 4;

  void start(Dio dio, {void Function(String event, dynamic data)? onEvent}) {
    stop();
    _dio = dio;
    _onEvent = onEvent;
    if (!_observing) {
      // Late-registered on purpose: main() may start the poller before the
      // binding exists in some test setups.
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    // Force every listening screen to refetch immediately on (re)start, exactly
    // like the old socket onReconnect did.
    SocketBus.visitorEvents.value++;
    SocketBus.billEvents.value++;
    SocketBus.noticeEvents.value++;
    SocketBus.notificationEvents.value++;
    _emptyPolls = 0;
    _consecutiveErrors = 0;
    _poll();
    _schedule(activeInterval);
  }

  void _schedule(Duration cadence) {
    _timer?.cancel();
    _cadence = cadence;
    _timer = Timer.periodic(cadence, (_) => _poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_dio == null) return;
        // Catch up immediately rather than waiting out a full interval - the
        // user just opened the app and expects to see current state. This is
        // what makes the longer interval invisible to the user: the moment
        // that matters most is app-open, and app-open always polls now.
        _emptyPolls = 0;
        _consecutiveErrors = 0;
        _poll();
        _schedule(activeInterval);
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Keep the watermark and the seeded flag: we are pausing, not resetting,
        // so the resume poll returns exactly what was missed.
        _timer?.cancel();
        _timer = null;
    }
  }

  /// Called by PushService when an FCM message arrives. A push means something
  /// just happened, so drop back to the fast cadence and pull the detail
  /// immediately - the push payload is a nudge, the poll is the source of
  /// truth. This is what lets the idle interval be as long as 5 minutes
  /// without ever feeling slow.
  void nudge() {
    if (_dio == null) return;
    _emptyPolls = 0;
    _consecutiveErrors = 0;
    _poll();
    if (_cadence != activeInterval && _timer != null) _schedule(activeInterval);
  }

  Future<void> _poll() async {
    final dio = _dio;
    if (dio == null || _inFlight) return;
    _inFlight = true;
    try {
      if (OfflineOutbox.pendingCount > 0) {
        await OfflineOutbox.syncAndNotify(dio);
      }
      final res = await dio.get('/notifications', queryParameters: {
        if (_since != null) 'since': _since,
        'limit': 50,
      });

      _consecutiveErrors = 0;

      final data = res.data;
      final list =
          (data is Map ? data['notifications'] : null) as List? ?? const [];
      if (list.isEmpty) {
        _emptyPolls++;
        if (_emptyPolls >= _idleAfterEmptyPolls &&
            _cadence != idleInterval &&
            _timer != null) {
          AppLogger.info(
              '[poller] idle - backing off to ${idleInterval.inSeconds}s');
          _schedule(idleInterval);
        }
        return;
      }
      // Something happened: go back to the fast cadence.
      _emptyPolls = 0;
      if (_cadence != activeInterval && _timer != null) {
        _schedule(activeInterval);
      }

      // Endpoint returns newest-first; advance the watermark to the newest.
      final newest = list.first as Map;
      final newestAt = newest['createdAt']?.toString();
      if (newestAt != null) _since = newestAt;

      // On the very first poll just seed the watermark; don't replay history
      // (would fire stale SOS alarms). The initial counter bump above already
      // refreshed the screens.
      if (!_seeded) {
        _seeded = true;
        return;
      }

      // Route oldest -> newest so counters/toasts fire in chronological order.
      final onEvent = _onEvent;
      for (final n in list.reversed) {
        final m = n as Map;
        final type = m['type'] as String?;
        if (type == null) continue;
        final isNew = SocketBus.route(type, m);
        if (isNew && onEvent != null) onEvent(type, m);
      }
    } catch (e, st) {
      AppLogger.error('[poller] poll failed', error: e, stackTrace: st);
      // Exponential backoff on repeated failure. Without this, a backend
      // outage means every installed device retries on a fixed cadence for as
      // long as the outage lasts - maximum load at exactly the wrong moment.
      _consecutiveErrors++;
      if (_consecutiveErrors >= 2 && _timer != null) {
        final backoffSeconds =
            (activeInterval.inSeconds * (1 << (_consecutiveErrors - 1)))
                .clamp(activeInterval.inSeconds, maxBackoff.inSeconds);
        final next = Duration(seconds: backoffSeconds);
        if (next != _cadence) {
          AppLogger.info(
              '[poller] $_consecutiveErrors consecutive failures - backing off to ${next.inSeconds}s');
          _schedule(next);
        }
      }
    } finally {
      _inFlight = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _since = null;
    _seeded = false;
    _emptyPolls = 0;
    _consecutiveErrors = 0;
    _cadence = activeInterval;
    _dio = null;
    _onEvent = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }
}
