import 'package:flutter/foundation.dart';

// Bumped whenever the backend pushes a relevant event over the socket, so any
// visible screen can refresh without wiring a dedicated event-bus package.
class SocketBus {
  static final visitorEvents = ValueNotifier<int>(0);
  static final billEvents = ValueNotifier<int>(0);
  static final noticeEvents = ValueNotifier<int>(0);
  // Bumped on every routed event regardless of type — the notification
  // history screen (features/notifications) reloads off this single counter
  // rather than needing a case added here per new backend NOTIFICATION_TYPES
  // value.
  static final notificationEvents = ValueNotifier<int>(0);
  // The same notification can arrive twice: once instantly via FCM foreground
  // push (PushService), then again ~20s later via RealtimePoller's GET
  // /v1/notifications backstop. Both call route() directly. Dedupe on the
  // Notification row's own id (FCM data payload carries it as
  // "notificationId"; polled rows carry it as "_id") so counters/toasts don't
  // double-fire for one event. Bounded so it can't leak memory over a long session.
  static final _seenIds = <String>{};
  static const _seenIdsCap = 300;

  /// Returns false when this exact notification (by id) was already routed —
  /// callers should skip their own toast/snackbar in that case.
  static bool route(String event, dynamic data) {
    final id = data is Map
        ? (data['notificationId'] ?? data['_id'])?.toString()
        : null;
    if (id != null) {
      if (_seenIds.contains(id)) return false;
      _seenIds.add(id);
      if (_seenIds.length > _seenIdsCap) _seenIds.remove(_seenIds.first);
    }
    switch (event) {
      case 'VISITOR_ENTERED':
      case 'VISITOR_EXITED':
      case 'VISITOR_APPROVAL':
      case 'VISITOR_DECISION':
      case 'VISITOR_SOS':
      case 'VISITOR_PASS':
      case 'VISITOR_ESCALATION':
      case 'SECURITY_ALERT':
        visitorEvents.value++;
        break;
      case 'BILL_GENERATED':
      case 'PAYMENT_RECEIVED':
        billEvents.value++;
        break;
      case 'NOTICE_POSTED':
        noticeEvents.value++;
        break;
    }
    notificationEvents.value++;
    return true;
  }
}
