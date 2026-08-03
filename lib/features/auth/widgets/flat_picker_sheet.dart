// lib/features/auth/widgets/flat_picker_sheet.dart
//
// The popup after login: "which flat?"
//
// Shown when the login response comes back with requiresProfileSelect: true,
// i.e. the account holds more than one active profile. Bhavani signs in once
// and picks 101, 201 or 401; tapping one calls /api/auth/switch-profile and
// that response is what actually issues the session.
//
// IMPORTANT CONTRACT NOTE - this is a live bug in the current app:
//
//   auth_bloc.dart reads  res.data['selectToken']
//   the web route returns res.data['profileSelectToken']
//
// So the token is null today and switch-profile is rejected. Fixed in
// AUTH-BLOC-PATCH.md. This sheet takes the token as a required parameter so
// the mismatch cannot silently reappear - passing null will not compile.
//
// Behaviour rules:
//   - not dismissible. There is no app state behind it; a member who escapes
//     this sheet is logged in with no active profile, which every downstream
//     screen would have to defend against.
//   - the sheet owns the switch call, so there is exactly one place a profile
//     session is established.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/haptics.dart';
import '../../onboarding/data/onboarding_api.dart' show FlatSummary;

typedef ProfileSelected = Future<String?> Function(String profileId);

class FlatPickerSheet extends StatefulWidget {
  const FlatPickerSheet({
    super.key,
    required this.name,
    required this.flats,
    required this.onSelect,
    required this.onCancel,
  });

  final String name;
  final List<FlatSummary> flats;

  /// Performs the switch-profile call. Returns null on success, or an error
  /// message to display.
  final ProfileSelected onSelect;

  /// Signs the half-authenticated user back out. Wired to the only exit.
  final VoidCallback onCancel;

  /// Convenience presenter. Returns true if a profile was selected.
  static Future<bool> show(
    BuildContext context, {
    required String name,
    required List<FlatSummary> flats,
    required ProfileSelected onSelect,
    required VoidCallback onCancel,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xFF0B1120).withValues(alpha: 0.72),
      builder: (_) => PopScope(
        // Back button must not leave the member in limbo.
        canPop: false,
        child: FlatPickerSheet(
          name: name,
          flats: flats,
          onSelect: onSelect,
          onCancel: onCancel,
        ),
      ),
    );
    return result ?? false;
  }

  @override
  State<FlatPickerSheet> createState() => _FlatPickerSheetState();
}

class _FlatPickerSheetState extends State<FlatPickerSheet> {
  String? _busyProfileId;
  String? _error;

  Future<void> _pick(FlatSummary flat) async {
    if (_busyProfileId != null) return;
    if (flat.status.toLowerCase() != 'active') {
      Haptics.heavy();
      setState(() => _error =
          'Flat ${flat.flatNo} is marked inactive. Contact your society admin.');
      return;
    }

    Haptics.medium();
    setState(() {
      _busyProfileId = flat.profileId;
      _error = null;
    });

    final err = await widget.onSelect(flat.profileId);

    if (!mounted) return;

    if (err == null) {
      Haptics.success();
      Navigator.of(context).pop(true);
    } else {
      Haptics.heavy();
      setState(() {
        _busyProfileId = null;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final flats = widget.flats;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF141C3A), Color(0xFF0D1430)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          padding: EdgeInsets.only(bottom: media.padding.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hello, ${widget.name.split(' ').first}',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: const Color(0xFF818CF8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Which flat today?',
                        style: GoogleFonts.fraunces(
                          fontSize: 27,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'You have ${flats.length} flats on this login. '
                        'Switch any time from your profile.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 340.ms)
                    .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic),

                const SizedBox(height: 22),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    children: flats.asMap().entries.map((entry) {
                      final i = entry.key;
                      final flat = entry.value;
                      final busy = _busyProfileId == flat.profileId;
                      final dimmed = _busyProfileId != null && !busy;
                      final inactive = flat.status.toLowerCase() != 'active';

                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: dimmed ? 0.35 : 1,
                        child: _FlatTile(
                          flat: flat,
                          busy: busy,
                          inactive: inactive,
                          onTap: () => _pick(flat),
                        )
                            .animate(delay: (70 * i).ms)
                            .fadeIn(duration: 320.ms)
                            .slideY(
                              begin: 0.18,
                              end: 0,
                              curve: Curves.easeOutCubic,
                              duration: 380.ms,
                            ),
                      );
                    }).toList(),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7F1D1D).withValues(alpha: 0.26),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.34)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 16, color: Color(0xFFFCA5A5)),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _error!,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                height: 1.45,
                                color: const Color(0xFFFECACA),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 200.ms)
                      .shake(hz: 3.5, offset: const Offset(2.5, 0), duration: 360.ms),
                ],

                const SizedBox(height: 16),

                Center(
                  child: TextButton.icon(
                    onPressed: _busyProfileId != null
                        ? null
                        : () {
                            Haptics.light();
                            Navigator.of(context).pop(false);
                            widget.onCancel();
                          },
                    icon: Icon(Icons.logout_rounded,
                        size: 15, color: Colors.white.withValues(alpha: 0.42)),
                    label: Text(
                      'Sign in as someone else',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlatTile extends StatefulWidget {
  const _FlatTile({
    required this.flat,
    required this.busy,
    required this.inactive,
    required this.onTap,
  });

  final FlatSummary flat;
  final bool busy;
  final bool inactive;
  final VoidCallback onTap;

  @override
  State<_FlatTile> createState() => _FlatTileState();
}

class _FlatTileState extends State<_FlatTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final flat = widget.flat;
    final isOwner = flat.occupancyType.toLowerCase() == 'owner';
    final accent = widget.inactive
        ? const Color(0xFF6B7280)
        : (isOwner ? const Color(0xFF818CF8) : const Color(0xFF34D399));

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.busy ? null : widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: Container(
          margin: const EdgeInsets.only(bottom: 11),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: widget.busy
                ? accent.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: _pressed ? 0.085 : 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.busy
                  ? accent.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.09),
              width: widget.busy ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0.10)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: accent.withValues(alpha: 0.32)),
                ),
                child: Text(
                  flat.flatNo,
                  style: GoogleFonts.robotoMono(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            flat.wing != null && flat.wing!.isNotEmpty
                                ? 'Wing ${flat.wing} \u00b7 ${flat.flatNo}'
                                : 'Flat ${flat.flatNo}',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.94),
                            ),
                          ),
                        ),
                        if (widget.inactive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6B7280).withValues(alpha: 0.24),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'Inactive',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${flat.societyName} \u00b7 ${flat.occupancyType}',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.3,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 24,
                height: 24,
                child: widget.busy
                    ? CircularProgressIndicator(strokeWidth: 2.2, color: accent)
                    : Icon(Icons.arrow_forward_rounded,
                        size: 19, color: Colors.white.withValues(alpha: 0.32)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
