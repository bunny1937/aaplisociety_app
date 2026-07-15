import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/theme_x.dart';

/// Shared visitor entry row — used by Visitor History today; Security shell
/// (ui-audit-plan.md roadmap step 8) is the planned second consumer, so this
/// is built as a Shared Component directly rather than a screen-local one.
class LedgerVisitorCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final String? status;
  final Color? statusColor;
  final Widget? actions;
  final int index;
  const LedgerVisitorCard({
    super.key,
    required this.name,
    required this.subtitle,
    this.status,
    this.statusColor,
    this.actions,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brass.withValues(alpha: context.isDark ? 0.18 : 0.12), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: AppColors.brass.withValues(alpha: 0.14),
                child: const Icon(Icons.person_rounded, color: AppColors.brass),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14.5, color: context.headline)),
                    Text(subtitle, style: GoogleFonts.manrope(fontSize: 12.5, color: AppColors.inkMuted)),
                  ],
                ),
              ),
              if (status != null && status!.isNotEmpty)
                Text(status!, style: GoogleFonts.manrope(fontSize: 12.5, color: statusColor ?? AppColors.inkMuted, fontWeight: FontWeight.w700)),
            ],
          ),
          if (actions != null) ...[
            const SizedBox(height: 12),
            actions!,
          ],
        ],
      ),
    ).animate(delay: (80 * index).ms).fadeIn(duration: 300.ms).slideX(begin: 0.1);
  }
}
