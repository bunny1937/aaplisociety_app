import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/theme_x.dart';

class TimelineStage {
  final String label;
  final String? timestamp;
  final String? note;
  final Color color;
  const TimelineStage({required this.label, this.timestamp, this.note, required this.color});
}

/// Vertical stage timeline. Only render stages backed by real data — no
/// synthetic intermediate steps. Today's only consumer (Complaints) has just
/// `createdAt` + current `status`/`updatedAt`, so it renders 2 stages; a full
/// multi-transition audit trail needs a backend status-history field first
/// (see .ui-craft/design-decisions.md).
class LedgerTimeline extends StatelessWidget {
  final List<TimelineStage> stages;
  const LedgerTimeline({super.key, required this.stages});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: stages.asMap().entries.map((e) {
        final i = e.key;
        final s = e.value;
        final last = i == stages.length - 1;
        return Padding(
          padding: EdgeInsets.only(bottom: last ? 0 : 4),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                    if (!last) Expanded(child: Container(width: 1.4, color: AppColors.inkMuted.withValues(alpha: 0.25))),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.label, style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14, color: context.headline)),
                        if (s.timestamp != null)
                          Text(s.timestamp!, style: GoogleFonts.ibmPlexMono(fontSize: 11.5, color: AppColors.inkMuted)),
                        if (s.note != null && s.note!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(s.note!, style: GoogleFonts.manrope(fontSize: 13, color: context.headline)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ).animate(delay: (80 * i).ms).fadeIn(duration: 250.ms);
      }).toList(),
    );
  }
}
