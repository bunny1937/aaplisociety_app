// lib/features/onboarding/widgets/onboarding_scaffold.dart
//
// Shared chrome for the three onboarding screens: the ink gradient background
// already used by login/splash, a step rail, and a card that holds the body.
//
// Keeping this in one place is what makes the flow feel like one continuous
// screen rather than three separate pages - only the card contents change
// between steps, so the header and progress rail never jump.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';

class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.step = 1,
    this.totalSteps = 3,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final int step;
  final int totalSteps;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.ink, Color(0xFF0E1A44), AppColors.inkRaised],
          ),
        ),
        child: Stack(
          children: [
            // Two soft indigo blooms. Positioned, never animated - a moving
            // blur on a form screen costs more than it adds.
            Positioned(
              top: -110,
              right: -80,
              child: _Bloom(size: 300, color: const Color(0xFF6366F1).withValues(alpha: 0.20)),
            ),
            Positioned(
              bottom: -140,
              left: -100,
              child: _Bloom(size: 340, color: const Color(0xFF4F46E5).withValues(alpha: 0.14)),
            ),

            SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 22,
                  right: 22,
                  top: 8,
                  bottom: media.viewInsets.bottom + 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),

                      Row(
                        children: [
                          if (onBack != null)
                            _CircleIcon(icon: Icons.arrow_back_rounded, onTap: onBack!),
                          if (onBack != null) const SizedBox(width: 12),
                          Expanded(child: _StepRail(step: step, total: totalSteps)),
                        ],
                      ),

                      const SizedBox(height: 30),

                      Text(
                        title,
                        style: GoogleFonts.fraunces(
                          fontSize: 30,
                          height: 1.12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 380.ms)
                          .slideY(begin: 0.16, end: 0, curve: Curves.easeOutCubic),

                      if (subtitle != null) ...[
                        const SizedBox(height: 9),
                        Text(
                          subtitle!,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            height: 1.55,
                            color: Colors.white.withValues(alpha: 0.60),
                          ),
                        )
                            .animate(delay: 70.ms)
                            .fadeIn(duration: 380.ms)
                            .slideY(begin: 0.16, end: 0, curve: Curves.easeOutCubic),
                      ],

                      const SizedBox(height: 26),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.055),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                            ),
                            child: child,
                          ),
                        ),
                      )
                          .animate(delay: 120.ms)
                          .fadeIn(duration: 420.ms)
                          .slideY(begin: 0.10, end: 0, curve: Curves.easeOutCubic),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final done = i < step;
        final current = i == step - 1;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              height: 3.5,
              decoration: BoxDecoration(
                color: done
                    ? (current ? const Color(0xFF818CF8) : const Color(0xFF6366F1))
                    : Colors.white.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(99),
                boxShadow: current
                    ? [
                        BoxShadow(
                          color: const Color(0xFF818CF8).withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
        ),
        child: Icon(icon, size: 17, color: Colors.white.withValues(alpha: 0.8)),
      ),
    );
  }
}

class _Bloom extends StatelessWidget {
  const _Bloom({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
