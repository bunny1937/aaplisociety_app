import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';
import 'pulse_tokens.dart';

enum PulseToastKind { success, error, info }

/// Port of Primitives.jsx `Toast` — solid-tone pill, bottom-center, 2.6s
/// auto-dismiss. Separate from the app-wide `showAppToast` (ink/paper style
/// used by admin/security surfaces) so this pass doesn't change those.
void showPulseToast(BuildContext context, String message, {PulseToastKind kind = PulseToastKind.info}) {
  final t = context.pulse;
  final (bg, icon) = switch (kind) {
    PulseToastKind.success => (t.success, Icons.check_circle_rounded),
    PulseToastKind.error => (t.danger, Icons.cancel_rounded),
    PulseToastKind.info => (t.fg1, Icons.info_rounded),
  };

  toastification.show(
    context: context,
    alignment: Alignment.bottomCenter,
    autoCloseDuration: const Duration(milliseconds: 2600),
    animationDuration: const Duration(milliseconds: 250),
    borderRadius: BorderRadius.circular(14),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    backgroundColor: bg,
    foregroundColor: Colors.white,
    showProgressBar: false,
    closeButton: const ToastCloseButton(showType: CloseButtonShowType.none),
    icon: Icon(icon, color: Colors.white, size: 16),
    title: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
  );
}
