import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/haptics.dart';
import '../member/pulse/pulse.dart';
import 'bloc/password_reset_bloc.dart';

class ResetPasswordPage extends StatelessWidget {
  final String identifier;
  const ResetPasswordPage({super.key, required this.identifier});
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => PasswordResetBloc(ctx.read<Dio>()),
      child: _ResetPasswordView(identifier: identifier),
    );
  }
}

class _ResetPasswordView extends StatefulWidget {
  final String identifier;
  const _ResetPasswordView({required this.identifier});
  @override
  State<_ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<_ResetPasswordView> {
  final _code = TextEditingController();
  final _newPw = TextEditingController();
  final _confirmPw = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _code.dispose();
    _newPw.dispose();
    _confirmPw.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    if (_code.text.trim().length != 6) {
      Haptics.heavy();
      showPulseToast(context, 'Enter the 6-digit code from your email', kind: PulseToastKind.error);
      return;
    }
    if (_newPw.text.length < 6) {
      Haptics.heavy();
      showPulseToast(context, 'Password must be at least 6 characters', kind: PulseToastKind.error);
      return;
    }
    if (_newPw.text != _confirmPw.text) {
      Haptics.heavy();
      showPulseToast(context, 'Passwords do not match', kind: PulseToastKind.error);
      return;
    }
    context.read<PasswordResetBloc>().add(
      ResetPasswordRequested(widget.identifier, _code.text.trim(), _newPw.text),
    );
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
                Text('Enter reset code', style: TextStyle(color: t.fg1, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                const SizedBox(height: 6),
                Text(
                  'Check your email for the 6-digit code, then set a new password.',
                  style: TextStyle(color: t.fg4, fontSize: 13.5),
                ),
                const SizedBox(height: 26),
                BlocConsumer<PasswordResetBloc, PasswordResetState>(
                  listener: (context, state) {
                    if (state is PasswordResetError) {
                      Haptics.heavy();
                      showPulseToast(context, state.message, kind: PulseToastKind.error);
                    } else if (state is PasswordResetSuccess) {
                      Haptics.success();
                      showPulseToast(context, 'Password updated — sign in with your new password', kind: PulseToastKind.success);
                      context.go('/login');
                    } else if (state is PasswordResetCodeSent) {
                      Haptics.success();
                      showPulseToast(context, 'New code sent', kind: PulseToastKind.success);
                    }
                  },
                  builder: (context, state) {
                    final loading = state is PasswordResetLoading;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _field(t, label: '6-digit code', controller: _code, icon: Icons.pin_outlined),
                        const SizedBox(height: 14),
                        _field(
                          t,
                          label: 'New password',
                          controller: _newPw,
                          icon: Icons.key_rounded,
                          obscure: _obscure,
                          suffix: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: t.fg4, size: 19),
                            onPressed: () { Haptics.select(); setState(() => _obscure = !_obscure); },
                          ),
                        ),
                        const SizedBox(height: 14),
                        _field(t, label: 'Confirm new password', controller: _confirmPw, icon: Icons.key_rounded, obscure: _obscure),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: loading
                                ? null
                                : () {
                                    Haptics.select();
                                    context.read<PasswordResetBloc>().add(ForgotPasswordRequested(widget.identifier));
                                  },
                            child: Text('Resend code', style: TextStyle(color: t.brand, fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        PulseButton(
                          label: loading ? 'Resetting…' : 'Reset password',
                          full: true,
                          size: PulseBtnSize.lg,
                          loading: loading,
                          disabled: _code.text.trim().isEmpty || _newPw.text.isEmpty || _confirmPw.text.isEmpty,
                          onTap: () => _submit(context),
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

  Widget _field(PulseTokens t, {required String label, required TextEditingController controller, required IconData icon, bool obscure = false, Widget? suffix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.fg3)),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
