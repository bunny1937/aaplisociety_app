import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:toastification/toastification.dart';
import '../theme/app_colors.dart';

enum AppToastKind { info, success, alert }

/// Ledger-note style toast: ink card, brass left accent, slides in from the
/// top. Shared so every screen that needs a confirmation/error toast (bill
/// paid, complaint submitted, gate alert...) reads as one system.
void showAppToast(BuildContext context, String message, {AppToastKind kind = AppToastKind.info}) {
  final accent = switch (kind) {
    AppToastKind.success => AppColors.stampGreen,
    AppToastKind.alert => AppColors.stampRed,
    AppToastKind.info => AppColors.brass,
  };
  final icon = switch (kind) {
    AppToastKind.success => Icons.check_circle_rounded,
    AppToastKind.alert => Icons.error_rounded,
    AppToastKind.info => Icons.notifications_rounded,
  };

  toastification.show(
    context: context,
    alignment: Alignment.topCenter,
    autoCloseDuration: const Duration(seconds: 3),
    animationDuration: const Duration(milliseconds: 350),
    borderRadius: BorderRadius.circular(14),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    backgroundColor: AppColors.ink,
    foregroundColor: AppColors.paper,
    showProgressBar: false,
    closeButton: const ToastCloseButton(showType: CloseButtonShowType.none),
    icon: Icon(icon, color: accent, size: 20),
    title: Text(
      message,
      style: GoogleFonts.manrope(color: AppColors.paper, fontWeight: FontWeight.w600, fontSize: 13.5),
    ),
    borderSide: BorderSide(color: accent.withValues(alpha: 0.55), width: 1),
  );
}
