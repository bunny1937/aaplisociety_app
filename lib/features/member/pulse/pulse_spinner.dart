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

class _SpinState extends State<_Spin> {
  @override
  Widget build(BuildContext context) {
    // CircularProgressIndicator already animates its own indeterminate
    // sweep — wrapping it in a second RotationTransition (removed) stacked
    // two independent rotations and produced a warped, streaking line
    // instead of a clean spinning ring.
    return CircularProgressIndicator(
        strokeWidth: 2.5,
        color: widget.color,
        backgroundColor: widget.color.withValues(alpha: 0.2));
  }
}
