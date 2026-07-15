import 'package:flutter_test/flutter_test.dart';

/// Repeatedly pumps [tester] until [finder] locates at least one widget, or
/// [timeout] elapses (whichever comes first).
///
/// This app uses `flutter_animate` extensively, and a bare `tester.pump()`
/// (or even `pumpAndSettle()`, which can time out on infinite/looping
/// animations) often isn't enough to reliably wait out entrance animations
/// or async work before asserting on the result. This is the common
/// Flutter-test idiom for that: poll in small steps until the expected
/// widget shows up.
///
/// Throws a [TestFailure] if [finder] still finds nothing once [timeout] is
/// exceeded.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (finder.evaluate().isEmpty) {
    throw TestFailure('pumpUntilFound: $finder was not found within $timeout');
  }
}
