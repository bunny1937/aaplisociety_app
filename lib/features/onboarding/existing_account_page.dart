// lib/features/onboarding/existing_account_page.dart
//
// Step 2 for a member whose account is ALREADY set up.
//
// Bhavani clicks "existing account" here and sees the three flats already
// active under her email - which is the confirmation the user asked for:
// "in existing acc click he can see that 3 acc are already done".
//
// It also handles the "register for more flat" case. Note carefully what that
// does and does not mean: a flat can only be CLAIMED, never CREATED. If the
// society admin has not imported that flat against this email, there is
// nothing to claim and the screen says so. There is no form here that writes a
// new member record - that is the whole security posture of this flow.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/haptics.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/press_effect.dart';
import 'data/onboarding_api.dart';
import 'onboarding_gate_page.dart' show kWebFallbackBase;
import 'widgets/flat_chip.dart';
import 'widgets/onboarding_scaffold.dart';

class ExistingAccountPage extends StatelessWidget {
  const ExistingAccountPage({
    super.key,
    required this.result,
    required this.email,
  });

  final LookupResult result;
  final String email;

  @override
  Widget build(BuildContext context) {
    final flats = result.flats;
    final count = flats.length;

    return OnboardingScaffold(
      step: 2,
      totalSteps: 3,
      onBack: () => context.pop(),
      title: 'Welcome back',
      subtitle: count > 1
          ? 'You already have $count flats on one login.'
          : 'Your account is already active.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Identity strip. Confirms which account we are talking about
          // without printing the full email back at an unauthenticated screen.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF818CF8).withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _initials(result.name ?? email),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF818CF8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.name ?? 'Your account',
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.maskedEmail ?? '',
                        style: GoogleFonts.robotoMono(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.48),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded,
                          size: 11, color: Color(0xFF34D399)),
                      const SizedBox(width: 4),
                      Text(
                        'Active',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF34D399),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Text(
                count == 1 ? 'YOUR FLAT' : '$count FLATS ALREADY ACTIVE',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Colors.white.withValues(alpha: 0.38),
                ),
              ),
              const Spacer(),
              if (count > 1)
                Text(
                  'one login',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    color: const Color(0xFF818CF8).withValues(alpha: 0.75),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          ...flats.asMap().entries.map(
                (e) => FlatChip(
                  flat: e.value,
                  trailing: const Icon(Icons.check_circle_rounded,
                      size: 18, color: Color(0xFF34D399)),
                )
                    .animate(delay: (80 * e.key).ms)
                    .fadeIn(duration: 320.ms)
                    .slideX(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
              ),

          if (result.splitAccount) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF92400E).withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFFFCD34D).withValues(alpha: 0.28)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.build_circle_outlined,
                      size: 15, color: Color(0xFFFCD34D)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Some of these flats are on separate legacy records from an '
                      'older import. They still work, but ask your admin to run the '
                      'account merge so switching is instant.',
                      style: GoogleFonts.inter(
                        fontSize: 11.6,
                        height: 1.5,
                        color: const Color(0xFFFDE68A).withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 20),

          // ── Claim another flat ────────────────────────────────────────
          Text(
            'Bought or moved into another flat?',
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Your society admin adds the flat against this same email. It then '
            'appears here automatically \u2014 and in the flat picker when you sign '
            'in. Nothing to fill in, and no second password.',
            style: GoogleFonts.inter(
              fontSize: 12.2,
              height: 1.55,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 14),

          PressEffect(
            onTap: () {
              Haptics.light();
              showAppToast(
                context,
                'Ask your society admin to add the flat against $email. '
                'It will show up here the next time you open this screen.',
                kind: AppToastKind.info,
              );
            },
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_home_outlined,
                      size: 16, color: Colors.white.withValues(alpha: 0.65)),
                  const SizedBox(width: 9),
                  Text(
                    'How do I add another flat?',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 26),

          PressEffect(
            onTap: () {
              Haptics.light();
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
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    result.username != null
                        ? 'Sign in as ${result.username}'
                        : 'Go to sign in',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 17, color: Colors.white),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Center(
            child: TextButton(
              onPressed: () async {
                final uri = Uri.parse('$kWebFallbackBase/forgot-password');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(
                'Forgot your password?',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String s) {
    final parts = s.trim().split(RegExp(r'[\s@._-]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}
