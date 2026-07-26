import 'package:flutter/material.dart';
import '../../features/member/pulse/pulse.dart';

/// The ONLY page chrome in the app.
///
/// Audit root cause RC-1: `LedgerPage` returned a bare `SafeArea > Column`
/// with no [Scaffold]. When pushed as its own route (`/ledger`) it therefore
/// had:
///   * no `backgroundColor` — the black window showed through, and
///   * no `Material`/`DefaultTextStyle` ancestor — so Flutter fell back to
///     its internal `_kErrorTextStyle`, which is monospace with a **yellow
///     double underline**. That is what the dark-mode screenshots showed.
///     It was never a theming choice; it was Flutter reporting a broken tree.
///   * no back affordance — the user was trapped.
///
/// RC-3/X-3: it also collapses the two competing headers (stock navy
/// `AppBar` on 5 screens vs `PulseTopBar` large-title on 4) into one.
///
/// Every route in `lib/app/router.dart` must render a [PulseScaffold] (or a
/// `Scaffold`). `tool/ui_guard.sh` fails CI otherwise.
class PulseScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  /// Shows the back chevron. Defaults to true because this widget exists for
  /// pushed routes; tab children inside `MemberShell` pass `false`.
  final bool showBack;
  final List<Widget> trailing;
  final Widget? leading;
  final Widget? floatingActionButton;

  /// Sticky footer — use for the primary CTA of a form so it can never be
  /// clipped by the screen edge (audit 3.4: `Submit request` was cut in half).
  final Widget? bottomBar;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;
  final Future<void> Function()? onRefresh;

  const PulseScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.showBack = true,
    this.trailing = const [],
    this.leading,
    this.floatingActionButton,
    this.bottomBar,
    this.scrollable = false,
    this.padding,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final canPop = Navigator.of(context).canPop();

    Widget body = child;
    if (scrollable) {
      body = SingleChildScrollView(
        padding: padding ?? const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: child,
      );
    } else if (padding != null) {
      body = Padding(padding: padding!, child: child);
    }
    if (onRefresh != null) {
      body = RefreshIndicator(
        onRefresh: onRefresh!,
        color: t.brand,
        backgroundColor: t.surface,
        child: body,
      );
    }

    return Scaffold(
      // Fixes the black window in dark mode.
      backgroundColor: t.canvas,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Column(
          children: [
            PulseTopBar(
              title: title,
              subtitle: subtitle,
              leading: leading ??
                  (showBack && canPop
                      ? PulseIconButton(
                          icon: Icons.arrow_back_rounded,
                          onTap: () => Navigator.of(context).maybePop(),
                        )
                      : null),
              trailing: trailing,
            ),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: bottomBar == null
          ? null
          : _StickyFooter(tokens: t, child: bottomBar!),
    );
  }
}

class _StickyFooter extends StatelessWidget {
  final PulseTokens tokens;
  final Widget child;
  const _StickyFooter({required this.tokens, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        // Respect the gesture bar so the CTA is always reachable.
        12 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: child,
    );
  }
}

/// Section label used to group rows into one container instead of N floating
/// cards (audit 3.3: Profile stacked 10 separate bordered cards).
class PulseSectionLabel extends StatelessWidget {
  final String label;
  final EdgeInsetsGeometry padding;
  const PulseSectionLabel(this.label,
      {super.key, this.padding = const EdgeInsets.fromLTRB(4, 18, 4, 8)});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: padding,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: t.fg4,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// A grouped list container: one rounded surface, hairline dividers between
/// rows. Replaces per-row `Container` decorations.
class PulseGroup extends StatelessWidget {
  final List<Widget> children;
  const PulseGroup({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Divider(height: 1, thickness: 1, color: t.hairline));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(PulseTokens.radius),
        boxShadow: t.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

/// A single settings/navigation row. Guarantees a 48dp touch target (X-10).
class PulseRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  const PulseRow({
    super.key,
    required this.icon,
    required this.label,
    this.sublabel,
    this.trailing,
    this.onTap,
    this.danger = false,
  });
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final fg = danger ? t.danger : t.fg1;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: danger ? t.dangerSoft : t.surface3,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 17, color: danger ? t.danger : t.fg3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          // The mockup used CSS font-weight 650. Flutter only
                          // exposes w100-w900 in hundreds, and w600 is the
                          // closest that still renders with Poppins.
                          fontWeight: FontWeight.w600,
                          color: fg)),
                  if (sublabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(sublabel!,
                          style: TextStyle(fontSize: 11.5, color: t.fg4)),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(Icons.chevron_right_rounded, size: 20, color: t.fg5),
          ],
        ),
      ),
    );
  }
}
