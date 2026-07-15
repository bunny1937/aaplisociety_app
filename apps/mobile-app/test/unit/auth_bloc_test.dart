import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:aapli_society/features/auth/bloc/auth_bloc.dart';

import '../fixtures/auth_fixtures.dart';
import '../mocks/fake_token_store.dart';
import '../mocks/mock_dio.dart';

Response<dynamic> _response(String path, dynamic data) => Response(
      requestOptions: RequestOptions(path: path),
      data: data,
      statusCode: 200,
    );

void main() {
  setUpAll(() {
    registerMockDioFallbacks();
  });

  late MockDio dio;
  late FakeTokenStore tokens;

  setUp(() {
    dio = MockDio();
    tokens = FakeTokenStore();
  });

  group('LoginRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthed] and persists the real tokens on a single-profile login',
      setUp: () {
        when(() => dio.post('/auth/login', data: any(named: 'data')))
            .thenAnswer((_) async => _response('/auth/login', sampleLoginResponse));
        when(() => dio.get('/auth/me'))
            .thenAnswer((_) async => _response('/auth/me', sampleAuthMeResponse));
      },
      build: () => AuthBloc(dio, tokens),
      act: (bloc) => bloc.add(LoginRequested('asha', 'password123')),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthed>()
            .having((s) => s.role, 'role', 'member')
            .having((s) => s.user['_id'], 'user._id', 'user_1')
            .having((s) => s.claims['societyId'], 'claims.societyId', 'society_1'),
      ],
      verify: (_) {
        // Check the token actually landed in the store, not just that some
        // method was invoked.
        expect(tokens.accessValue, 'sample-access-token');
        expect(tokens.refreshValue, 'sample-refresh-token');
        verify(() => dio.post('/auth/login', data: {'identifier': 'asha', 'password': 'password123'})).called(1);
        verify(() => dio.get('/auth/me')).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthNeedsProfile] and saves only the select token when multiple profiles exist',
      setUp: () {
        when(() => dio.post('/auth/login', data: any(named: 'data')))
            .thenAnswer((_) async => _response('/auth/login', sampleLoginNeedsProfileResponse));
      },
      build: () => AuthBloc(dio, tokens),
      act: (bloc) => bloc.add(LoginRequested('asha', 'password123')),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthNeedsProfile>()
            .having((s) => s.selectToken, 'selectToken', 'sample-select-token')
            .having((s) => s.profiles.length, 'profiles.length', 2),
      ],
      verify: (_) {
        expect(tokens.accessValue, 'sample-select-token');
        // No refresh token exists yet for a profile-select flow.
        expect(tokens.refreshValue, isNull);
        verifyNever(() => dio.get('/auth/me'));
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] with the real apiErrorMessage-derived message on invalid credentials',
      setUp: () {
        final req = RequestOptions(path: '/auth/login');
        when(() => dio.post('/auth/login', data: any(named: 'data'))).thenThrow(
          DioException(
            requestOptions: req,
            response: Response(
              requestOptions: req,
              statusCode: 401,
              data: {'error': 'Invalid credentials'},
            ),
            type: DioExceptionType.badResponse,
          ),
        );
      },
      build: () => AuthBloc(dio, tokens),
      act: (bloc) => bloc.add(LoginRequested('asha', 'wrong-password')),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>().having((s) => s.message, 'message', 'Invalid credentials'),
      ],
      verify: (_) {
        // No tokens should have been persisted on a failed login.
        expect(tokens.accessValue, isNull);
        expect(tokens.refreshValue, isNull);
      },
    );
  });

  group('SwitchProfileRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthed] on a successful profile switch',
      setUp: () {
        when(() => dio.post('/auth/switch-profile', data: any(named: 'data'))).thenAnswer(
          (_) async => _response('/auth/switch-profile', {
            'role': 'security',
            'tokens': {
              'accessToken': 'switched-access-token',
              'refreshToken': 'switched-refresh-token',
            },
          }),
        );
        when(() => dio.get('/auth/me'))
            .thenAnswer((_) async => _response('/auth/me', sampleAuthMeResponse));
      },
      build: () => AuthBloc(dio, tokens),
      act: (bloc) => bloc.add(SwitchProfileRequested('profile_2')),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthed>().having((s) => s.role, 'role', 'security'),
      ],
      verify: (_) {
        expect(tokens.accessValue, 'switched-access-token');
        expect(tokens.refreshValue, 'switched-refresh-token');
        verify(() => dio.post('/auth/switch-profile', data: {'profileId': 'profile_2'})).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] when the switch-profile call fails',
      setUp: () {
        final req = RequestOptions(path: '/auth/switch-profile');
        when(() => dio.post('/auth/switch-profile', data: any(named: 'data'))).thenThrow(
          DioException(requestOptions: req, type: DioExceptionType.connectionError),
        );
      },
      build: () => AuthBloc(dio, tokens),
      act: (bloc) => bloc.add(SwitchProfileRequested('profile_2')),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>().having(
          (s) => s.message,
          'message',
          'Could not reach the server. Check your connection.',
        ),
      ],
    );
  });

  group('LogoutRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthInitial] and actually clears the token store',
      build: () {
        tokens.accessValue = 'existing-access';
        tokens.refreshValue = 'existing-refresh';
        return AuthBloc(dio, tokens);
      },
      act: (bloc) => bloc.add(LogoutRequested()),
      expect: () => [isA<AuthInitial>()],
      verify: (_) async {
        expect(await tokens.access, isNull);
        expect(await tokens.refresh, isNull);
      },
    );
  });

  group('SessionRestored', () {
    blocTest<AuthBloc, AuthState>(
      'emits AuthAuthed directly with the exact data passed in and makes zero Dio calls',
      build: () => AuthBloc(dio, tokens),
      act: (bloc) => bloc.add(SessionRestored(
        'committee',
        {'_id': 'user_9', 'name': 'Restored User'},
        {'role': 'committee', 'societyId': 'society_9'},
      )),
      expect: () => [
        isA<AuthAuthed>()
            .having((s) => s.role, 'role', 'committee')
            .having((s) => s.user['_id'], 'user._id', 'user_9')
            .having((s) => s.claims['societyId'], 'claims.societyId', 'society_9'),
      ],
      verify: (_) {
        verifyNever(() => dio.post(any(), data: any(named: 'data')));
        verifyNever(() => dio.get(any()));
      },
    );
  });
}
