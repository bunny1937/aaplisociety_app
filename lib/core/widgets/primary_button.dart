import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/haptics.dart';

// Gradient CTA with press animation, loading spinner and medium haptic.
// `ledger: true` opts a screen into the brass-on-ink ledger styling
// (design-system.md) without changing the default look for screens not yet
// migrated off the legacy navy/blue theme.
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool ledger;
  const PrimaryButton(
      {super.key,
      required this.label,
      this.onPressed,
      this.loading = false,
      this.icon,
      this.ledger = false});
  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading || widget.onPressed == null;
    final labelColor = widget.ledger ? AppColors.ink : Colors.white;
    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: disabled
          ? null
          : () {
              Haptics.medium();
              widget.onPressed!();
            },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 56,
          decoration: BoxDecoration(
            color: widget.ledger ? AppColors.brass : null,
            gradient: widget.ledger ? null : AppColors.brandGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (widget.ledger ? AppColors.brass : AppColors.blue)
                    .withValues(alpha: disabled ? 0.0 : 0.3),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: widget.loading
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: labelColor))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: labelColor, size: 20),
                        const SizedBox(width: 8)
                      ],
                      Text(
                        widget.label,
                        style: widget.ledger
                            ? GoogleFonts.manrope(
                                color: labelColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)
                            : TextStyle(
                                color: labelColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
