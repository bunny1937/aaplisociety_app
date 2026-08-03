// lib/features/onboarding/onboarding_gate_page.dart
//
// The screen the activation link lands on.
//
// It asks one question - "what is your email?" - and then the SERVER decides
// which of three doors opens:
//
//   NEW_ACCOUNT       -> straight into setup. No "are you new or existing?"
//                        button, because the server already knows. Asking the
//                        member to self-classify is how you get people picking
//                        the wrong branch and then blaming the app.
//   EXISTING_ACCOUNT  -> the flats already active on this login, and a way
//                        back to sign in.
//   PROHIBITED        -> a hard stop with an explanation. There is deliberately
//                        no "create anyway" escape hatch.
//
// UI shape: a single card that morphs between states. Nothing slides in from
// off-screen; the card grows and its contents cross-fade, so the member never
// loses their place.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/haptics.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/press_effect.dart';
import 'data/onboarding_api.dart';
import 'widgets/onboarding_scaffold.dart';

const String kWebFallbackBase = 'https://aaplisociety.vercel.app';

class OnboardingGatePage extends StatefulWidget {
  const OnboardingGatePage({super.key, this.token});

  /// From the deep link. Null when the member opened this screen manually,
  /// in which case we fall back to society code + flat number as proof.
  final String? token;

  @override
  State<OnboardingGatePage> createState() => _OnboardingGatePageState();
}

enum _Stage { collecting, checking, prohibited, invalidLink }

class _OnboardingGatePageState extends State<OnboardingGatePage> {
  late final _api = OnboardingApi(context.read<Dio>());
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _societyCode = TextEditingController();
  final _flatNo = TextEditingController();
  final _emailFocus = FocusNode();

  _Stage _stage = _Stage.collecting;
  String _message = '';
  LookupResult? _result;

