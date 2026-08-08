// lib/features/onboarding/new_account_setup_page.dart
//
// Step 2 for a member whose account exists but has never been set up.
// Same four inputs as the website: username, re-entered email, password,
// confirm password.
//
// Two things this screen does that the website does not:
//
// 1. It shows the flats being activated BEFORE asking for a password, so
//    Bhavani can see "you are activating 101, 201 and 401" and understands why
//    there is only one password to set. Without this, three flats and one
//    password reads like a bug.
//
// 2. Every rule is checked live as you type, with the same wording the server
//    uses. The submit button does not enable until all of them pass, so a
//    round trip can only fail on username collision - the one thing the client
//    genuinely cannot know.
//
// The client checks are UX. /api/onboarding/activate re-checks all of them.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/haptics.dart';
import '../../core/widgets/press_effect.dart';
import 'data/onboarding_api.dart';
import 'onboarding_gate_page.dart' show OnboardingField;
import 'widgets/flat_chip.dart';
import 'widgets/onboarding_scaffold.dart';

class NewAccountSetupPage extends StatefulWidget {
  const NewAccountSetupPage({
    super.key,
    required this.token,
    required this.email,
    this.name,
    this.flats = const [],
  });

  final String token;
  final String email;
  final String? name;
  final List<ProfileSummary> flats;

  @override
  State<NewAccountSetupPage> createState() => _NewAccountSetupPageState();
}

class _NewAccountSetupPageState extends State<NewAccountSetupPage> {
  late final _api = OnboardingApi(context.read<Dio>());

  final _username = TextEditingController();
  final _emailConfirm = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscurePw = true;
  bool _obscureConfirm = true;
  bool _busy = false;
  bool _done = false;
  String? _serverError;
  List<ProfileSummary> _activated = const [];

  // ── Live rules, worded exactly like the server ──────────────────────────
  static final _usernameRe = RegExp(r'^[a-z0-9_-]{4,30}$');

  static const _reserved = {
    'admin', 'administrator', 'superadmin', 'root', 'system', 'support',
    'security', 'guard', 'watchman', 'secretary', 'treasurer', 'accountant',
    'auditor', 'society', 'aaplisociety', 'help', 'billing', 'noreply',
    'no-reply', 'postmaster', 'webmaster', 'test', 'null', 'undefined',
  };

  static const _weak = {
    'password1', 'passw0rd', 'abcd1234', 'admin123', 'member123', 'welcome1',
    'qwerty123', '123456a', 'a123456', 'pass1234', 'society1', 'flat1234',
  };

  String get _u => _username.text.trim().toLowerCase();
  String get _p => _password.text;

  bool get _uFormatOk => _usernameRe.hasMatch(_u);
  bool get _uNotReserved => _u.isEmpty || !_reserved.contains(_u);
  bool get _emailMatches =>
      _emailConfirm.text.trim().toLowerCase() == widget.email.toLowerCase();

  bool get _pLength => _p.length >= 6;
  bool get _pLetterDigit =>
      RegExp(r'[a-zA-Z]').hasMatch(_p) && RegExp(r'[0-9]').hasMatch(_p);
  bool get _pNotCommon => _p.isEmpty || !_weak.contains(_p.toLowerCase());

  bool get _pNotPersonal {
    if (_p.isEmpty) return true;
    final lower = _p.toLowerCase();
    if (_u.isNotEmpty && lower.contains(_u)) return false;
    final localPart = widget.email.split('@').first.toLowerCase();
    if (localPart.isNotEmpty && lower.contains(localPart)) return false;
    final first = (widget.name ?? '').trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (first.length >= 4 && lower.contains(first)) return false;
    for (final f in widget.flats) {
      final flat = (f.flatNo ?? '').toLowerCase();
      if (flat.length >= 3 && lower.contains(flat)) return false;
    }
    return true;
  }

  bool get _pMatches => _confirm.text.isNotEmpty && _confirm.text == _p;

  bool get _canSubmit =>
      !_busy &&
      _uFormatOk &&
      _uNotReserved &&
      _emailMatches &&
      _pLength &&
      _pLetterDigit &&
      _pNotCommon &&
      _pNotPersonal &&
      _pMatches;

