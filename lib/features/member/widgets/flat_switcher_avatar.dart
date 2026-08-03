// lib/features/member/widgets/flat_switcher_avatar.dart
//
// The dashboard avatar, and the only in-app way to change flat.
//
// Interaction, in order of discoverability:
//   tap        -> opens the switcher (only when the account has >1 flat)
//   long-press -> opens the switcher with a heavier haptic
//   swipe up   -> opens the switcher
// A single-flat account gets a plain avatar with no gesture and no chevron,
// because a switcher with one row is a dead end that looks broken.
//
// The avatar itself IS the flat number - "101" in mono, ringed in the occupancy
// accent (indigo owner / green tenant). That is the whole point: on a shared
// account you must be able to tell at a glance which flat you are acting as
// before you pay a bill against the wrong one.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/haptics.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../onboarding/data/onboarding_api.dart' show FlatSummary;

const _kOwner = Color(0xFF818CF8);
const _kTenant = Color(0xFF34D399);
const _kSheetTop = Color(0xFF141C3A);
const _kSheetBottom = Color(0xFF0D1430);

Color _accentFor(String occupancyType) =>
    occupancyType.toLowerCase() == 'tenant' ? _kTenant : _kOwner;

class FlatSwitcherAvatar extends StatefulWidget {
  const FlatSwitcherAvatar({
    super.key,
    required this.dio,
    this.size = 44,
  });

  final Dio dio;
  final double size;

  @override
  State<FlatSwitcherAvatar> createState() => _FlatSwitcherAvatarState();
}

class _FlatSwitcherAvatarState extends State<FlatSwitcherAvatar> {
  List<FlatSummary> _flats = const [];
  String _activeId = '';
  String _name = '';
  bool _loaded = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.dio.get('/auth/my-profiles');
      if (!mounted) return;
      setState(() {
        _flats = ((res.data['profiles'] as List?) ?? const [])
            .map((p) => FlatSummary.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList();
        _activeId = (res.data['activeProfileId'] ?? '').toString();
        _name = (res.data['name'] ?? '').toString();
        _loaded = true;
      });
    } catch (_) {
      // Offline or a rolled-back API: degrade to a plain avatar rather than
      // blocking the dashboard behind a switcher nobody asked for.
      if (mounted) setState(() => _loaded = true);
    }
  }

  FlatSummary? get _active {
    for (final f in _flats) {
      if (f.profileId == _activeId) return f;
    }
    return _flats.isEmpty ? null : _flats.first;
  }

  bool get _canSwitch => _flats.length > 1;

  Future<void> _open() async {
    if (!_canSwitch) return;
    Haptics.medium();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xFF0B1120).withValues(alpha: 0.72),
      builder: (_) => _SwitcherSheet(
        name: _name,
        flats: _flats,
        activeId: _activeId,
      ),
    );
    if (!mounted || chosen == null || chosen == _activeId) return;

    // Optimistic: repaint the avatar immediately so the switch feels instant.
    // AuthBloc re-hydrates behind it and the dashboard rebuilds from /auth/me.
    setState(() => _activeId = chosen);
    context.read<AuthBloc>().add(SwitchProfileInSession(chosen));
  }

  @override
  Widget build(BuildContext context) {
    final flat = _active;
    final label = flat?.flatNo ?? '';
    final accent = _accentFor(flat?.occupancyType ?? 'Owner');
    final s = widget.size;

    final avatar = AnimatedScale(
      scale: _pressed ? 0.94 : 1,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      child: Container(
        width: s,
        height: s,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.26),
              accent.withValues(alpha: 0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(s * 0.32),
          border: Border.all(color: accent.withValues(alpha: 0.38), width: 1.4),
        ),
        child: Text(
          label.isEmpty ? '\u2022' : label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: GoogleFonts.robotoMono(
            fontSize: label.length > 3 ? s * 0.27 : s * 0.33,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: accent,
          ),
        ),
      ),
    );

    if (!_loaded || !_canSwitch) return avatar;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: _open,
      onLongPress: () {
        Haptics.heavy();
        _open();
      },
      // Swipe up. velocity is negative when the finger travels upward.
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -220) _open();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          // Count pip. Tells you the account HAS other flats without opening
          // anything - otherwise the gesture is invisible.
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                    color: const Color(0xFF0D1430).withValues(alpha: 0.75),
                    width: 1.6),
              ),
              child: Text(
                '${_flats.length}',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0B1120),
                ),
              ),
            ),
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true, period: 2600.ms))
        .shimmer(
          duration: 1400.ms,
          color: accent.withValues(alpha: 0.14),
        );
  }
}

class _SwitcherSheet extends StatelessWidget {
  const _SwitcherSheet({
    required this.name,
    required this.flats,
    required this.activeId,
  });

  final String name;
  final List<FlatSummary> flats;
  final String activeId;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.72),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_kSheetTop, _kSheetBottom],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          padding: EdgeInsets.only(bottom: media.padding.bottom + 18),
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
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Your flats' : 'Signed in as ${name.split(' ').first}',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: _kOwner,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Switch flat',
                        style: GoogleFonts.fraunces(
                          fontSize: 26,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Bills, ledger and complaints all follow the flat you pick here.',
                        style: GoogleFonts.inter(
                          fontSize: 12.8,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .slideY(begin: 0.10, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    children: flats.asMap().entries.map((e) {
                      final i = e.key;
                      final f = e.value;
                      final active = f.profileId == activeId;
                      final accent = _accentFor(f.occupancyType);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Haptics.light();
                              Navigator.of(context).pop(f.profileId);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 14),
                              decoration: BoxDecoration(
                                color: active
                                    ? accent.withValues(alpha: 0.13)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: active
                                      ? accent.withValues(alpha: 0.5)
                                      : Colors.white.withValues(alpha: 0.09),
                                  width: active ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          accent.withValues(alpha: 0.22),
                                          accent.withValues(alpha: 0.10),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(13),
                                      border: Border.all(
                                          color: accent.withValues(alpha: 0.32)),
                                    ),
                                    child: Text(
                                      f.flatNo,
                                      style: GoogleFonts.robotoMono(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.5,
                                        color: accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          f.wing != null && f.wing!.isNotEmpty
                                              ? 'Wing ${f.wing} \u00b7 ${f.flatNo}'
                                              : 'Flat ${f.flatNo}',
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white
                                                .withValues(alpha: 0.94),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${f.societyName} \u00b7 ${f.occupancyType}',
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 12.2,
                                            color: Colors.white
                                                .withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (active)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.20),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        'Current',
                                        style: GoogleFonts.inter(
                                          fontSize: 9.8,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                          color: accent,
                                        ),
                                      ),
                                    )
                                  else
                                    Icon(Icons.arrow_forward_rounded,
                                        size: 18,
                                        color: Colors.white
                                            .withValues(alpha: 0.32)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                          .animate(delay: (60 * i).ms)
                          .fadeIn(duration: 300.ms)
                          .slideY(
                              begin: 0.16,
                              end: 0,
                              duration: 340.ms,
                              curve: Curves.easeOutCubic);
                    }).toList(),
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
