import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/member/pulse/pulse.dart';

/// Press-and-hold destructive action.
///
/// Audit fix 3.3 flaw 4 + X-8: "Emergency SOS" was the 2nd row of a plain
/// settings list, visually identical to "Change password". One mis-tap while
/// scrolling raised a society-wide alarm. A life-safety trigger must be
/// (a) visually separated from navigation, and (b) impossible to fire with a
/// single accidental tap.
///
/// This widget requires a deliberate [holdDuration] press, gives continuous
/// progress feedback, escalating haptics, and cancels cleanly on release.
class HoldToConfirm extends StatefulWidget {
  final String label;
  final String holdingLabel;
  final String helper;
  final IconData icon;
  final Duration holdDuration;
  final VoidCallback onConfirmed;
  final Color? color;
  const HoldToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.holdingLabel = 'Keep holding\u2026',
    this.helper = 'Hold for 2 seconds to alert security',
    this.icon = Icons.sos_rounded,
    this.holdDuration = const Duration(milliseconds: 2000),
    this.color,
  });

  @override
  State<HoldToConfirm> createState() => _HoldToConfirmState();
}

class _HoldToConfirmState extends State<HoldToConfirm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )
    ..addListener(_onTick)
    ..addStatusListener(_onStatus);
  int _lastHapticStep = 0;
  bool _fired = false;

  void _onTick() {
    // Escalating haptics: one tick per 25% so the user feels the commitment.
    final step = (_ctrl.value * 4).floor();
    if (step != _lastHapticStep && step > 0 && step < 4) {
      _lastHapticStep = step;
      HapticFeedback.selectionClick();
    }
    setState(() {});
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && !_fired) {
      _fired = true;
      HapticFeedback.heavyImpact();
      widget.onConfirmed();
      _reset();
    }
  }

  void _reset() {
    _fired = false;
    _lastHapticStep = 0;
    _ctrl.value = 0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final accent = widget.color ?? t.danger;
    final holding = _ctrl.isAnimating || _ctrl.value > 0;
    return Semantics(
      button: true,
      label: '${widget.label}. ${widget.helper}',
      child: GestureDetector(
        onLongPressStart: (_) {
          HapticFeedback.mediumImpact();
          _ctrl.forward(from: 0);
        },
        onLongPressEnd: (_) {
          if (!_fired) {
            _ctrl.stop();
            setState(_reset);
          }
        },
        onLongPressCancel: () {
          if (!_fired) {
            _ctrl.stop();
            setState(_reset);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(PulseTokens.radius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Fill that tracks hold progress.
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _ctrl.value,
                  child: DecoratedBox(
                    decoration:
                        BoxDecoration(color: accent.withValues(alpha: 0.22)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: accent, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child:
                          Icon(widget.icon, size: 20, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            holding ? widget.holdingLabel : widget.label,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: accent),
                          ),
                          const SizedBox(height: 2),
                          Text(widget.helper,
                              style:
                                  TextStyle(fontSize: 11.5, color: t.fg4)),
                        ],
                      ),
                    ),
                    if (holding)
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          value: _ctrl.value,
                          strokeWidth: 2.5,
                          color: accent,
                          backgroundColor: accent.withValues(alpha: 0.2),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirmation sheet body for destructive actions where the two buttons must
/// NOT be symmetric.
///
/// Audit fix 3.12 flaw 2: the gate approval sheet rendered `Deny` and `Allow`
/// as identical-weight buttons side by side, so denying entry — the
/// irreversible, security-relevant choice — was exactly as easy to hit as
/// allowing it. Here the destructive action is a filled danger button and the
/// safe action is the visually quieter secondary, and the destructive one is
/// placed on the right where the thumb is less likely to land by accident.
class DestructiveConfirmActions extends StatelessWidget {
  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool loading;
  const DestructiveConfirmActions({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    this.cancelLabel = 'Cancel',
    this.loading = false,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: PulseButton(
            label: cancelLabel,
            variant: PulseBtnVariant.secondary,
            full: true,
            onTap: onCancel,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 5,
          child: PulseButton(
            label: confirmLabel,
            variant: PulseBtnVariant.danger,
            full: true,
            loading: loading,
            onTap: onConfirm,
          ),
        ),
      ],
    );
  }
}
