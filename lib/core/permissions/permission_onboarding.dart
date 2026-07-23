import 'package:flutter/material.dart';
import 'app_permissions.dart';

/// First-launch, app-controlled explanation shown before the native OS
/// notification prompt. Runs once ever (persisted via AppPermissions) -
/// never reappears after the user picks either option, and never reappears
/// just because permission was denied (that's what "Not now" is for -
/// re-prompting on every launch trains users to reflexively dismiss it).
Future<void> showNotificationOnboardingIfNeeded(BuildContext context) async {
  if (await AppPermissions.hasShownNotificationOnboarding()) return;
  if (await AppPermissions.isGranted()) {
    await AppPermissions.markNotificationOnboardingShown();
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.notifications_active_outlined, size: 40),
      title: const Text('Stay in the loop'),
      content: const Text(
        'Aapli Society uses notifications for visitor approvals, gate/SOS alerts, '
        'society notices, bills, payment confirmations, and tenancy updates. '
        'You can change this anytime in Settings.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () async {
            await AppPermissions.markNotificationOnboardingShown();
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () async {
            await AppPermissions.markNotificationOnboardingShown();
            await AppPermissions.requestNotificationPermission();
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          child: const Text('Allow notifications'),
        ),
      ],
    ),
  );
}

/// For a settings screen: re-offers the choice when permission was denied.
/// If the OS has permanently denied it (Android "don't ask again"), the OS
/// prompt won't fire again - route to app settings instead.
Future<void> requestNotificationPermissionFromSettings(
    BuildContext context) async {
  if (await AppPermissions.isPermanentlyDenied()) {
    await AppPermissions.openSettings();
    return;
  }
  await AppPermissions.requestNotificationPermission();
}
