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

  static void route(String event, dynamic data) {
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
  }
}
