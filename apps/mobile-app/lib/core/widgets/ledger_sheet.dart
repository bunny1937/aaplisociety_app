import 'package:flutter/material.dart';
import '../theme/theme_x.dart';

/// Shared drag-handle + chrome for bottom sheets — extracted after the same
/// handle block was copy-pasted across bills/profile/complaints/admin sheets
/// (see .ui-craft/design-decisions.md). Wrap sheet content's Column with this
/// instead of hand-rolling the handle each time.
class LedgerSheetHandle extends StatelessWidget {
  const LedgerSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: context.isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
