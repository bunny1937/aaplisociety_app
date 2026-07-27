import 'package:flutter/material.dart';
import '../../../core/theme/haptics.dart';
import 'pulse_tokens.dart';

/// Port of Primitives.jsx `TopBar` — large-title header used at the top of
/// every tab screen (title/subtitle + optional leading avatar + trailing
/// actions).
class PulseTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> trailing;
  final bool large;

  /// Set false to suppress the automatic back chevron on a pushed route.
  final bool showBack;
  const PulseTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing = const [],
    this.large = true,
    this.showBack = true,
  });
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    // Automatic back button.
    //
    // This header replaced Material's AppBar on the member screens, and AppBar
    // is what normally supplies the back arrow (automaticallyImplyLeading).
    // Nothing took over that job, so every pushed page that uses this bar had
    // no way back on Android beyond the system gesture, and on iOS only the
    // edge-swipe.
    //
    // canPop is the right condition: bottom-nav tab roots live in an
    // IndexedStack and have nothing to pop, so they correctly get no arrow,
    // while every pushed route gets one. An explicit `leading` (the dashboard
    // avatar) still wins.
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final effectiveLeading = leading ??
        (showBack && canPop
            ? Padding(
                padding: EdgeInsets.only(top: large ? 4 : 0),
                child: PulseIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  size: 36,
                  onTap: () {
                    Haptics.light();
                    // maybePop, not pop: respects any PopScope guard on the
                    // page instead of tearing it down.
                    Navigator.of(context).maybePop();
                  },
                ),
              )
            : null);
    return Padding(
      padding: large
          ? const EdgeInsets.fromLTRB(20, 8, 20, 14)
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment:
            large ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (effectiveLeading != null) ...[
            effectiveLeading,
            const SizedBox(width: 10)
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: large ? 26 : 17,
                    fontWeight: FontWeight.w800,
                    color: t.fg1,
                    letterSpacing: -0.4,
                    height: 1.15,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        style: TextStyle(fontSize: 12.5, color: t.fg4)),
                  ),
              ],
            ),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 12),
            Row(mainAxisSize: MainAxisSize.min, children: trailing),
          ],
        ],
      ),
    );
  }
}

/// Port of Primitives.jsx `IconBtn` — circular icon button, optional badge.
class PulseIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final int? badge;
  final double size;
  const PulseIconButton(
      {super.key, required this.icon, this.onTap, this.badge, this.size = 38});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              Haptics.light();
              onTap!();
            },
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(size / 2.6),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 17, color: t.fg2),
            ),
            if (badge != null && badge! > 0)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: t.danger,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: t.canvas, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text('$badge',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