  bool get _hasToken => (widget.token ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emailFocus.requestFocus());
  }

  @override
  void dispose() {
    _email.dispose();
    _societyCode.dispose();
    _flatNo.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      Haptics.medium();
      return;
    }
    FocusScope.of(context).unfocus();
    Haptics.light();
    setState(() => _stage = _Stage.checking);

    final res = await _api.lookup(
      email: _email.text,
      token: widget.token,
      societyCode: _hasToken ? null : _societyCode.text,
      flatNo: _hasToken ? null : _flatNo.text,
    );

    if (!mounted) return;

    switch (res.outcome) {
      case LookupOutcome.newAccount:
        Haptics.success();
        context.push('/onboarding/setup', extra: {
          'token': widget.token,
          'email': _email.text.trim().toLowerCase(),
          'name': res.name,
          'flats': res.flats,
        });
        setState(() => _stage = _Stage.collecting);
        break;

      case LookupOutcome.existingAccount:
        Haptics.success();
        context.push('/onboarding/existing', extra: {
          'result': res,
          'email': _email.text.trim().toLowerCase(),
        });
        setState(() => _stage = _Stage.collecting);
        break;

      case LookupOutcome.linkInvalid:
      case LookupOutcome.linkMismatch:
        Haptics.heavy();
        setState(() {
          _stage = _Stage.invalidLink;
          _message = res.message;
          _result = res;
        });
        break;

      case LookupOutcome.proofRequired:
        Haptics.medium();
        setState(() => _stage = _Stage.collecting);
        showAppToast(context, res.message, kind: AppToastKind.alert);
        break;

      case LookupOutcome.prohibited:
        Haptics.heavy();
        setState(() {
          _stage = _Stage.prohibited;
          _message = res.message;
          _result = res;
        });
        break;
    }
  }

  Future<void> _openWebsite() async {
    // The always-available escape hatch. If anything about the app flow fails,
    // the member can still finish on the website with the same link.
    final url = _hasToken
        ? '$kWebFallbackBase/onboarding/set-credentials?token=${widget.token}'
        : '$kWebFallbackBase/login';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      showAppToast(context, 'Could not open the browser.', kind: AppToastKind.alert);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 1,
      totalSteps: 3,
      title: 'Activate your flat',
      subtitle: _hasToken
          ? 'Confirm the email your invite was sent to.'
          : 'Enter the email your society has on file.',
      child: AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: switch (_stage) {
          _Stage.prohibited => _blocked(context),
          _Stage.invalidLink => _blocked(context, isLink: true),
          _ => _form(context),
        },
      ),
    );
  }

  Widget _form(BuildContext context) {
    final busy = _stage == _Stage.checking;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            controller: _email,
            focusNode: _emailFocus,
            label: 'Email address',
            hint: 'you@example.com',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            enabled: !busy,
            autofillHints: const [AutofillHints.email],
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'Enter your email address.';
              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s)) {
                return 'That does not look like a valid email.';
              }
              return null;
            },
          ),

          // Without a signed link we need some other proof the caller belongs
          // to the flat, otherwise this screen becomes an email-checker for
          // anyone who downloads the app.
          if (!_hasToken) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _Field(
                    controller: _societyCode,
                    label: 'Society code',
                    hint: 'e.g. SUN2024',
                    icon: Icons.apartment_rounded,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _Field(
                    controller: _flatNo,
                    label: 'Flat no.',
                    hint: '101',
                    icon: Icons.meeting_room_rounded,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const _Note(
              icon: Icons.shield_outlined,
              text:
                  'We ask for these so nobody can use this screen to find out '
                  'whether an email is registered.',
            ),
          ],

          const SizedBox(height: 22),

          PressEffect(
            onTap: busy ? null : _check,
            child: _PrimaryButton(
              busy: busy,
              label: busy ? 'Checking\u2026' : 'Continue',
            ),
          ),

          const SizedBox(height: 14),

          Center(
            child: TextButton(
              onPressed: _openWebsite,
              child: Text(
                'Continue on the website instead',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.62),
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white24,
                ),
              ),
            ),
          ),
        ],
      ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
    );
  }

  Widget _blocked(BuildContext context, {bool isLink = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF7F1D1D).withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.32)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      color: Color(0xFFFCA5A5), size: 20),
                  const SizedBox(width: 10),
                  Text(
                    isLink ? 'Link not usable' : 'Not registered',
                    style: GoogleFonts.fraunces(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFFECACA),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _message,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  height: 1.55,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
              if (_result?.maskedEmail != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Checked: ${_result!.maskedEmail}',
                  style: GoogleFonts.robotoMono(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        )
            .animate()
            .fadeIn(duration: 240.ms)
            .shake(hz: 3, offset: const Offset(3, 0), duration: 400.ms),

        const SizedBox(height: 18),

        _Note(
          icon: Icons.info_outline_rounded,
          text: isLink
              ? 'Activation links expire after 7 days. Your society admin can send a new one.'
              : 'Accounts are created by your society admin during setup. They cannot be '
                'created from this app \u2014 that is what stops someone claiming a flat that is not theirs.',
        ),

        const SizedBox(height: 22),

        PressEffect(
          onTap: () {
            Haptics.light();
            setState(() => _stage = _Stage.collecting);
          },
          child: const _SecondaryButton(label: 'Try a different email'),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => context.go('/login'),
            child: Text(
              'Back to sign in',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.focusNode,
    this.validator,
    this.keyboardType,
    this.enabled = true,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.obscure = false,
    this.suffix,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool enabled;
  final bool obscure;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      validator: validator,
      keyboardType: keyboardType,
      enabled: enabled,
      obscureText: obscure,
      autofillHints: autofillHints,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      style: GoogleFonts.inter(fontSize: 14.5, color: Colors.white),
      cursorColor: const Color(0xFF818CF8),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.5)),
        suffixIcon: suffix,
        labelStyle: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
        hintStyle: GoogleFonts.inter(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.26)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF818CF8), width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.6),
        ),
        errorStyle: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFFFCA5A5)),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.38)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11.8,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.44),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, this.busy = false});
  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: busy ? 0.12 : 0.34),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
            )
          : Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
          color: Colors.white.withValues(alpha: 0.86),
        ),
      ),
    );
  }
}

// Re-exported so the sibling screens use identical inputs.
class OnboardingField extends StatelessWidget {
  const OnboardingField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.focusNode,
    this.validator,
    this.keyboardType,
    this.enabled = true,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.obscure = false,
    this.suffix,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool enabled;
  final bool obscure;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return _Field(
      controller: controller,
      label: label,
      icon: icon,
      hint: hint,
      focusNode: focusNode,
      validator: validator,
      keyboardType: keyboardType,
      enabled: enabled,
      obscure: obscure,
      suffix: suffix,
      autofillHints: autofillHints,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
    );
  }
}
