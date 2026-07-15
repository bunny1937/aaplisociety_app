import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';

/// Mocktail-based mock of [Dio] for unit/bloc/widget tests.
///
/// Usage:
/// ```dart
/// final dio = MockDio();
/// registerMockDioFallbacks();
/// when(() => dio.post('/auth/login', data: any(named: 'data')))
///     .thenAnswer((_) async => Response(
///           requestOptions: RequestOptions(path: '/auth/login'),
///           data: {...},
///         ));
/// ```
class MockDio extends Mock implements Dio {}

/// A fake [RequestOptions] usable as a mocktail fallback value, and as the
/// `requestOptions` for hand-built [Response]/[DioException] instances in
/// tests.
class FakeRequestOptions extends Fake implements RequestOptions {}

/// Registers fallback values mocktail needs for `any()` matchers against
/// [MockDio] methods whose positional/named argument types aren't
/// registered by default (e.g. `RequestOptions`, `Options`).
///
/// Call this once per test file (e.g. in a `setUpAll`) before using `any()`
/// with [MockDio].
void registerMockDioFallbacks() {
  registerFallbackValue(FakeRequestOptions());
  registerFallbackValue(Options());
}
