// lib/features/onboarding/widgets/flat_chip.dart
//
// One flat, rendered the same way in three places: the "already activated"
// list, the activation summary, and the post-login flat picker. Sharing the
// widget is what makes Bhavani recognise the same three cards each time.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/onboarding_api.dart';

class FlatChip extends StatelessWidget {
  const FlatChip({
    super.key,
    required this.flat,
    this.selected = false,
    this.onTap,
    this.trailing,
    this.dense = false,
  });

  final ProfileSummary flat;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final isOwner = !flat.isCommercial && flat.occupancyType?.toLowerCase() == 'owner';
    final accent = flat.isCommercial
        ? const Color(0xFFF59E0B) // amber — visually distinct from the flat owner/tenant indigo/green
        : (isOwner ? const Color(0xFF818CF8) : const Color(0xFF34D399));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.only(bottom: dense ? 8 : 10),
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? accent.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.09),
          width: selected ? 1.5 : 1,
        ),
        boxShadow: selected
            ? [BoxShadow(color: accent.withValues(alpha: 0.22), blurRadius: 16, offset: const Offset(0, 4))]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: dense ? 11 : 14,
            ),
            child: Row(
              children: [
                // Flat number as the hero. When you own three flats, the number
                // is the only thing you scan for.
                Container(
                  width: dense ? 44 : 50,
                  height: dense ? 44 : 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: flat.isCommercial
                      ? Icon(Icons.storefront_rounded, color: accent, size: dense ? 20 : 22)
                      : Text(
                          flat.flatNo ?? '',
                          style: GoogleFonts.robotoMono(
                            fontSize: dense ? 14 : 15.5,
                            fontWeight: FontWeight.w700,
                            color: accent,
                            letterSpacing: -0.4,
                          ),
                        ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              flat.isCommercial
                                  ? (flat.tradeName ?? 'Shop ${flat.shopNo ?? ""}')
                                  : (flat.wing != null && flat.wing!.isNotEmpty
                                      ? 'Wing ${flat.wing} \u00b7 Flat ${flat.flatNo}'
                                      : 'Flat ${flat.flatNo}'),
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: dense ? 13.5 : 14.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                            ),
                          ),
                          if (flat.isPrimary) ...[
                            const SizedBox(width: 7),
                            const _Tag(text: 'Primary', color: Color(0xFF818CF8)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        flat.isCommercial
                            ? '${flat.societyName} \u00b7 ${flat.unitKind ?? "Shop"}'
                            : '${flat.societyName} \u00b7 ${flat.occupancyType}',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      if (flat.split) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 12, color: Color(0xFFFCD34D)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'On a separate legacy record \u2014 merges when you finish setup',
                                style: GoogleFonts.inter(
                                  fontSize: 10.8,
                                  height: 1.35,
                                  color: const Color(0xFFFCD34D).withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                if (trailing == null && onTap != null)
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    size: selected ? 21 : 20,
                    color: selected ? accent : Colors.white.withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
