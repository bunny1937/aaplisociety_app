import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF0C2461);
  static const blue = Color(0xFF2353FF);
  static const navyDark = Color(0xFF081A47);
  static const bg = Color(0xFFF4F6FB);
  static const surface = Colors.white;
  static const textMuted = Color(0xFF6B7280);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy, blue],
  );
  // Premium identity: dark blue / light blue / cream — confirmed direction.
  // Names kept as `ink`/`paper`/`brass` so every already-migrated screen
  // picks up the new palette without touching each file again; they now hold
  // navy/sky-blue/cream values, not the old ink/brass tones.
  static const ink = Color(0xFF0B1330); // deep navy — dark surfaces, gradients
  static const inkRaised =
      Color(0xFF16224D); // lighter navy — elevated dark surfaces
  static const inkMuted = Color(0xFF8FA3C7); // muted blue-gray — secondary text
  static const paper = Color(0xFFF7F1E0); // cream — light surfaces
  static const brass = Color(0xFF4C8DFF); // light blue — primary accent, CTAs
  static const brassBright =
      Color(0xFF7EC1FF); // brighter blue — hover/highlight
  static const stampGreen = Color(0xFF2F7D5A);
  static const stampRed = Color(0xFFB33A2E);
  static const ledgerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ink, inkRaised],
  );
}
