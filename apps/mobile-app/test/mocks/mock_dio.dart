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
///
/// Overrides [preserveHeaderCase]: `Response`'s constructor always reads
/// `requestOptions.preserveHeaderCase` (to build its default `Headers`)
/// unless a `headers:` param is explicitly passed — a bare `Fake` throws
/// `UnimplementedError` on any unstubbed getter, so every
/// `Response(requestOptions: FakeRequestOptions(), ...)` in this codebase
/// would otherwise fail at construction time.
class FakeRequestOptions extends Fake implements RequestOptions {
  @override
  bool get preserveHeaderCase => false;
}

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
