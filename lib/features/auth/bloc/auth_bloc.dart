import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_error.dart';
import '../../../core/storage/token_store.dart';
import '../../../core/storage/offline_cache.dart';
import '../../../core/storage/offline_outbox.dart';
import '../../onboarding/data/onboarding_api.dart' show FlatSummary;

sealed class AuthEvent {}

class LoginRequested extends AuthEvent {
  final String id;
  final String pw;
  LoginRequested(this.id, this.pw);
}

class SwitchProfileRequested extends AuthEvent {
  final String profileId;
  final String profileSelectToken;
  SwitchProfileRequested(this.profileId, this.profileSelectToken);
}

class SessionRestored extends AuthEvent {
  final String role;
  final Map<String, dynamic> user;
  final Map<String, dynamic> claims;
  SessionRestored(this.role, this.user, this.claims);
}

class LogoutRequested extends AuthEvent {}

sealed class AuthState {}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthed extends AuthState {
  final String role;
  final Map<String, dynamic> user;
  final Map<String, dynamic> claims;
  final bool mustChangePassword;
  AuthAuthed(this.role, this.user, this.claims,
      {this.mustChangePassword = false});
}

// Where each role lands after auth. Shared by login + profile-select so the
// two screens can't drift on where a given role's home actually is.
String homeRouteForRole(String role) {
  if (role == 'Admin' || role == 'Secretary' || role == 'Accountant') {
    return '/admin';
  }
  if (role == 'Security') return '/security';
  return '/member';
}

class AuthNeedsProfile extends AuthState {
  final String name;
  final List<FlatSummary> profiles;
  final String selectToken;
  AuthNeedsProfile(this.name, this.profiles, this.selectToken);
}

class AuthError extends AuthState {
  final String message;
  AuthError(this.message);
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final Dio dio;
  final TokenStore tokens;
  AuthBloc(this.dio, this.tokens) : super(AuthInitial()) {
    on<LoginRequested>((e, emit) async {
      emit(AuthLoading());
      try {
        final res = await dio
            .post('/auth/login', data: {'identifier': e.id, 'password': e.pw});
       // Read both name pairs so deploy order stops mattering: a server rollback
// cannot strand a shipped build at the login screen.
final needsSelect =
    (res.data['requiresProfileSelect'] ?? res.data['needsProfileSelect']) == true;
if (needsSelect) {
  final token =
      (res.data['profileSelectToken'] ?? res.data['selectToken']) as String?;
  final profiles = ((res.data['profiles'] as List?) ?? const [])
      .map((p) => FlatSummary.fromJson(Map<String, dynamic>.from(p as Map)))
      .toList();
  if (token == null || profiles.isEmpty) {
    emit(AuthError('Could not start profile selection. Please try again.'));
    return;
  }
  emit(AuthNeedsProfile(
    (res.data['name'] ?? res.data['username']) as String? ?? 'there',
    profiles,
    token,
  ));
  return;
}
        await tokens.save(res.data['tokens']['accessToken'],
            res.data['tokens']['refreshToken']);
        emit(await _hydrate(res.data['role']));
      } on DioException catch (err) {
        emit(AuthError(apiErrorMessage(err, 'Login failed')));
      }
    });
    on<SwitchProfileRequested>((e, emit) async {
      emit(AuthLoading());
      try {
        // The app has no cookie jar, so the profile-select token is the ONLY
        // thing authorising this call. It expires in 10 minutes, matching
        // the web flow.
        final res = await dio.post('/auth/switch-profile', data: {
          'profileId': e.profileId,
          'profileSelectToken': e.profileSelectToken,
        });
        await tokens.save(res.data['tokens']['accessToken'],
            res.data['tokens']['refreshToken']);
        emit(await _hydrate(res.data['role']));
      } on DioException catch (err) {
        emit(AuthError(apiErrorMessage(err, 'Could not switch profile')));
      }
    });
    on<SessionRestored>(
        (e, emit) => emit(AuthAuthed(e.role, e.user, e.claims)));
    on<LogoutRequested>((e, emit) async {
      await tokens.clear();
      // Shared guard phones must not show one account's cached bills,
      // visitors, complaints, or replay its queued writes under another user.
      await OfflineCache.clear();
      await OfflineOutbox.clear();
      emit(AuthInitial());
    });
  }
  Future<AuthAuthed> _hydrate(String role) async {
    final me = await dio.get('/auth/me');
    final user = Map<String, dynamic>.from(me.data['user']);
    if (me.data['member'] != null) user['member'] = me.data['member'];
    if (me.data['society'] != null) user['society'] = me.data['society'];
    return AuthAuthed(
      role,
      user,
      Map<String, dynamic>.from(me.data['claims']),
      mustChangePassword: user['mustChangePassword'] == true,
    );
  }
}
