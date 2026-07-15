import 'package:flutter/material.dart';
import '../../../core/theme/haptics.dart';
import 'pulse_tokens.dart';

class PulseSegmentedOption<T> {
  final T value;
  final String label;
  final int? count;
  final IconData? icon;
  const PulseSegmentedOption({required this.value, required this.label, this.count, this.icon});
}

/// Port of Primitives.jsx `Segmented` — horizontally-scrolling filter pill
/// row, replaces the current app's `Wrap`-of-`LedgerChip` filter pattern.
class PulseSegmented<T> extends StatelessWidget {
  final List<PulseSegmentedOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool small;

  const PulseSegmented({super.key, required this.options, required this.value, required this.onChanged, this.small = false});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return SizedBox(
      height: small ? 32 : 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final o = options[i];
          final active = o.value == value;
          return GestureDetector(
            onTap: () { Haptics.select(); onChanged(o.value); },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: small ? 10 : 13, vertical: small ? 5 : 6),
              decoration: BoxDecoration(
                color: active ? t.brandSoft : t.surface,
                border: Border.all(color: active ? t.brand : t.border, width: 1.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (o.icon != null) ...[Icon(o.icon, size: 12, color: active ? t.brand : t.fg3), const SizedBox(width: 5)],
                  Text(o.label, style: TextStyle(fontSize: small ? 11.5 : 12.5, fontWeight: FontWeight.w700, color: active ? t.brand : t.fg3)),
                  if (o.count != null) Text('  ${o.count}', style: TextStyle(fontSize: small ? 11.5 : 12.5, fontWeight: FontWeight.w700, color: (active ? t.brand : t.fg3).withValues(alpha: 0.65))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
