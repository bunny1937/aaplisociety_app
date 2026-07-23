import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../features/member/pulse/pulse.dart';

/// Guard-facing visitor row, shared by the Security feature's Gate and Log
/// tabs. Restyled onto the Pulse token system (was AppColors/GoogleFonts) —
/// this widget has no other consumers (verified via grep), so retheming it
/// carries no risk to Member screens.
class LedgerVisitorCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final String? status;
  final Color? statusColor;
  final Color? tint;
  final Widget? actions;
  final int index;
  const LedgerVisitorCard({
    super.key,
    required this.name,
    required this.subtitle,
    this.status,
    this.statusColor,
    this.tint,
    this.actions,
    this.index = 0,
  });
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint ?? t.surface,
        borderRadius: BorderRadius.circular(PulseTokens.radius),
        border: Border.all(color: t.border, width: 1),
        boxShadow: t.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulseAvatar(name: name, size: 42),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: t.fg1)),
                    Text(subtitle,
                        style: TextStyle(fontSize: 12.5, color: t.fg3)),
                  ],
                ),
              ),
              if (status != null && status!.isNotEmpty)
                Text(status!,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: statusColor ?? t.fg3,
                        fontWeight: FontWeight.w700)),
            ],
          ),
          if (actions != null) ...[
            const SizedBox(height: 12),
            actions!,
          ],
        ],
      ),
    )
        .animate(delay: (80 * index).ms)
        .fadeIn(duration: 300.ms)
        .slideX(begin: 0.1);
  }
}
