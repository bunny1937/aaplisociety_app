import 'package:flutter/material.dart';
import '../pulse/pulse.dart';

/// One label/value row, shared by all profile detail pages (port of the
/// row rendering that used to live inline in member_profile_page.dart's
/// `_Section`).
class ProfileInfoRow extends StatelessWidget {
  final String label;
  final String? value;
  const ProfileInfoRow({super.key, required this.label, this.value});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 120,
              child:
                  Text(label, style: TextStyle(fontSize: 12.5, color: t.fg4))),
          Expanded(
            child: Text(
              value ?? 'Not available yet',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: value != null ? t.fg1 : t.fg5,
                fontStyle: value != null ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Change to X — pending approval" note shown under a field/row that has an
/// outstanding ProfileEditRequest against it.
class PendingChangeNote extends StatelessWidget {
  final String text;
  const PendingChangeNote({super.key, required this.text});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top_rounded, size: 13, color: t.brand),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: t.brand,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
