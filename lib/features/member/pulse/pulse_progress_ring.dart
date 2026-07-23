import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'pulse_tokens.dart';

/// Port of Primitives.jsx `ProgressRing` — animated arc, 1s ease-out on mount
/// or value change.
class PulseProgressRing extends StatelessWidget {
  final double pct; // 0..100
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;
  const PulseProgressRing(
      {super.key,
      required this.pct,
      this.size = 96,
      this.stroke = 9,
      this.color,
      this.child});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: pct.clamp(0, 100)),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _RingPainter(
                    pct: value,
                    stroke: stroke,
                    track: t.surface3,
                    color: color ?? t.brand),
              ),
              if (child != null) child!,
            ],
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  final double stroke;
  final Color track;
  final Color color;
  _RingPainter(
      {required this.pct,
      required this.stroke,
      required this.track,
      required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, r, trackPaint);
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final sweep = (pct / 100) * 2 * math.pi;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2,
        sweep, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.pct != pct || old.color != color;
}
