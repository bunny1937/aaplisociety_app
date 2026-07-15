import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/theme_x.dart';
import '../theme/haptics.dart';

/// Ledger-styled selectable chip — replaces the default Material `ChoiceChip`
/// (components.md: Chip/Tag). Brass-tinted fill when selected, hairline
/// outline when not.
class LedgerChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const LedgerChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { Haptics.select(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.brass : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.brass : AppColors.inkMuted.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            color: selected ? AppColors.ink : context.headline,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
