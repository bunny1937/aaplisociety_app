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
// accent (indigo owner / green tenant). On a shared account you must be able to
// tell at a glance which flat you are acting as before you pay a bill against
// the wrong one.
//
// ---------------------------------------------------------------------------
// THE JELLY PASS
// ---------------------------------------------------------------------------
// "create some soooth fluid switch or jellly animation".
//
// Everything here is transform + opacity only, so it stays on the compositor
// and never triggers layout. Three physical behaviours:
//
//   1. SQUISH    - press scales to 0.90 on X but 0.83 on Y, the way a soft body
//                  deforms under a finger. A uniform scale reads like a button;
//                  a non-uniform one reads like jelly.
//   2. OVERSHOOT - release springs back through Curves.elasticOut over 620ms,
//                  so it wobbles past 1.0 and settles. That wobble IS the jelly.
//   3. MORPH     - the corner radius breathes from squircle toward circle during
//                  the press, and an accent glow blooms with it, so the
//                  silhouette itself is soft.
//
// All three are driven off ONE controller per element via AnimatedBuilder.
// Three separate implicit animations would drift out of phase and stop reading
// as a single soft body.

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

class _FlatSwitcherAvatarState extends State<FlatSwitcherAvatar>
    with TickerProviderStateMixin {
  List<FlatSummary> _flats = const [];
  String _activeId = '';
  String _name = '';
  bool _loaded = false;

  // The jelly driver. 0 = at rest, 1 = fully squished.
  late final AnimationController _squish = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    reverseDuration: const Duration(milliseconds: 620),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _squish.dispose();
    super.dispose();
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

  // Release with an elastic settle. reverse() runs the 620ms reverseDuration,
  // and the elasticOut curve inside build() turns that into the wobble.
  void _release() => _squish.reverse();

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
    Haptics.success();
    setState(() => _activeId = chosen);
    context.read<AuthBloc>().add(SwitchProfileInSession(chosen));
  }

  @override
  Widget build(BuildContext context) {
    final flat = _active;
    final label = flat?.flatNo ?? '';
    final accent = _accentFor(flat?.occupancyType ?? 'Owner');
    final s = widget.size;

    final avatar = AnimatedBuilder(
      animation: _squish,
      builder: (context, child) {
        // elasticOut on the way back out is what produces the overshoot.
        final raw = _squish.value.clamp(0.0, 1.0);
        final t = _squish.status == AnimationStatus.reverse
            ? Curves.elasticOut.transform(raw)
            : Curves.easeOutCubic.transform(raw);

        // Non-uniform squash. Wider than it is tall while pressed.
        final sx = 1.0 - (0.10 * t);
        final sy = 1.0 - (0.17 * t);

        return Transform.scale(
          scaleX: sx,
          scaleY: sy,
          filterQuality: FilterQuality.low,
          child: Container(
            width: s,
            height: s,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.26 + 0.10 * t),
                  accent.withValues(alpha: 0.10),
                ],
              ),
              // The silhouette softens toward a circle under the finger.
              borderRadius: BorderRadius.circular(s * (0.32 + 0.18 * t)),
              border: Border.all(
                color: accent.withValues(alpha: 0.38 + 0.30 * t),
                width: 1.4,
              ),
              boxShadow: t > 0.02
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.22 * t),
                        blurRadius: 16 * t,
                        spreadRadius: 1.5 * t,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        );
      },
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
    );

    if (!_loaded || !_canSwitch) return avatar;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _squish.forward(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      onTap: _open,
      onLongPress: () {
        Haptics.heavy();
        _release();
        _open();
      },
      // Swipe up. velocity is negative when the finger travels upward.
      onVerticalDragEnd: (d) {
        _release();
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
                ).animate().scaleX(
                      begin: 0.3,
                      end: 1,
                      duration: 480.ms,
                      curve: Curves.elasticOut,
                    ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty
                            ? 'Your flats'
                            : 'Signed in as ${name.split(' ').first}',
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
                        child: _JellyRow(
                          accent: accent,
                          active: active,
                          flat: f,
                          onPicked: () => Navigator.of(context).pop(f.profileId),
                        ),
                      )
                          .animate()
                          // Spring-staggered entry. Each row lands a beat after
                          // the one above and overshoots very slightly, so the
                          // list settles like a stack of soft cards instead of
                          // snapping into place.
                          .fadeIn(delay: (60 * i).ms, duration: 260.ms)
                          .slideY(
                            begin: 0.22,
                            end: 0,
                            delay: (60 * i).ms,
                            duration: 520.ms,
                            curve: Curves.elasticOut,
                          )
                          .scaleXY(
                            begin: 0.94,
                            end: 1,
                            delay: (60 * i).ms,
                            duration: 520.ms,
                            curve: Curves.elasticOut,
                          );
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

/// One flat row that squishes under the finger and wobbles on selection.
///
/// Split out of the old inline InkWell because a jelly press needs its own
/// controller per row, and an InkWell ripple fights the squash visually.
class _JellyRow extends StatefulWidget {
  const _JellyRow({
    required this.accent,
    required this.active,
    required this.flat,
    required this.onPicked,
  });

  final Color accent;
  final bool active;
  final FlatSummary flat;
  final VoidCallback onPicked;

  @override
  State<_JellyRow> createState() => _JellyRowState();
}

class _JellyRowState extends State<_JellyRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 130),
    reverseDuration: const Duration(milliseconds: 560),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    Haptics.light();
    // Let the release wobble start before the sheet dismisses, so the choice is
    // visibly acknowledged rather than the sheet just vanishing.
    _c.reverse();
    await Future<void>.delayed(const Duration(milliseconds: 110));
    if (mounted) widget.onPicked();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.flat;
    final accent = widget.accent;
    final active = widget.active;
    final wing = f.wing ?? '';
    final unit = wing.trim().isEmpty ? f.flatNo : '$wing-${f.flatNo}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _c.forward(),
      onTapUp: (_) => _c.reverse(),
      onTapCancel: () => _c.reverse(),
      onTap: _tap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final raw = _c.value.clamp(0.0, 1.0);
          final t = _c.status == AnimationStatus.reverse
              ? Curves.elasticOut.transform(raw)
              : Curves.easeOutCubic.transform(raw);
          return Transform.scale(
            scaleX: 1.0 - (0.025 * t),
            scaleY: 1.0 - (0.055 * t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
              decoration: BoxDecoration(
                color: active
                    ? accent.withValues(alpha: 0.13 + 0.06 * t)
                    : Colors.white.withValues(alpha: 0.05 + 0.05 * t),
                borderRadius: BorderRadius.circular(16 + 6 * t),
                border: Border.all(
                  color: active
                      ? accent.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.09 + 0.16 * t),
                  width: active ? 1.5 : 1,
                ),
              ),
              child: child,
            ),
          );
        },
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                    color: accent.withValues(alpha: 0.34), width: 1.2),
              ),
              child: Text(
                f.flatNo.isEmpty ? '\u2022' : f.flatNo,
                style: GoogleFonts.robotoMono(
                  fontSize: f.flatNo.length > 3 ? 12 : 14,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit.isEmpty ? f.label : unit,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${f.societyName}  \u00b7  ${f.occupancyType}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11.8,
                      color: Colors.white.withValues(alpha: 0.52),
                    ),
                  ),
                ],
              ),
            ),
            if (active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'Current',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: Colors.white.withValues(alpha: 0.28)),
          ],
        ),
      ),
    );
  }
}
