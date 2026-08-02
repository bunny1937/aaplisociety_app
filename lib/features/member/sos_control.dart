import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_error.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/hold_to_confirm.dart';
import 'pulse/pulse.dart';

/// Raises POST /visitors/sos — a panic alert to security + admin.
///
/// This was previously a PRIVATE widget inside `member_profile_page.dart`,
/// which is the owner's profile screen. A tenant's profile is a different
/// screen (`tenant_profile_page.dart`), so tenants — residents who are exactly
/// as likely to have a medical emergency, a fire or an intruder — had no panic
/// button anywhere in the app.
///
/// Extracted here verbatim and made public so BOTH resident surfaces mount the
/// same control. Safety is not an ownership perk.
class SosControl extends StatefulWidget {
  const SosControl({super.key});
  @override
  State<SosControl> createState() => _SosControlState();
}

class _SosControlState extends State<SosControl> {
  bool _sending = false;

  /// One-tap reasons. A guard reading "SOS Alert / Other" on their screen learns
  /// nothing and cannot decide whether to bring a first-aid kit, call the fire
  /// brigade, or run. These are the categories that change what the guard
  /// actually does on arrival.
  static const _reasons = <String>[
    'Medical',
    'Fire',
    'Intruder',
    'Accident',
    'Harassment',
  ];

  /// Asks what the emergency is, then returns the note to send. Returns null if
  /// the resident backed out.
  Future<String?> _askReason() async {
    final controller = TextEditingController();
    String? picked;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) => AlertDialog(
          title: const Text('What is the emergency?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The guard sees this together with your flat number, so they '
                  'know what they are walking into.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _reasons
                      .map((reason) => ChoiceChip(
                            label: Text(reason),
                            selected: picked == reason,
                            onSelected: (_) => setDialogState(() {
                              picked = reason;
                              controller.text = reason;
                            }),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Add detail (optional)',
                    hintText: 'e.g. chest pain, need an ambulance',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final typed = controller.text.trim();
                // Never send an empty note - the guard screen would fall back
                // to "Other", which is the problem this exists to fix.
                Navigator.pop(
                    dialogContext, typed.isEmpty ? 'Emergency' : typed);
              },
              child: const Text(
                'Raise SOS now',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _raise() async {
    if (_sending) return;
    final note = await _askReason();
    if (note == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await context.read<Dio>().post('/visitors/sos', data: {'note': note});
      if (!mounted) return;
      showAppToast(context, 'SOS sent to security \u00b7 $note',
          kind: AppToastKind.alert);
    } on DioException catch (err) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sending) {
      final t = context.pulse;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: t.dangerSoft,
          borderRadius: BorderRadius.circular(PulseTokens.radius),
          border: Border.all(color: t.danger.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child:
                  CircularProgressIndicator(strokeWidth: 2.4, color: t.danger),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Alerting security\u2026',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: t.danger)),
            ),
          ],
        ),
      );
    }
    return HoldToConfirm(
      label: 'Raise SOS',
      helper: 'Hold 2 seconds, then tell the guard what is wrong',
      onConfirmed: _raise,
    );
  }
}
