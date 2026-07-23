import 'package:flutter/material.dart';
import '../../../core/theme/haptics.dart';
import 'pulse_tokens.dart';

/// Port of Primitives.jsx `Card`. Tappable cards scale to 0.98 on press.
class PulseCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  const PulseCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.radius = PulseTokens.radius,
  });
  @override
  State<PulseCard> createState() => _PulseCardState();
}

class _PulseCardState extends State<PulseCard> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final card = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.color ?? t.surface,
        border: Border.all(color: t.border, width: 1),
        borderRadius: BorderRadius.circular(widget.radius),
        boxShadow: t.shadowCard,
      ),
      child: widget.child,
    );
    if (widget.onTap == null) return card;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        Haptics.light();
        widget.onTap!();
      },
      child: AnimatedScale(
        scale: _down ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: card,
      ),
    );
  }
}
