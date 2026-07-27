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
/// Two changes:
/// 1. **Lifecycle aware.** Polling stops when the app leaves the foreground and
///    resumes with an immediate catch-up poll. Backgrounded delivery is FCM's
///    job, and FCM does it without waking our Dart isolate.
/// 2. **Adaptive cadence.** [activeInterval] while things are happening; after
///    [_idleAfterEmptyPolls] consecutive polls that return nothing, it backs
///    off to [idleInterval]. Any new notification snaps it straight back to the
///    fast cadence, so responsiveness when it matters is unchanged.
///
/// The `since` watermark means a slower cadence never loses an event - the next
/// poll still returns everything since the last one.
class RealtimePoller with WidgetsBindingObserver {
  RealtimePoller._();
  static final instance = RealtimePoller._();

  Timer? _timer;
  String? _since; // ISO createdAt of the newest notification already seen
  bool _seeded = false;
  bool _inFlight = false;
  bool _observing = false;
  int _emptyPolls = 0;
  Duration _cadence = activeInterval;
  Dio? _dio;
  void Function(String event, dynamic data)? _onEvent;

  /// Cadence while the society is active.
  static const Duration activeInterval = Duration(seconds: 20);

  /// Cadence after a stretch of silence. FCM still covers anything urgent.
  static const Duration idleInterval = Duration(seconds: 90);

  /// Kept for any existing reference to the old constant name.
  static const Duration interval = activeInterval;

  /// ~2 minutes of nothing at the fast cadence before backing off.
  static const int _idleAfterEmptyPolls = 6;

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
        // user just opened the app and expects to see current state.
        _emptyPolls = 0;
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
      final data = res.data;
      final list =
          (data is Map ? data['notifications'] : null) as List? ?? const [];
      if (list.isEmpty) {
        _emptyPolls++;
        if (_emptyPolls >= _idleAfterEmptyPolls &&
            _cadence != idleInterval &&
            _timer != null) {
          AppLogger.info('[poller] idle - backing off to ${idleInterval.inSeconds}s');
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
    _cadence = activeInterval;
    _dio = null;
    _onEvent = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }
}
