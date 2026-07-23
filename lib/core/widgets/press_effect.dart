import 'package:flutter/material.dart';
import '../theme/haptics.dart';

// Wrap anything tappable: scale-down micro animation + light haptic on tap.
class PressEffect extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const PressEffect(
      {super.key, required this.child, this.onTap, this.scale = 0.96});
  @override
  State<PressEffect> createState() => _PressEffectState();
}

class _PressEffectState extends State<PressEffect> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        Haptics.light();
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
