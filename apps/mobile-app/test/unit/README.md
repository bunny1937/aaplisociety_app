# Unit tests

Pure Dart logic tests — no `flutter_test` widget pumping, no `WidgetTester`.

Scope:
- Bloc logic (e.g. `AuthBloc` event -> state transitions) using `bloc_test`'s
  `blocTest` with `MockDio` from `test/mocks/mock_dio.dart` and
  `FakeTokenStore` from `test/mocks/fake_token_store.dart`.
- Repository / service classes that talk to `Dio` but have no widget surface.
- Model parsing / mapping functions (e.g. turning a raw API `Map` into a
  typed object), validated against the sample payloads in `test/fixtures/`.
- Pure utility/helper functions (formatters, validators, etc).

Out of scope (put these in `test/widget/` instead):
- Anything that pumps a `Widget`, taps/scrolls, or asserts on rendered UI.

Naming convention: mirror the `lib/` path, e.g. a test for
`lib/features/auth/bloc/auth_bloc.dart` lives at
`test/unit/features/auth/bloc/auth_bloc_test.dart`.

This directory is currently empty (foundation only) — no tests have been
added yet.
