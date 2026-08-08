import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/haptics.dart';
import '../member/pulse/pulse.dart';
import 'bloc/auth_bloc.dart';
import 'widgets/flat_picker_sheet.dart';

/// Port of ui_kits/member-v2 `MemberV2ScreensAuth.jsx` `LoginScreen` — light
/// Pulse look (design intentionally drops the app's old dark-glass login
/// treatment). Keeps the real phone-or-username field + `AuthBloc` wiring;
/// only the design's "Username or email" framing is cosmetic copy, the
/// actual field still accepts phone-or-username per the real auth flow.
/// "Forgot password?" pushes /forgot-password, backed by PasswordResetBloc
/// (see docs/superpowers/specs/2026-07-19-mobile-forgot-password-design.md).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _obscure = true;
  Completer<String?>? _pendingSwitch;
  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Scaffold(
      backgroundColor: t.canvas,
      body: Stack(
        children: [
          Positioned(
            top: -80,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                      colors: [t.brandSoft, t.canvas.withValues(alpha: 0)])),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [t.brand, t.accent]),
                        boxShadow: [
                          BoxShadow(
                              color: t.brand.withValues(alpha: 0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 10))
                        ],
                      ),
                      child: const Icon(Icons.apartment_rounded,
                          color: Colors.white, size: 34),
                    ),
                    const SizedBox(height: 20),
                    Text('AapliSocietyy',
                        style: TextStyle(
                            color: t.fg1,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    Text('Member sign in',
                        style: TextStyle(color: t.fg3, fontSize: 13.5)),
                    const SizedBox(height: 30),
                    BlocConsumer<AuthBloc, AuthState>(
                      listener: (context, state) {
                        if (state is AuthError) {
                          Haptics.heavy();
                          showPulseToast(context, state.message,
                              kind: PulseToastKind.error);
                        } else if (state is AuthAuthed) {
                          Haptics.success();
                          if (state.mustChangePassword) {
                            context.go('/change-password',
                                extra: {'forced': true, 'role': state.role, 'kind': state.kind});
                          } else {
                            context.go(homeRouteForProfile(state.role, state.kind));
                          }
                        } else if (state is AuthNeedsProfile) {
                          FlatPickerSheet.show(
                            context,
                            name: state.name,
                            flats: state.profiles,
                            onSelect: (profileId) async {
                              final completer = Completer<String?>();
                              // The bloc owns the call; the sheet only
                              // reports the outcome.
                              _pendingSwitch = completer;
                              context.read<AuthBloc>().add(
                                    SwitchProfileRequested(
                                        profileId, state.selectToken),
                                  );
                              return completer.future;
                            },
                            onCancel: () => context
                                .read<AuthBloc>()
                                .add(LogoutRequested()),
                          );
                        }

                        if (state is AuthAuthed) {
                          _pendingSwitch?.complete(null);
                          _pendingSwitch = null;
                        }
                        if (state is AuthError) {
                          _pendingSwitch?.complete(state.message);
                          _pendingSwitch = null;
                        }
                      },
                      builder: (context, state) {
                        final loading = state is AuthLoading;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _field(t,
                                label: 'Username or email',
                                controller: _id,
                                icon: Icons.person_outline_rounded),
                            const SizedBox(height: 14),
                            _field(
                              t,
                              label: 'Password',
                              controller: _pw,
                              icon: Icons.key_rounded,
                              obscure: _obscure,
                              suffix: IconButton(
                                tooltip: _obscure
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: t.fg3,
                                  size: 19,
                                ),
                                onPressed: () {
                                  Haptics.select();
                                  setState(() => _obscure = !_obscure);
                                },
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: GestureDetector(
                                  onTap: () {
                                    Haptics.select();
                                    context.push('/forgot-password');
                                  },
                                  child: Text('Forgot password?',
                                      style: TextStyle(
                                          color: t.brand,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            PulseButton(
                              label: loading ? 'Signing in…' : 'Sign In',
                              full: true,
                              size: PulseBtnSize.lg,
                              loading: loading,
                              disabled:
                                  _id.text.trim().isEmpty || _pw.text.isEmpty,
                              onTap: () => context.read<AuthBloc>().add(
                                  LoginRequested(_id.text.trim(), _pw.text)),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                "By continuing you agree to the Society's terms & privacy policy",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: t.fg3,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(PulseTokens t,
      {required String label,
      required TextEditingController controller,
      required IconData icon,
      bool obscure = false,
      Widget? suffix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: t.fg3)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border, width: 1.5),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: t.fg1, fontSize: 14.5),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: t.fg4, size: 19),
              suffixIcon: suffix,
              filled: false,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
