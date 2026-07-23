import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/theme_x.dart';
import 'press_effect.dart';

/// Shared ledger-system list row: icon chip + title/subtitle + trailing
/// value, entrance fade+slide staggered by [index]. Promoted from the
/// dashboard-local card pattern once a second screen (Bills) needed the
/// same shape — see .ui-craft/design-decisions.md.
class LedgerListCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final Widget trailing;
  final VoidCallback? onTap;
  final int index;
  const LedgerListCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    required this.trailing,
    this.onTap,
    this.index = 0,
  });
  @override
  Widget build(BuildContext context) {
    return PressEffect(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.brass
                  .withValues(alpha: context.isDark ? 0.18 : 0.12),
              width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.brass.withValues(alpha: 0.45), width: 1.2),
              ),
              child: Icon(icon, color: AppColors.brass, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: context.headline)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          color: subtitleColor ?? AppColors.inkMuted,
                          fontWeight: subtitleColor != null
                              ? FontWeight.w600
                              : FontWeight.w400)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    )
        .animate(delay: (80 * index).ms)
        .fadeIn(duration: 300.ms)
        .slideX(begin: 0.1);
  }
}

/// Compact status pill for routine list rendering — deliberately NOT the
/// elastic StampBadge, which motion.md reserves for momentous, once-per-view
/// state changes (a detail sheet, a payment settling), not routine list scroll.
class LedgerStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const LedgerStatusPill({super.key, required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: GoogleFonts.manrope(
              fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
    );
  }
}
