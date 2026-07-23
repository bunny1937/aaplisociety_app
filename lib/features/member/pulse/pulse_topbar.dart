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
  const PulseTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing = const [],
    this.large = true,
  });
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: large
          ? const EdgeInsets.fromLTRB(20, 8, 20, 14)
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment:
            large ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
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
