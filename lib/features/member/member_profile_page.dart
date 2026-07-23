import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'pulse/member_display.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/theme/haptics.dart';
import '../../core/network/api_error.dart';
import '../auth/bloc/auth_bloc.dart';
import 'pulse/pulse.dart';

/// Profile tab — port of ui_kits/member-v2 `ScreensVisitorsProfile.jsx`
/// `ProfileScreen`: gradient header + a tile list. Each info section (Flat
/// details, Contact, Parking, Family members, Emergency contact) now lives on
/// its own page under `profile/`, reached via tiles below, instead of being
/// stacked inline — see docs/superpowers/specs/2026-07-19-profile-restructure-design.md.
/// Contact/Family members/Emergency contact are editable there by the flat's
/// owner, but only via an approval-pending request — see that page's Edit flow.
/// The old page's navigation tiles (Change password / My complaints /
/// dark-mode toggle) are folded in below unchanged; "Visitor history" tile is
/// dropped because that history now lives directly on the Visitors tab.
class MemberProfilePage extends StatelessWidget {
  const MemberProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthed ? auth.user : const <String, dynamic>{};
    final claims = auth is AuthAuthed ? auth.claims : const <String, dynamic>{};
    final displayName = resolveDisplayName(user);
    final email = user['email']?.toString();
    final profiles = (user['profiles'] as List?) ?? const [];
    final activeProfile = profiles.cast<Map?>().firstWhere(
          (p) => p != null && '${p['_id']}' == '${claims['activeProfileId']}',
          orElse: () => profiles.isNotEmpty ? profiles.first as Map : null,
        );
    final member = user['member'] as Map?;
    final flatNo = (member?['flatNo'] ?? activeProfile?['flatNo'])?.toString();
    final wing = (member?['wing'] ?? activeProfile?['wing'])?.toString();
    final societyName = resolveSocietyName(user, activeProfile);
    final role =
        claims['role']?.toString() ?? activeProfile?['role']?.toString();
    final status = activeProfile?['status']?.toString();
    final occupancyType = claims['occupancyType']?.toString();
    final parkingSlots =
        (member?['parkingSlots'] as List?)?.cast<Map>() ?? const <Map>[];
    final familyMembers =
        (member?['familyMembers'] as List?)?.cast<Map>() ?? const <Map>[];
    final canEdit = occupancyType != 'Tenant';
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _Header(
              username: displayName,
              wing: wing,
              flatNo: flatNo,
              societyName: societyName,
              role: role,
              status: status),
          const SizedBox(height: 20),
          _Tile(
            icon: Icons.badge_outlined,
            label: 'Basic details',
            onTap: () {
              Haptics.light();
              context.push('/profile/basic-details', extra: {
                'member': member,
                'flatNo': flatNo,
                'wing': wing,
                'email': email,
                'canEdit': canEdit,
                'parkingSlots': parkingSlots,
                'familyMembers': familyMembers,
              });
            },
          ),
          const SizedBox(height: 8),
          Text('More',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: t.fg1)),
          const SizedBox(height: 10),
          const _SosTile(),
          _Tile(
              icon: Icons.notifications_outlined,
              label: 'Notifications',
              onTap: () {
                Haptics.light();
                context.push('/notifications');
              }),
          _Tile(
              icon: Icons.lock_outline_rounded,
              label: 'Change password',
              onTap: () {
                Haptics.light();
                context.push('/change-password');
              }),
          _Tile(
              icon: Icons.report_problem_outlined,
              label: 'My complaints',
              onTap: () {
                Haptics.light();
                context.push('/complaints');
              }),
          if (occupancyType != 'Tenant')
            _Tile(
                icon: Icons.key_outlined,
                label: 'Add Tenant',
                onTap: () {
                  Haptics.light();
                  context.push('/add-tenant');
                }),
          _Tile(
              icon: Icons.receipt_outlined,
              label: 'Rent Payments',
              onTap: () {
                Haptics.light();
                context.push('/rent-payments');
              }),
          if (occupancyType != 'Tenant')
            _Tile(
                icon: Icons.history_outlined,
                label: 'Tenant History',
                onTap: () {
                  Haptics.light();
                  context.push('/tenant-history');
                }),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (_, mode, __) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                  color: t.surface,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
              child: Row(
                children: [
                  Icon(
                      mode == ThemeMode.dark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      color: t.fg3,
                      size: 19),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text('Dark mode',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: t.fg1))),
                  Switch(
                      value: mode == ThemeMode.dark,
                      activeThumbColor: t.brand,
                      onChanged: (_) {
                        Haptics.select();
                        toggleTheme();
                      }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          PulseButton(
            label: 'Sign out',
            full: true,
            variant: PulseBtnVariant.ghost,
            icon: Icons.logout_rounded,
            onTap: () {
              Haptics.heavy();
              context.read<AuthBloc>().add(LogoutRequested());
              context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String username;
  final String? wing;
  final String? flatNo;
  final String? societyName;
  final String? role;
  final String? status;
  const _Header(
      {required this.username,
      this.wing,
      this.flatNo,
      this.societyName,
      this.role,
      this.status});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PulseTokens.radiusLg),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [t.brand2, t.brand]),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PulseAvatar(name: username, size: 52, ring: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                if (societyName != null)
                  Text(societyName!,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12)),
                if (role != null || status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(
                          '${role ?? ''}${status != null ? ' · $status' : ''}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(flatNo != null ? formatFlatLabel(wing, flatNo) : '—',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
              Text('Flat',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Raises POST /visitors/sos — a panic alert to security + admin (see
/// mobile-backend's visitor.controller.ts and queues/index.ts's
/// NOTIFICATION_TYPES.VISITOR_SOS handling). Confirms first since this is a
/// real emergency dispatch, not a reversible action.
class _SosTile extends StatefulWidget {
  const _SosTile();
  @override
  State<_SosTile> createState() => _SosTileState();
}

class _SosTileState extends State<_SosTile> {
  bool _sending = false;
  Future<void> _raise(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Raise SOS alert?'),
        content: const Text(
            'This immediately notifies security and society admins of an emergency at your flat.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child:
                  const Text('Raise SOS', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    setState(() => _sending = true);
    Haptics.heavy();
    try {
      final dio = context.read<Dio>();
      await dio.post('/visitors/sos');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('SOS alert sent to security and admin'),
            backgroundColor: Colors.red),
      );
    } on DioException catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(err))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
          onTap: _sending ? null : () => _raise(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.sos_rounded, color: Colors.red, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Raise SOS',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: Colors.red))),
                if (_sending)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PulseCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: t.fg3, size: 19),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: t.fg1))),
            Icon(Icons.chevron_right_rounded, color: t.fg4),
          ],
        ),
      ),
    );
  }
}
