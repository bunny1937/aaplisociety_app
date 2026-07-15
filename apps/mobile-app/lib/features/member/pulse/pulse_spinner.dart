import 'package:flutter/material.dart';
import 'pulse_tokens.dart';

/// Port of Primitives.jsx `Spinner` — 2.5px ring, 0.7s rotation.
class PulseSpinner extends StatelessWidget {
  final double size;
  final Color? color;
  const PulseSpinner({super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.pulse.brand;
    return SizedBox(width: size, height: size, child: _Spin(color: c));
  }
}

class _Spin extends StatefulWidget {
  final Color color;
  const _Spin({required this.color});
  @override
  State<_Spin> createState() => _SpinState();
}

class _SpinState extends State<_Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: widget.color, backgroundColor: widget.color.withValues(alpha: 0.2)),
    );
  }
}
