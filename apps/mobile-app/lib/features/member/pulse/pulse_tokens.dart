import 'package:flutter/material.dart';

/// Design tokens for the "Pulse Mobile" member-app visual language, ported
/// from the design handoff's `--m-*` CSS custom properties
/// (ui_kits/member-v2/MemberV2Primitives.jsx `ThemeStyles()`).
/// The handoff shipped light tokens only — `dark` below is an extrapolation
/// kept in the same spirit, not a literal handoff value (see
/// apps/mobile-app/MEMBER_V2_GAPS.md).
@immutable
class PulseTokens extends ThemeExtension<PulseTokens> {
  final Color canvas;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color hairline;
  final Color fg1;
  final Color fg2;
  final Color fg3;
  final Color fg4;
  final Color fg5;
  final Color brand;
  final Color brand2;
  final Color accent;
  final Color brandSoft;
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color warning;
  final Color warningSoft;
  final List<BoxShadow> shadowCard;
  final List<BoxShadow> shadowPop;

  const PulseTokens({
    required this.canvas,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.hairline,
    required this.fg1,
    required this.fg2,
    required this.fg3,
    required this.fg4,
    required this.fg5,
    required this.brand,
    required this.brand2,
    required this.accent,
    required this.brandSoft,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
    required this.shadowCard,
    required this.shadowPop,
  });

  // Radii — --m-radius-sm / --m-radius / --m-radius-lg
  static const double radiusSm = 10;
  static const double radius = 18;
  static const double radiusLg = 26;

  static const light = PulseTokens(
    canvas: Color(0xFFF6F7FB),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFFBFBFE),
    surface3: Color(0xFFF0F1F7),
    border: Color(0xFFECECF3),
    hairline: Color(0xFFF1F1F6),
    fg1: Color(0xFF0C0E1A),
    fg2: Color(0xFF1C1F2E),
    fg3: Color(0xFF565A72),
    fg4: Color(0xFF8B8FA3),
    fg5: Color(0xFFB3B6C6),
    brand: Color(0xFF1E3A8A),
    brand2: Color(0xFF3454B4),
    accent: Color(0xFF6B8EEF),
    brandSoft: Color(0xFFE9EDFB),
    success: Color(0xFF0F9D58),
    successSoft: Color(0xFFE5F6EC),
    danger: Color(0xFFE0392C),
    dangerSoft: Color(0xFFFDECEB),
    warning: Color(0xFFB5690A),
    warningSoft: Color(0xFFFDF1DE),
    shadowCard: [
      BoxShadow(color: Color(0x0A14142D), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x1A14142D), blurRadius: 20, offset: Offset(0, 6), spreadRadius: -8),
    ],
    shadowPop: [
      BoxShadow(color: Color(0x47141426), blurRadius: 48, offset: Offset(0, 24), spreadRadius: -12),
      BoxShadow(color: Color(0x1A14142D), blurRadius: 12, offset: Offset(0, 4), spreadRadius: -2),
    ],
  );

  static const dark = PulseTokens(
    canvas: Color(0xFF0B1020),
    surface: Color(0xFF161C2E),
    surface2: Color(0xFF1B2238),
    surface3: Color(0xFF212942),
    border: Color(0xFF2B3350),
    hairline: Color(0xFF232B45),
    fg1: Color(0xFFF5F6FA),
    fg2: Color(0xFFE1E3EE),
    fg3: Color(0xFFA6ABC4),
    fg4: Color(0xFF7B81A0),
    fg5: Color(0xFF565C7C),
    brand: Color(0xFF5D82E8),
    brand2: Color(0xFF7599EE),
    accent: Color(0xFF8FACF7),
    brandSoft: Color(0xFF1E2748),
    success: Color(0xFF34C97C),
    successSoft: Color(0xFF13301F),
    danger: Color(0xFFF0665A),
    dangerSoft: Color(0xFF3A1C1A),
    warning: Color(0xFFE2A94E),
    warningSoft: Color(0xFF3A2C13),
    shadowCard: [
      BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 6), spreadRadius: -8),
    ],
    shadowPop: [
      BoxShadow(color: Color(0x66000000), blurRadius: 48, offset: Offset(0, 24), spreadRadius: -12),
      BoxShadow(color: Color(0x24000000), blurRadius: 12, offset: Offset(0, 4), spreadRadius: -2),
    ],
  );

  @override
  PulseTokens copyWith({
    Color? canvas, Color? surface, Color? surface2, Color? surface3, Color? border, Color? hairline,
    Color? fg1, Color? fg2, Color? fg3, Color? fg4, Color? fg5,
    Color? brand, Color? brand2, Color? accent, Color? brandSoft,
    Color? success, Color? successSoft, Color? danger, Color? dangerSoft, Color? warning, Color? warningSoft,
    List<BoxShadow>? shadowCard, List<BoxShadow>? shadowPop,
  }) {
    return PulseTokens(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      border: border ?? this.border,
      hairline: hairline ?? this.hairline,
      fg1: fg1 ?? this.fg1,
      fg2: fg2 ?? this.fg2,
      fg3: fg3 ?? this.fg3,
      fg4: fg4 ?? this.fg4,
      fg5: fg5 ?? this.fg5,
      brand: brand ?? this.brand,
      brand2: brand2 ?? this.brand2,
      accent: accent ?? this.accent,
      brandSoft: brandSoft ?? this.brandSoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      shadowCard: shadowCard ?? this.shadowCard,
      shadowPop: shadowPop ?? this.shadowPop,
    );
  }

  @override
  PulseTokens lerp(ThemeExtension<PulseTokens>? other, double t) {
    if (other is! PulseTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return PulseTokens(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surface2: c(surface2, other.surface2),
      surface3: c(surface3, other.surface3),
      border: c(border, other.border),
      hairline: c(hairline, other.hairline),
      fg1: c(fg1, other.fg1),
      fg2: c(fg2, other.fg2),
      fg3: c(fg3, other.fg3),
      fg4: c(fg4, other.fg4),
      fg5: c(fg5, other.fg5),
      brand: c(brand, other.brand),
      brand2: c(brand2, other.brand2),
      accent: c(accent, other.accent),
      brandSoft: c(brandSoft, other.brandSoft),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      shadowCard: t < 0.5 ? shadowCard : other.shadowCard,
      shadowPop: t < 0.5 ? shadowPop : other.shadowPop,
    );
  }
}

extension PulseTokensX on BuildContext {
  PulseTokens get pulse => Theme.of(this).extension<PulseTokens>() ?? PulseTokens.light;
}
