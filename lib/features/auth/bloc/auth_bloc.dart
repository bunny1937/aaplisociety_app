import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_error.dart';
import '../../../core/storage/token_store.dart';
import '../../../core/storage/offline_cache.dart';
import '../../../core/storage/offline_outbox.dart';
import '../../onboarding/data/onboarding_api.dart' show ProfileSummary;

sealed class AuthEvent {}

class LoginRequested extends AuthEvent {
  final String id;
  final String pw;
  LoginRequested(this.id, this.pw);
}

/// First selection, straight after login. Authorised ONLY by the short-lived
/// pending token that login returned; nothing is in TokenStore yet.
class SwitchProfileRequested extends AuthEvent {
  final String profileId;
  final String profileSelectToken;
  SwitchProfileRequested(this.profileId, this.profileSelectToken);
}

/// In-session switch from the dashboard avatar. No pending token exists - the
/// normal access token on the Dio interceptor is the authorisation.
///
/// Deliberately a separate event from SwitchProfileRequested so the two paths
/// cannot be confused: this one MUST NOT send a profileSelectToken (there isn't
/// one), and it must wipe the offline cache before emitting, because that cache
/// holds flat 101's bills, ledger and complaints and we are about to render 201.
class SwitchProfileInSession extends AuthEvent {
  final String profileId;
  SwitchProfileInSession(this.profileId);
}

class SessionRestored extends AuthEvent {
  final String role;
  final String kind;
  final Map<String, dynamic> user;
  final Map<String, dynamic> claims;
  SessionRestored(this.role, this.kind, this.user, this.claims);
}

class LogoutRequested extends AuthEvent {}

sealed class AuthState {}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthed extends AuthState {
  final String role;
  final String kind;
  final Map<String, dynamic> user;
  final Map<String, dynamic> claims;
  final bool mustChangePassword;
  AuthAuthed(this.role, this.kind, this.user, this.claims,
      {this.mustChangePassword = false});
}

// Where each role/kind lands after auth. Shared by login + profile-select so
// the screens can't drift on where a given profile actually goes. Commercial
// routes to /shop regardless of role — a shop owner is never Admin/Security
// on that profile, but checking kind first (not just role) keeps this correct
// if that ever changes.
String homeRouteForProfile(String role, String kind) {
  if (kind == 'Commercial') return '/shop';
  if (role == 'Admin' || role == 'Secretary' || role == 'Accountant') {
    return '/admin';
  }
  if (role == 'Security') return '/security';
  return '/member';
}

class AuthNeedsProfile extends AuthState {
  final String name;
  final List<ProfileSummary> profiles;
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
        // Read both name pairs so deploy order stops mattering: a server
        // rollback cannot strand a shipped build at the login screen.
        final needsSelect = (res.data['requiresProfileSelect'] ??
                res.data['needsProfileSelect']) ==
            true;
        if (needsSelect) {
          final token = (res.data['profileSelectToken'] ??
              res.data['selectToken']) as String?;
          final profiles = ((res.data['profiles'] as List?) ?? const [])
              .map((p) => ProfileSummary.fromJson(Map<String, dynamic>.from(p as Map)))
              .toList();
          if (token == null || profiles.isEmpty) {
            emit(AuthError(
                'Could not start profile selection. Please try again.'));
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
        // thing authorising this call. It is short lived and deliberately never
        // written to TokenStore, which is why it travels in the body.
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

    on<SwitchProfileInSession>((e, emit) async {
      emit(AuthLoading());
      try {
        // No profileSelectToken here on purpose. The interceptor attaches the
        // live access token and the route accepts a non-pending claim for
        // exactly this case.
        final res = await dio.post(
          '/auth/switch-profile',
          data: {'profileId': e.profileId},
        );

        // Order matters. Swap the token FIRST so nothing can refetch under the
        // old profile, then drop the previous flat's cached bills / ledger /
        // complaints and its queued writes. Replaying 101's outbox against 201
        // would post real money to the wrong flat.
        await tokens.save(res.data['tokens']['accessToken'],
            res.data['tokens']['refreshToken']);
        await OfflineCache.clear();
        await OfflineOutbox.clear();

        emit(await _hydrate(res.data['role']));
      } on DioException catch (err) {
        emit(AuthError(apiErrorMessage(err, 'Could not switch flat')));
      }
    });

    on<SessionRestored>(
        (e, emit) => emit(AuthAuthed(e.role, e.kind, e.user, e.claims)));
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
    if (me.data['shop'] != null) user['shop'] = me.data['shop'];
    final claims = Map<String, dynamic>.from(me.data['claims']);
    return AuthAuthed(
      role,
      (claims['kind'] ?? 'Residential').toString(),
      user,
      claims,
      mustChangePassword: user['mustChangePassword'] == true,
    );
  }
}
