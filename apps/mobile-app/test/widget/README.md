# Widget tests

Widget rendering/interaction tests that run under plain `flutter test`
(no device/emulator required).

Scope:
- Pumping a single page/widget via `pumpApp` from `test/helpers/pump_app.dart`
  and asserting on what's rendered (text, icons, buttons enabled/disabled).
- Simulating user interaction (`tester.tap`, `tester.enterText`,
  `tester.drag`) and asserting the resulting UI state.
- Verifying `BlocProvider`-driven UI reacts correctly to bloc states, using
  `MockDio` (mocktail) to stub the `Dio` calls the page/bloc makes and
  `FakeTokenStore` in place of `flutter_secure_storage`.
- Because this app uses `flutter_animate` extensively, prefer
  `pumpUntilFound` from `test/utils/pump_until_found.dart` over a bare
  `tester.pump()` when waiting on animated/async content to settle.

Out of scope:
- Full app navigation flows across multiple routes/screens — that belongs in
  `integration_test/` (needs a real device/emulator to exercise platform
  channels and full `GoRouter` navigation end-to-end).
- Pure logic with no widget tree — put that in `test/unit/`.

Naming convention: mirror the `lib/` path, e.g. a test for
`lib/features/member/bills_page.dart` lives at
`test/widget/features/member/bills_page_test.dart`.

This directory is currently empty (foundation only) — no tests have been
added yet.
