import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the golden-test *mechanism* itself works end-to-end (Phase 11:
/// visual regression diff generation), independent of any real app screen.
///
/// This deliberately does NOT test a real screen — the app's UI changed a
/// lot this session and nothing is stable enough to pin down yet (see
/// test/golden/README.md). Instead it pumps a tiny, fixed-size/fixed-color
/// widget defined right here in the test file, so this test never needs to
/// be touched when real screens change.
///
/// To regenerate the baseline after a deliberate change to
/// [_MechanismProbeWidget]: `flutter test --update-goldens test/golden/mechanism_test.dart`
class _MechanismProbeWidget extends StatelessWidget {
  const _MechanismProbeWidget();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 120,
          height: 80,
          child: ColoredBox(
            color: Color(0xFF3355FF),
            child: Center(
              child: Text(
                'golden-ok',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('mechanism probe widget matches its pinned golden image', (tester) async {
    await tester.binding.setSurfaceSize(const Size(200, 150));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const _MechanismProbeWidget());
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(_MechanismProbeWidget),
      matchesGoldenFile('goldens/mechanism_baseline.png'),
    );
  });
}
