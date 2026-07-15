import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Rotated ink-stamp mark, like the rubber "PAID" / "DUE" stamp on a
/// resident's physical maintenance passbook. Lands with a stamp-thud
/// entrance instead of a plain fade.
class StampBadge extends StatelessWidget {
  final String label;
  final bool settled;
  const StampBadge({super.key, required this.label, required this.settled});

  @override
  Widget build(BuildContext context) {
    final color = settled ? AppColors.stampGreen : AppColors.stampRed;
    return Transform.rotate(
      angle: -0.12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.85), width: 1.6),
          borderRadius: BorderRadius.circular(8),
          color: color.withValues(alpha: 0.08),
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexMono(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            letterSpacing: 2,
          ),
        ),
      ),
    )
        .animate()
        .scale(
          begin: const Offset(1.8, 1.8),
          end: const Offset(1, 1),
          duration: 420.ms,
          curve: Curves.elasticOut,
          delay: 260.ms,
        )
        .fadeIn(duration: 160.ms, delay: 260.ms);
  }
}
