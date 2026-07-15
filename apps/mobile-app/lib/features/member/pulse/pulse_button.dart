import 'package:flutter/material.dart';
import '../../../core/theme/haptics.dart';
import 'pulse_tokens.dart';

enum PulseBtnVariant { primary, success, danger, secondary, ghost, link }

enum PulseBtnSize { sm, md, lg }

/// Port of Primitives.jsx `Btn` — gradient-fill primary, press-scale to 0.96.
class PulseButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final PulseBtnVariant variant;
  final PulseBtnSize size;
  final bool full;
  final IconData? icon;
  final IconData? iconTrailing;
  final bool disabled;
  final bool loading;

  const PulseButton({
    super.key,
    required this.label,
    this.onTap,
    this.variant = PulseBtnVariant.primary,
    this.size = PulseBtnSize.md,
    this.full = false,
    this.icon,
    this.iconTrailing,
    this.disabled = false,
    this.loading = false,
  });

  @override
  State<PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<PulseButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final disabled = widget.disabled || widget.loading;
    final (double h, double fs, double gap, EdgeInsets pad) = switch (widget.size) {
      PulseBtnSize.sm => (34.0, 13.0, 6.0, const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
      PulseBtnSize.md => (46.0, 14.5, 8.0, const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
      PulseBtnSize.lg => (54.0, 16.0, 8.0, const EdgeInsets.symmetric(horizontal: 22, vertical: 15)),
    };

    Gradient? gradient;
    Color? bg;
    Color fg;
    Border? border;
    List<BoxShadow>? shadow;

    switch (widget.variant) {
      case PulseBtnVariant.primary:
        gradient = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [t.brand2, t.brand]);
        fg = Colors.white;
        shadow = [BoxShadow(color: t.brand.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 6), spreadRadius: -4)];
      case PulseBtnVariant.success:
        gradient = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFF14B56A), t.success]);
        fg = Colors.white;
        shadow = [BoxShadow(color: t.success.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6), spreadRadius: -4)];
      case PulseBtnVariant.danger:
        gradient = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFFEF4C3F), t.danger]);
        fg = Colors.white;
        shadow = [BoxShadow(color: t.danger.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6), spreadRadius: -4)];
      case PulseBtnVariant.secondary:
        bg = t.surface;
        fg = t.fg2;
        border = Border.all(color: t.border, width: 1.5);
      case PulseBtnVariant.ghost:
        bg = t.surface3;
        fg = t.fg2;
      case PulseBtnVariant.link:
        bg = Colors.transparent;
        fg = t.brand;
    }

    Widget content = Row(
      mainAxisSize: widget.full ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(width: fs, height: fs, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
        else if (widget.icon != null)
          Icon(widget.icon, size: widget.size == PulseBtnSize.lg ? 18 : 16, color: fg),
        if ((widget.icon != null || widget.loading) ) SizedBox(width: gap),
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700, color: fg, letterSpacing: -0.1),
          ),
        ),
        if (widget.iconTrailing != null) ...[
          SizedBox(width: gap),
          Icon(widget.iconTrailing, size: widget.size == PulseBtnSize.lg ? 18 : 16, color: fg),
        ],
      ],
    );

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTapDown: disabled ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: disabled ? null : () { Haptics.light(); widget.onTap?.call(); },
        child: AnimatedScale(
          scale: _down ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            height: h,
            width: widget.full ? double.infinity : null,
            padding: pad,
            decoration: BoxDecoration(
              gradient: gradient,
              color: bg,
              border: border,
              borderRadius: BorderRadius.circular(14),
              boxShadow: disabled ? null : shadow,
            ),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}
