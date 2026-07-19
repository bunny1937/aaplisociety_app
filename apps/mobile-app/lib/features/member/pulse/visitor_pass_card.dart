import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/haptics.dart';
import 'pulse.dart';

/// The generated pass shown to the member right after `/visitors/pass`
/// returns — a premium "credit card" look (gradient + diagonal sheen,
/// rather than a literal gesture-driven 3D tilt, which would need a
/// perspective-transform package for a lot of complexity this doesn't need)
/// with the OTP code prominent and a direct WhatsApp share.
///
/// Only the OTP is shown/shared, not the qrToken: both work identically
/// against POST /visitors/pass/verify (it checks either hash), but the
/// qrToken is a long base64url string — awkward to read aloud or text,
/// where the 6-digit OTP is the one meant for a human to actually use.
Future<void> showVisitorPassCard(
  BuildContext context, {
  required String visitorName,
  required String visitorPhone,
  required String otp,
  required DateTime generatedAt,
  required DateTime expiresAt,
}) {
  return showPulseSheet<void>(
    context,
    title: 'Gate Pass',
    builder: (context) => _VisitorPassCardBody(
      visitorName: visitorName,
      visitorPhone: visitorPhone,
      otp: otp,
      generatedAt: generatedAt,
      expiresAt: expiresAt,
    ),
  );
}

class _VisitorPassCardBody extends StatelessWidget {
  final String visitorName;
  final String visitorPhone;
  final String otp;
  final DateTime generatedAt;
  final DateTime expiresAt;

  const _VisitorPassCardBody({
    required this.visitorName,
    required this.visitorPhone,
    required this.otp,
    required this.generatedAt,
    required this.expiresAt,
  });

  String _time(DateTime d) => '${d.day}/${d.month}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _shareToWhatsapp(BuildContext context) async {
    Haptics.select();
    final message = Uri.encodeComponent(
      'Gate pass for $visitorName\n'
      'Show this code at the security gate: $otp\n'
      'Valid until ${_time(expiresAt)}',
    );
    // Indian 10-digit numbers throughout this app assume no country code -
    // wa.me needs the full number, so prefix +91 to match every other phone
    // field in the codebase (contactNumber, whatsappNumber, etc.).
    final uri = Uri.parse('https://wa.me/91$visitorPhone?text=$message');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      showPulseToast(context, 'Could not open WhatsApp', kind: PulseToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [t.brand2, t.brand, t.accent],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('VISITOR PASS', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                        const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 22),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(visitorName, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(visitorPhone, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 20),
                    Text('ENTRY CODE', style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    const SizedBox(height: 4),
                    Text(otp, style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 6)),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Generated ${_time(generatedAt)}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10.5)),
                        Text('Valid until ${_time(expiresAt)}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10.5)),
                      ],
                    ),
                  ],
                ),
              ),
              // Diagonal sheen - the one bit of "premium card" visual
              // language borrowed from real credit cards, without a literal
              // interactive 3D tilt.
              Positioned(
                top: -40, right: -60,
                child: Transform.rotate(
                  angle: 0.5,
                  child: Container(width: 160, height: 240, color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        PulseButton(
          label: 'Share via WhatsApp',
          icon: Icons.chat_rounded,
          full: true,
          onTap: () => _shareToWhatsapp(context),
        ),
        const SizedBox(height: 10),
        PulseButton(
          label: 'Done',
          variant: PulseBtnVariant.ghost,
          full: true,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
