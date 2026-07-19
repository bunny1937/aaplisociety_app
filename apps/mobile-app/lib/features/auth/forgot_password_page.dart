import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/haptics.dart';
import '../member/pulse/pulse.dart';
import 'bloc/password_reset_bloc.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => PasswordResetBloc(ctx.read<Dio>()),
      child: const _ForgotPasswordView(),
    );
  }
}

class _ForgotPasswordView extends StatefulWidget {
  const _ForgotPasswordView();
  @override
  State<_ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<_ForgotPasswordView> {
  final _id = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Scaffold(
      backgroundColor: t.canvas,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, foregroundColor: t.fg1),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Forgot password?', style: TextStyle(color: t.fg1, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                const SizedBox(height: 6),
                Text(
                  "Enter your username or email and we'll send a reset code to the email on your account.",
                  style: TextStyle(color: t.fg4, fontSize: 13.5),
                ),
                const SizedBox(height: 26),
                BlocConsumer<PasswordResetBloc, PasswordResetState>(
                  listener: (context, state) {
                    if (state is PasswordResetError) {
                      Haptics.heavy();
                      showPulseToast(context, state.message, kind: PulseToastKind.error);
                    } else if (state is PasswordResetCodeSent) {
                      Haptics.success();
                      // Deliberately non-committal: the backend always returns success here
                      // regardless of whether the identifier matched an account, so this
                      // can't confirm an email was actually sent without leaking account
                      // existence (see docs/superpowers/specs/2026-07-19-mobile-forgot-password-design.md).
                      showPulseToast(context, "If that account exists, a reset code is on its way", kind: PulseToastKind.success);
                      context.push('/reset-password', extra: {'identifier': _id.text.trim()});
                    }
                  },
                  builder: (context, state) {
                    final loading = state is PasswordResetLoading;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Username or email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.fg3)),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: t.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: t.border, width: 1.5),
                          ),
                          child: TextField(
                            controller: _id,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(color: t.fg1, fontSize: 14.5),
                            decoration: InputDecoration(
                              prefixIcon: Icon(Icons.person_outline_rounded, color: t.fg4, size: 19),
                              filled: false,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        PulseButton(
                          label: loading ? 'Sending…' : 'Send reset code',
                          full: true,
                          size: PulseBtnSize.lg,
                          loading: loading,
                          disabled: _id.text.trim().isEmpty,
                          onTap: () => context.read<PasswordResetBloc>().add(ForgotPasswordRequested(_id.text.trim())),
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
    );
  }
}