  /// 0..4, drives the strength bar. Not a security control, just feedback.
  int get _strength {
    if (_p.isEmpty) return 0;
    var s = 0;
    if (_p.length >= 8) s++;
    if (_p.length >= 12) s++;
    if (RegExp(r'[a-z]').hasMatch(_p) && RegExp(r'[A-Z]').hasMatch(_p)) s++;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(_p)) s++;
    return s.clamp(0, 4);
  }

  @override
  void dispose() {
    _username.dispose();
    _emailConfirm.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      Haptics.medium();
      return;
    }
    FocusScope.of(context).unfocus();
    Haptics.light();
    setState(() {
      _busy = true;
      _serverError = null;
    });

    final res = await _api.activate(
      token: widget.token,
      username: _u,
      email: _emailConfirm.text,
      password: _p,
      confirmPassword: _confirm.text,
    );

    if (!mounted) return;

    if (res.success) {
      Haptics.success();
      setState(() {
        _busy = false;
        _done = true;
        _activated = res.flats;
      });
    } else {
      Haptics.heavy();
      setState(() {
        _busy = false;
        _serverError = res.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _successScreen();

    final multi = widget.flats.length > 1;

    return OnboardingScaffold(
      step: 2,
      totalSteps: 3,
      onBack: _busy ? null : () => context.pop(),
      title: 'Set up your login',
      subtitle: multi
          ? 'One login for all ${widget.flats.length} of your flats.'
          : 'Choose a username and password.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.flats.isNotEmpty) ...[
            _SectionLabel(
              multi
                  ? 'Activating ${widget.flats.length} flats'
                  : 'Activating this flat',
            ),
            const SizedBox(height: 10),
            ...widget.flats.map((f) => FlatChip(flat: f, dense: true)),
            if (multi) ...[
              const SizedBox(height: 4),
              const _InfoStrip(
                icon: Icons.swap_horiz_rounded,
                text:
                    'You will pick which flat to open each time you sign in \u2014 '
                    'and switch any time from your profile.',
              ),
            ],
            const SizedBox(height: 22),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 22),
          ],

          OnboardingField(
            controller: _username,
            label: 'Choose a username',
            hint: 'bhavani_101',
            icon: Icons.person_outline_rounded,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          _Rule('4\u201330 characters: a\u2013z, 0\u20139, hyphen or underscore',
              ok: _uFormatOk, show: _username.text.isNotEmpty),
          _Rule('Not a reserved name',
              ok: _uNotReserved, show: _username.text.isNotEmpty && _uFormatOk),

          const SizedBox(height: 18),

          OnboardingField(
            controller: _emailConfirm,
            label: 'Re-enter your email',
            hint: 'the address your invite was sent to',
            icon: Icons.mark_email_read_outlined,
            keyboardType: TextInputType.emailAddress,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          _Rule('Matches the email on your invite',
              ok: _emailMatches, show: _emailConfirm.text.isNotEmpty),

          const SizedBox(height: 18),

          OnboardingField(
            controller: _password,
            label: 'Password',
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePw,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            suffix: _EyeButton(
              obscured: _obscurePw,
              onTap: () => setState(() => _obscurePw = !_obscurePw),
            ),
          ),
          const SizedBox(height: 10),
          if (_password.text.isNotEmpty) _StrengthBar(level: _strength),
          const SizedBox(height: 8),
          _Rule('At least 6 characters', ok: _pLength, show: _p.isNotEmpty),
          _Rule('Contains a letter and a number',
              ok: _pLetterDigit, show: _p.isNotEmpty),
          _Rule('Not a commonly used password',
              ok: _pNotCommon, show: _p.isNotEmpty),
          _Rule('Does not contain your name, email or flat number',
              ok: _pNotPersonal, show: _p.isNotEmpty),

          const SizedBox(height: 18),

          OnboardingField(
            controller: _confirm,
            label: 'Confirm password',
            icon: Icons.lock_reset_rounded,
            obscure: _obscureConfirm,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            suffix: _EyeButton(
              obscured: _obscureConfirm,
              onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          const SizedBox(height: 8),
          _Rule('Both passwords match', ok: _pMatches, show: _confirm.text.isNotEmpty),

          if (_serverError != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF7F1D1D).withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.34)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 17, color: Color(0xFFFCA5A5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _serverError!,
                      style: GoogleFonts.inter(
                        fontSize: 12.8,
                        height: 1.5,
                        color: const Color(0xFFFECACA),
                      ),
                    ),
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(duration: 200.ms)
                .shake(hz: 3.5, offset: const Offset(2.5, 0), duration: 380.ms),
          ],

          const SizedBox(height: 24),

          PressEffect(
            onTap: _canSubmit ? _submit : null,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _canSubmit ? 1 : 0.42,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _canSubmit
                      ? [
                          BoxShadow(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.34),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : Text(
                        widget.flats.length > 1
                            ? 'Activate all ${widget.flats.length} flats'
                            : 'Activate my account',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _successScreen() {
    return OnboardingScaffold(
      step: 3,
      totalSteps: 3,
      title: 'You are all set',
      subtitle: _activated.length > 1
          ? 'All ${_activated.length} flats are active under one login.'
          : 'Your account is active.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.4), width: 2),
              ),
              child: const Icon(Icons.check_rounded, size: 36, color: Color(0xFF34D399)),
            )
                .animate()
                .scale(
                  begin: const Offset(0.5, 0.5),
                  end: const Offset(1, 1),
                  duration: 480.ms,
                  curve: Curves.elasticOut,
                )
                .fadeIn(duration: 220.ms),
          ),
          const SizedBox(height: 24),
          const _SectionLabel('Signed in as'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: Row(
              children: [
                Icon(Icons.person_rounded, size: 17, color: Colors.white.withValues(alpha: 0.5)),
                const SizedBox(width: 10),
                Text(
                  _u,
                  style: GoogleFonts.robotoMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _SectionLabel(
            _activated.length > 1
                ? '${_activated.length} flats activated'
                : 'Flat activated',
          ),
          const SizedBox(height: 10),
          ..._activated.asMap().entries.map(
                (e) => FlatChip(flat: e.value, dense: true)
                    .animate(delay: (90 * e.key).ms)
                    .fadeIn(duration: 300.ms)
                    .slideX(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
              ),
          const SizedBox(height: 18),
          const _InfoStrip(
            icon: Icons.touch_app_rounded,
            text:
                'Sign in with your username or email. We will ask which flat to '
                'open every time \u2014 no separate passwords to remember.',
          ),
          const SizedBox(height: 26),
          PressEffect(
            onTap: () {
              Haptics.light();
              // Straight to login. Activation deliberately does not create a
              // session, so there is exactly one place a session can start.
              context.go('/login');
            },
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Sign in now',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
class _Rule extends StatelessWidget {
  const _Rule(this.text, {required this.ok, this.show = true});
  final String text;
  final bool ok;
  final bool show;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topLeft,
      child: !show
          ? const SizedBox(width: double.infinity, height: 0)
          : Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      ok ? Icons.check_circle_rounded : Icons.circle_outlined,
                      key: ValueKey(ok),
                      size: 13,
                      color: ok
                          ? const Color(0xFF34D399)
                          : Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: GoogleFonts.inter(
                        fontSize: 11.6,
                        height: 1.4,
                        color: ok
                            ? const Color(0xFF34D399).withValues(alpha: 0.85)
                            : Colors.white.withValues(alpha: 0.44),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.level});
  final int level;

  static const _labels = ['Weak', 'Weak', 'Fair', 'Good', 'Strong'];
  static const _colors = [
    Color(0xFFEF4444),
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF34D399),
    Color(0xFF10B981),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ...List.generate(
          4,
          (i) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 3 ? 0 : 5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                height: 3,
                decoration: BoxDecoration(
                  color: i < level ? _colors[level] : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(
            _labels[level],
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: _colors[level].withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
    );
  }
}

class _EyeButton extends StatelessWidget {
  const _EyeButton({required this.obscured, required this.onTap});
  final bool obscured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        size: 18,
        color: Colors.white.withValues(alpha: 0.45),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: Colors.white.withValues(alpha: 0.38),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF4F46E5).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF818CF8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 11.8,
                height: 1.5,
                color: Colors.white.withValues(alpha: 0.66),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
