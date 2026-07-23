import 'dart:async';
import 'package:dio/dio.dart';
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
class RealtimePoller {
  RealtimePoller._();
  static final instance = RealtimePoller._();

  Timer? _timer;
  String? _since; // ISO createdAt of the newest notification already seen
  bool _seeded = false;
  bool _inFlight = false;

  // Foreground polling cadence. Keep modest to balance freshness vs. battery /
  // serverless invocations; FCM covers the instant case.
  static const Duration interval = Duration(seconds: 20);

  void start(Dio dio, {void Function(String event, dynamic data)? onEvent}) {
    stop();
    // Force every listening screen to refetch immediately on (re)start, exactly
    // like the old socket onReconnect did.
    SocketBus.visitorEvents.value++;
    SocketBus.billEvents.value++;
    SocketBus.noticeEvents.value++;
    SocketBus.notificationEvents.value++;
    _poll(dio, onEvent);
    _timer = Timer.periodic(interval, (_) => _poll(dio, onEvent));
  }

  Future<void> _poll(Dio dio, void Function(String, dynamic)? onEvent) async {
    if (_inFlight) return;
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
      if (list.isEmpty) return;

      // Endpoint returns newest-first; advance the watermark to the newest.
      final newest = list.first as Map;
      final newestAt = newest['createdAt']?.toString();
      if (newestAt != null) _since = newestAt;

      // On the very first poll just seed the watermark; don't replay history
      // (would fire stale SOS toasts). The initial counter bump above already
      // refreshed the screens.
      if (!_seeded) {
        _seeded = true;
        return;
      }

      // Route oldest -> newest so counters/toasts fire in chronological order.
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
  }
}
