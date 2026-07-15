import 'package:flutter/material.dart';
import 'pulse_tokens.dart';

/// Port of Primitives.jsx hand-drawn SVG illustration set — recreated as
/// CustomPainters so no SVG asset pipeline is needed. Used by [PulseEmptyState].
enum PulseIllo { emptyInbox, allClear, gate, noData, celebrate, shield }

class PulseIllustration extends StatefulWidget {
  final PulseIllo kind;
  final double size;
  const PulseIllustration({super.key, required this.kind, this.size = 96});

  @override
  State<PulseIllustration> createState() => _PulseIllustrationState();
}

class _PulseIllustrationState extends State<PulseIllustration> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 550))..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _IllustrationPainter(kind: widget.kind, tokens: t, progress: Curves.easeOutCubic.transform(_ctrl.value)),
      ),
    );
  }
}

class _IllustrationPainter extends CustomPainter {
  final PulseIllo kind;
  final PulseTokens tokens;
  final double progress;
  _IllustrationPainter({required this.kind, required this.tokens, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    switch (kind) {
      case PulseIllo.emptyInbox:
        _bg(canvas, c, r, tokens.brandSoft);
        final env = Rect.fromCenter(center: c, width: size.width * 0.5, height: size.width * 0.36);
        _stroke(canvas, tokens.brand, 2.5, (p) {
          p.addRRect(RRect.fromRectAndRadius(env, const Radius.circular(6)));
        });
        _stroke(canvas, tokens.brand, 2.5, (p) {
          p.moveTo(env.left, env.top + 4);
          p.lineTo(c.dx, env.top + env.height * 0.6);
          p.lineTo(env.right, env.top + 4);
        });
        canvas.drawCircle(Offset(c.dx + r * 0.42, c.dy - r * 0.42), r * 0.14, Paint()..color = tokens.accent);
      case PulseIllo.allClear:
      case PulseIllo.celebrate:
        final ringColor = tokens.successSoft;
        _bg(canvas, c, r, ringColor);
        canvas.drawCircle(c, r * 0.66, Paint()..color = tokens.surface);
        canvas.drawCircle(c, r * 0.66, Paint()..color = tokens.success..style = PaintingStyle.stroke..strokeWidth = 2.5);
        _animatedCheck(canvas, c, r * 0.38, tokens.success, progress);
        if (kind == PulseIllo.celebrate) {
          const dots = [Offset(-0.8, -0.7), Offset(0.85, -0.85), Offset(0.9, 0.7), Offset(-0.85, 0.9)];
          final colors = [tokens.accent, tokens.brand, tokens.success, tokens.warning];
          for (var i = 0; i < dots.length; i++) {
            canvas.drawCircle(c + Offset(dots[i].dx * r, dots[i].dy * r), r * 0.045, Paint()..color = colors[i]);
          }
        }
      case PulseIllo.gate:
        _bg(canvas, c, r, tokens.brandSoft);
        final barW = r * 0.16;
        final barH = r * 1.0;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(-r * 0.4, 0), width: barW, height: barH), const Radius.circular(3)), Paint()..color = tokens.brand);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(r * 0.4, 0), width: barW, height: barH), const Radius.circular(3)), Paint()..color = tokens.brand);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, -r * 0.5), width: r * 0.96, height: barW), const Radius.circular(3)), Paint()..color = tokens.accent);
        canvas.drawCircle(c + Offset(0, r * 0.12), r * 0.2, Paint()..color = tokens.surface);
        canvas.drawCircle(c + Offset(0, r * 0.12), r * 0.2, Paint()..color = tokens.brand..style = PaintingStyle.stroke..strokeWidth = 2.5);
      case PulseIllo.noData:
        _bg(canvas, c, r, tokens.surface3);
        final doc = Rect.fromCenter(center: c, width: size.width * 0.42, height: size.width * 0.38);
        canvas.drawRRect(RRect.fromRectAndRadius(doc, const Radius.circular(6)), Paint()..color = tokens.surface);
        canvas.drawRRect(RRect.fromRectAndRadius(doc, const Radius.circular(6)), Paint()..color = tokens.fg5..style = PaintingStyle.stroke..strokeWidth = 2.5);
        final linePaint = Paint()..color = tokens.fg5..strokeWidth = 2.5..strokeCap = StrokeCap.round;
        for (var i = 0; i < 3; i++) {
          final y = doc.top + doc.height * (0.3 + i * 0.22);
          canvas.drawLine(Offset(doc.left + 6, y), Offset(doc.right - 6 - i * 8, y), linePaint);
        }
      case PulseIllo.shield:
        _bg(canvas, c, r, tokens.brandSoft);
        final path = Path();
        final w = size.width * 0.42, h = size.width * 0.48;
        path.moveTo(c.dx, c.dy - h / 2);
        path.lineTo(c.dx + w / 2, c.dy - h / 2 + h * 0.18);
        path.lineTo(c.dx + w / 2, c.dy - h * 0.02);
        path.quadraticBezierTo(c.dx + w / 2, c.dy + h * 0.34, c.dx, c.dy + h / 2);
        path.quadraticBezierTo(c.dx - w / 2, c.dy + h * 0.34, c.dx - w / 2, c.dy - h * 0.02);
        path.lineTo(c.dx - w / 2, c.dy - h / 2 + h * 0.18);
        path.close();
        canvas.drawPath(path, Paint()..color = tokens.surface);
        canvas.drawPath(path, Paint()..color = tokens.brand..style = PaintingStyle.stroke..strokeWidth = 2.5);
        _animatedCheck(canvas, c + Offset(0, r * 0.02), r * 0.22, tokens.brand, progress);
    }
  }

  void _bg(Canvas canvas, Offset c, double r, Color color) => canvas.drawCircle(c, r, Paint()..color = color);

  void _stroke(Canvas canvas, Color color, double w, void Function(Path) build) {
    final p = Path();
    build(p);
    canvas.drawPath(p, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
  }

  void _animatedCheck(Canvas canvas, Offset c, double r, Color color, double progress) {
    final path = Path()
      ..moveTo(c.dx - r * 0.55, c.dy + r * 0.05)
      ..lineTo(c.dx - r * 0.1, c.dy + r * 0.5)
      ..lineTo(c.dx + r * 0.65, c.dy - r * 0.45);
    final metrics = path.computeMetrics().toList();
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = r * 0.24..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    for (final m in metrics) {
      canvas.drawPath(m.extractPath(0, m.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _IllustrationPainter old) => old.progress != progress || old.kind != kind;
}

/// Port of Primitives.jsx `EmptyState`.
class PulseEmptyState extends StatelessWidget {
  final PulseIllo illo;
  final String title;
  final String? subtitle;
  final Widget? action;

  const PulseEmptyState({super.key, required this.illo, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseIllustration(kind: illo),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.fg1)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: 240,
              child: Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: t.fg4, height: 1.5)),
            ),
          ],
          if (action != null) Padding(padding: const EdgeInsets.only(top: 12), child: action!),
        ],
      ),
    );
  }
}
