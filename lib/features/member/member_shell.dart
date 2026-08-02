import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/session/session_role.dart';
import '../../core/theme/haptics.dart';
import '../auth/bloc/auth_bloc.dart';
import 'pulse/pulse_tokens.dart';
import 'dashboard_page.dart';
import 'bills_page.dart';
import 'notices_page.dart';
import 'visitors_page.dart';
import 'member_profile_page.dart';

/// Cross-screen tab switcher: pages nested inside [MemberShell] (Dashboard's
/// quick actions, notice bell, etc.) set this to jump tabs without needing a
/// BuildContext-based shell handle. Same pattern as `theme_controller.dart`'s
/// `themeModeNotifier`.
final memberTabNotifier = ValueNotifier<int>(0);

/// Request a tab **by label** ("Visitors", "Notices", ...).
///
/// Push taps cannot use [memberTabNotifier] directly: Visitors is index 3 for an
/// owner but index 2 for a tenant (no Bills tab), so a hardcoded index sends
/// every tenant to the wrong screen. Set by `PushService._openTarget`, drained
/// (and reset to null) by [MemberShell] - including on its first frame, so a
/// cold start from a notification tap still lands correctly.
final memberTabRequestNotifier = ValueNotifier<String?>(null);

/// Bottom-tab shell for the member surface, re-skinned to the "Pulse Mobile"
/// design (ui_kits/member-v2 index.html TABS array + BottomNav primitive):
/// Home / Bills / Notices / Visitors / Profile, frosted-glass bar. Ledger,
/// Receipts and Complaints are reached via pushed go_router routes from
/// Dashboard/Profile quick actions rather than as extra tabs, matching the
/// design's "layered over tab, Back to return" pattern.
class MemberShell extends StatefulWidget {
  const MemberShell({super.key});
  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _NavItem {
  final IconData icon;
  final IconData iconFilled;
  final String label;
  const _NavItem(this.icon, this.iconFilled, this.label);
}

class _MemberShellState extends State<MemberShell> {
  int _i = 0;
  int _pendingVisitors = 0;
  List<Widget> _pages(bool isTenant) => [
        const DashboardPage(),
        if (!isTenant) const BillsPage(),
        const NoticesPage(),
        const VisitorsPage(),
        const MemberProfilePage(),
      ];
  List<_NavItem> _items(bool isTenant) => [
        const _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
        if (!isTenant)
          const _NavItem(
              Icons.description_outlined, Icons.description_rounded, 'Bills'),
        const _NavItem(
            Icons.campaign_outlined, Icons.campaign_rounded, 'Notices'),
        const _NavItem(Icons.person_add_alt_outlined,
            Icons.person_add_alt_1_rounded, 'Visitors'),
        const _NavItem(Icons.account_circle_outlined,
            Icons.account_circle_rounded, 'Profile'),
      ];
  @override
  void initState() {
    super.initState();
    _loadPendingVisitors();
    memberTabNotifier.addListener(_onTabRequest);
    memberTabRequestNotifier.addListener(_onTabLabelRequest);
    // Cold start from a notification tap: the request was set before this shell
    // existed, so there was no listener to hear it. Drain it once we are
    // mounted and can read AuthBloc.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _onTabLabelRequest());
  }

  @override
  void dispose() {
    memberTabNotifier.removeListener(_onTabRequest);
    memberTabRequestNotifier.removeListener(_onTabLabelRequest);
    super.dispose();
  }

  void _onTabLabelRequest() {
    final label = memberTabRequestNotifier.value;
    if (label == null || !mounted) return;
    final authState = context.read<AuthBloc>().state;
    final isTenant = authState is AuthAuthed &&
        authState.claims['occupancyType'] == 'Tenant';
    final index = _items(isTenant).indexWhere((it) => it.label == label);
    // Consume the request either way, so a stale label cannot fire again on the
    // next rebuild.
    memberTabRequestNotifier.value = null;
    if (index < 0) return;
    memberTabNotifier.value = index;
    if (index != _i) setState(() => _i = index);
  }

  void _onTabRequest() {
    if (mounted && memberTabNotifier.value != _i) {
      setState(() => _i = memberTabNotifier.value);
    }
  }

  Future<void> _loadPendingVisitors() async {
    try {
      final dio = context.read<Dio>();
      final res = (await dio.get('/visitors')).data['visitors'] as List;
      final pending =
          res.where((v) => (v as Map)['status'] == 'Pending').length;
      if (mounted) setState(() => _pendingVisitors = pending);
    } catch (_) {
      // dashboard/visitors pages surface real errors; nav badge fails silent
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final authState = context.watch<AuthBloc>().state;
    final isTenant = authState is AuthAuthed &&
        authState.claims['occupancyType'] == 'Tenant';
    // Publish the role for code that has no BuildContext - specifically the
    // push notification router, which was sending tenants to owner-only screens
    // (a rent reminder opened the OWNER's maintenance receipts) because it had
    // no idea who was holding the phone.
    publishIsTenant(isTenant);

    final pages = _pages(isTenant);
    final items = _items(isTenant);
    if (_i >= pages.length) _i = 0;
    return Scaffold(
      backgroundColor: t.canvas,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: KeyedSubtree(key: ValueKey(_i), child: pages[_i]),
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: EdgeInsets.fromLTRB(
                14, 10, 14, MediaQuery.of(context).padding.bottom + 10),
            decoration: BoxDecoration(
              color: t.surface.withValues(alpha: 0.86),
              border: Border(top: BorderSide(color: t.hairline)),
            ),
            child: Row(
              children: List.generate(items.length, (i) {
                final active = i == _i;
                final item = items[i];
                final showBadge =
                    item.label == 'Visitors' && _pendingVisitors > 0;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Haptics.select();
                      memberTabNotifier.value = i;
                      setState(() => _i = i);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(active ? item.iconFilled : item.icon,
                                  size: 22, color: active ? t.brand : t.fg4),
                              if (showBadge)
                                Positioned(
                                  top: -3,
                                  right: -6,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                        color: t.danger,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 1.5)),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.label,
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight:
                                    active ? FontWeight.w700 : FontWeight.w600,
                                color: active ? t.brand : t.fg4),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
