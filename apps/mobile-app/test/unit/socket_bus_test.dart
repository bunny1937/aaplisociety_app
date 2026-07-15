import 'package:flutter_test/flutter_test.dart';
import 'package:aapli_society/core/socket/socket_bus.dart';

void main() {
  // `SocketBus`'s ValueNotifiers are global statics shared across every test
  // in this file (and, in principle, the whole test run) — reset them before
  // each test so one test's events can't leak into the next.
  setUp(() {
    SocketBus.visitorEvents.value = 0;
    SocketBus.billEvents.value = 0;
    SocketBus.noticeEvents.value = 0;
  });

  group('SocketBus.route visitor events', () {
    for (final event in [
      'VISITOR_ENTERED',
      'VISITOR_EXITED',
      'VISITOR_APPROVAL',
      'VISITOR_DECISION',
      'VISITOR_SOS',
    ]) {
      test('$event increments visitorEvents by exactly 1 and leaves others untouched', () {
        SocketBus.route(event, null);
        expect(SocketBus.visitorEvents.value, 1);
        expect(SocketBus.billEvents.value, 0);
        expect(SocketBus.noticeEvents.value, 0);
      });
    }

    test('multiple visitor events accumulate', () {
      SocketBus.route('VISITOR_ENTERED', null);
      SocketBus.route('VISITOR_SOS', null);
      SocketBus.route('VISITOR_EXITED', null);
      expect(SocketBus.visitorEvents.value, 3);
      expect(SocketBus.billEvents.value, 0);
      expect(SocketBus.noticeEvents.value, 0);
    });
  });

  group('SocketBus.route bill events', () {
    for (final event in ['BILL_GENERATED', 'PAYMENT_RECEIVED']) {
      test('$event increments billEvents only', () {
        SocketBus.route(event, null);
        expect(SocketBus.billEvents.value, 1);
        expect(SocketBus.visitorEvents.value, 0);
        expect(SocketBus.noticeEvents.value, 0);
      });
    }
  });

  group('SocketBus.route notice events', () {
    test('NOTICE_POSTED increments noticeEvents only', () {
      SocketBus.route('NOTICE_POSTED', null);
      expect(SocketBus.noticeEvents.value, 1);
      expect(SocketBus.visitorEvents.value, 0);
      expect(SocketBus.billEvents.value, 0);
    });
  });

  group('SocketBus.route unrecognized events', () {
    test('an unrecognized event name changes nothing', () {
      SocketBus.route('SOMETHING_UNKNOWN', null);
      expect(SocketBus.visitorEvents.value, 0);
      expect(SocketBus.billEvents.value, 0);
      expect(SocketBus.noticeEvents.value, 0);
    });

    test('an empty event string changes nothing', () {
      SocketBus.route('', null);
      expect(SocketBus.visitorEvents.value, 0);
      expect(SocketBus.billEvents.value, 0);
      expect(SocketBus.noticeEvents.value, 0);
    });
  });
}
