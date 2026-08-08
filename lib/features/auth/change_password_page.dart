import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_x.dart';
import '../../core/theme/haptics.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/app_toast.dart';
import 'bloc/auth_bloc.dart';

class ChangePasswordPage extends StatefulWidget {
  /// True when the backend flagged this account as mustChangePassword
  /// (e.g. a newly added member's temp password) - every other route is
  /// blocked server-side until this succeeds, so there's nothing to pop
  /// back to and no way to skip it.
  final bool forced;
  final String? roleForRedirect;
  final String? kindForRedirect;
  const ChangePasswordPage(
      {super.key, this.forced = false, this.roleForRedirect, this.kindForRedirect});
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text.length < 6) {
      Haptics.heavy();
      showAppToast(context, 'Password must be at least 6 characters',
          kind: AppToastKind.alert);
      return;
    }
    if (_next.text != _confirm.text) {
      Haptics.heavy();
      showAppToast(context, 'Passwords do not match', kind: AppToastKind.alert);
      return;
    }
    Haptics.medium();
    setState(() => _busy = true);
    try {
      await context.read<Dio>().post('/auth/change-password', data: {
        'currentPassword': _current.text,
        'newPassword': _next.text,
      });
      if (!mounted) return;
      Haptics.success();
      setState(() => _busy = false);
      showAppToast(context, 'Password updated', kind: AppToastKind.success);
      if (widget.forced) {
        context.go(homeRouteForProfile(
            widget.roleForRedirect ?? 'Member', widget.kindForRedirect ?? 'Residential'));
      } else {
        Navigator.of(context).maybePop();
      }
    } on DioException catch (err) {
      if (!mounted) return;
      Haptics.heavy();
      setState(() => _busy = false);
      showAppToast(context, apiErrorMessage(err, 'Could not update password'),
          kind: AppToastKind.alert);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: !widget.forced,
          title: Text('Change password',
              style: GoogleFonts.fraunces(
                  fontWeight: FontWeight.w600, color: context.headline)),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: AppColors.ledgerGradient,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.brass.withValues(alpha: 0.35),
                        width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          color: AppColors.brass, size: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          widget.forced
                              ? 'Your account was created with a temporary password. Set a new one to continue.'
                              : 'Keep your account secure with a strong password.',
                          style: GoogleFonts.manrope(
                              color: AppColors.paper, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1),
                const SizedBox(height: 22),
                _field(_current, 'Current password'),
                const SizedBox(height: 14),
                _field(_next, 'New password'),
                const SizedBox(height: 14),
                _field(_confirm, 'Confirm new password'),
                const SizedBox(height: 24),
                PrimaryButton(
                    label: 'Update password',
                    icon: Icons.check,
                    ledger: true,
                    loading: _busy,
                    onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) {
    return TextField(
      controller: c,
      obscureText: _obscure,
      style: TextStyle(color: context.headline),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AppColors.brass),
          onPressed: () {
            Haptics.select();
            setState(() => _obscure = !_obscure);
          },
        ),
      ),
    );
  }
}
