import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_colors.dart';
import '../theme/theme_x.dart';

/// Shimmer skeleton for list screens — replaces the bare spinner AsyncView
/// falls back to by default. Shape mirrors a real LedgerListCard row so the
/// loading state doesn't jump/reflow once data arrives.
class LedgerListSkeleton extends StatelessWidget {
  final int rows;
  const LedgerListSkeleton({super.key, this.rows = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      itemCount: rows,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => Container(
        height: 72,
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.brass.withValues(alpha: context.isDark ? 0.12 : 0.08), width: 1),
        ),
      )
          .animate(onPlay: (c) => c.repeat())
          .shimmer(duration: 1200.ms, color: AppColors.brass.withValues(alpha: 0.16)),
    );
  }
}
