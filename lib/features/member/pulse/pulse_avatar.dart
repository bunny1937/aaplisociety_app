import 'package:flutter/material.dart';
import 'pulse_tokens.dart';

/// Port of Primitives.jsx `Avatar` — initials on a deterministic gradient,
/// optional conic-gradient ring (SweepGradient is Flutter's conic-gradient).
class PulseAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool ring;
  const PulseAvatar(
      {super.key, required this.name, this.size = 40, this.ring = false});
  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final letters = parts.take(2).map((p) => p[0]).join();
    return letters.toUpperCase();
  }

  int get _hue {
    final seed = name.codeUnits.fold<int>(0, (a, c) => a + c);
    return (seed * 37) % 360;
  }

  Widget _bubble(double d) {
    final hue = _hue.toDouble();
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.70, 0.52).toColor(),
            HSLColor.fromAHSL(1, (hue + 45) % 360, 0.65, 0.42).toColor(),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: d * 0.36,
            letterSpacing: -0.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    if (!ring) return SizedBox(width: size, height: size, child: _bubble(size));
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [t.brand, t.accent, t.brand]),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, color: t.surface),
        child: _bubble(size - 9),
      ),
    );
  }
}
