import 'package:flutter/material.dart';
import 'pulse_tokens.dart';

/// Port of Primitives.jsx `Skel` — shimmer sweep via ShaderMask, 1.4s loop.
class PulseSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const PulseSkeleton({super.key, this.width = double.infinity, this.height = 14, this.radius = 7});

  @override
  State<PulseSkeleton> createState() => _PulseSkeletonState();
}

class _PulseSkeletonState extends State<PulseSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.pulse.surface3;
    final highlight = Color.lerp(base, Colors.white, 0.5)!;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            final dx = (_ctrl.value * 2 - 1) * rect.width;
            return LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.25, 0.5, 0.75],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              transform: _SlideGradient(dx),
            ).createShader(rect);
          },
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(widget.radius)),
          ),
        );
      },
    );
  }
}

class _SlideGradient extends GradientTransform {
  final double dx;
  const _SlideGradient(this.dx);
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(dx, 0, 0);
}
