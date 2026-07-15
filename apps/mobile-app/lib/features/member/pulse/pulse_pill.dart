import 'package:flutter/material.dart';
import 'pulse_tokens.dart';

/// Status/tag pill — port of Primitives.jsx `Pill`. Tone keys map to REAL
/// backend vocabulary, not the design fixture's (see MEMBER_V2_GAPS.md):
/// bills use Paid/Unpaid/Partial/Overdue; complaints use
/// Open/In progress/Resolved/Rejected; visitors use their own status set;
/// ledger uses Credit/Debit. `overdue` pulses per the design's
/// `@keyframes pulse` attention-grabber.
enum PulseTone {
  paid, unpaid, partial, overdue, pending, approved, rejected,
  open, inProgress, resolved,
  entered, exited, expired, info, credit, debit, neutral,
}

class PulsePill extends StatefulWidget {
  final String label;
  final PulseTone tone;
  final bool dot;
  final bool small;

  const PulsePill({super.key, required this.label, this.tone = PulseTone.neutral, this.dot = true, this.small = false});

  @override
  State<PulsePill> createState() => _PulsePillState();
}

class _PulsePillState extends State<PulsePill> with SingleTickerProviderStateMixin {
  AnimationController? _pulseCtrl;

  @override
  void initState() {
    super.initState();
    if (widget.tone == PulseTone.overdue) {
      _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseCtrl?.dispose();
    super.dispose();
  }

  (Color, Color) _tone(PulseTokens t) => switch (widget.tone) {
        PulseTone.paid || PulseTone.approved || PulseTone.resolved || PulseTone.credit => (t.successSoft, t.success),
        PulseTone.unpaid || PulseTone.overdue || PulseTone.rejected || PulseTone.debit => (t.dangerSoft, t.danger),
        PulseTone.partial || PulseTone.pending || PulseTone.inProgress => (t.warningSoft, t.warning),
        PulseTone.open || PulseTone.info || PulseTone.entered => (t.brandSoft, t.brand),
        PulseTone.exited || PulseTone.expired || PulseTone.neutral => (t.surface3, t.fg3),
      };

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final (bg, fg) = _tone(t);
    final pad = widget.small
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 3);
    final fs = widget.small ? 10.0 : 11.0;

    Widget pill = Container(
      padding: pad,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.dot) ...[
            Container(width: 5, height: 5, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          Text(widget.label, style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700, color: fg, letterSpacing: 0.2)),
        ],
      ),
    );

    if (_pulseCtrl == null) return pill;
    return AnimatedBuilder(
      animation: _pulseCtrl!,
      builder: (context, child) {
        final v = 1 - (_pulseCtrl!.value * 0.3);
        return Opacity(opacity: v, child: Transform.scale(scale: 0.95 + v * 0.05, child: child));
      },
      child: pill,
    );
  }
}
