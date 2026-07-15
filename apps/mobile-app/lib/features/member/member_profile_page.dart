import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/theme/haptics.dart';
import '../auth/bloc/auth_bloc.dart';
import 'pulse/member_display.dart';
import 'pulse/pulse.dart';

/// Profile tab — port of ui_kits/member-v2 `ScreensVisitorsProfile.jsx`
/// `ProfileScreen`: gradient header, stacked info sections, danger sign-out.
/// Per user decision, sections the design wants (family members, parking
/// slots, emergency contact, carpet/built-up area, ownership type) that
/// don't exist on the backend yet render "Not available yet" rather than
/// being hidden — ready to light up once those fields ship (see
/// MEMBER_V2_GAPS.md). The old page's navigation tiles (Change password /
/// My complaints / dark-mode toggle) are folded in below the design's info
/// blocks so those destinations stay reachable; "Visitor history" tile is
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
    final role = claims['role']?.toString() ?? activeProfile?['role']?.toString();
    final status = activeProfile?['status']?.toString();
    final carpetArea = member?['carpetAreaSqft'];
    final builtUpArea = member?['builtUpAreaSqft'];
    final areaText = carpetArea != null
        ? '$carpetArea sqft (carpet)${builtUpArea != null ? ' · $builtUpArea sqft (built-up)' : ''}'
        : null;
    final votingRights = member?['hasVotingRights'];
    final votingText = votingRights == null ? null : (votingRights == true ? 'Eligible' : 'Not eligible');
    final parkingSlots = (member?['parkingSlots'] as List?)?.cast<Map>() ?? const <Map>[];
    final familyMembers = (member?['familyMembers'] as List?)?.cast<Map>() ?? const <Map>[];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _Header(username: displayName, wing: wing, flatNo: flatNo, societyName: societyName, role: role, status: status),
          const SizedBox(height: 20),
          _Section(
            icon: Icons.home_work_outlined,
            title: 'Flat details',
            rows: [
              ('Flat', flatNo != null ? '$flatNo${wing != null && wing.isNotEmpty ? ' ($wing wing)' : ''}' : null),
              ('Type', member?['flatType']?.toString()),
              ('Ownership', member?['ownershipType']?.toString()),
              ('Carpet area', areaText),
              ('Voting rights', votingText),
            ],
          ),
          _Section(
            icon: Icons.call_outlined,
            title: 'Contact',
            rows: [
              ('Email', email),
              ('Phone', (member?['contactNumber'] ?? user['phone'])?.toString()),
              ('WhatsApp', member?['whatsappNumber']?.toString()),
            ],
          ),
          _ParkingSection(slots: parkingSlots),
          _FamilySection(members: familyMembers),
          const _Section(icon: Icons.emergency_outlined, title: 'Emergency contact', rows: [('Contact', null)]),
          const SizedBox(height: 8),
          Text('More', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: t.fg1)),
          const SizedBox(height: 10),
          _Tile(icon: Icons.lock_outline_rounded, label: 'Change password', onTap: () { Haptics.light(); context.push('/change-password'); }),
          _Tile(icon: Icons.report_problem_outlined, label: 'My complaints', onTap: () { Haptics.light(); context.push('/complaints'); }),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (_, mode, __) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(color: t.surface, border: Border.all(color: t.border), borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
              child: Row(
                children: [
                  Icon(mode == ThemeMode.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: t.fg3, size: 19),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Dark mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: t.fg1))),
                  Switch(value: mode == ThemeMode.dark, activeThumbColor: t.brand, onChanged: (_) { Haptics.select(); toggleTheme(); }),
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
            onTap: () { Haptics.heavy(); context.read<AuthBloc>().add(LogoutRequested()); context.go('/login'); },
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
  const _Header({required this.username, this.wing, this.flatNo, this.societyName, this.role, this.status});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PulseTokens.radiusLg),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [t.brand2, t.brand]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulseAvatar(name: username, size: 52, ring: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(username, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    if (societyName != null) Text(societyName!, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
                    if (role != null || status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(999)),
                          child: Text('${role ?? ''}${status != null ? ' · $status' : ''}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(flatNo != null ? '${wing != null && wing!.isNotEmpty ? '$wing-' : ''}$flatNo' : '—', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          Text('Flat', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<(String, String?)> rows;
  const _Section({required this.icon, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PulseCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: t.brand),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: t.fg2)),
              ],
            ),
            const SizedBox(height: 10),
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(width: 100, child: Text(r.$1, style: TextStyle(fontSize: 12.5, color: t.fg4))),
                      Expanded(
                        child: Text(
                          r.$2 ?? 'Not available yet',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: r.$2 != null ? t.fg1 : t.fg5, fontStyle: r.$2 != null ? FontStyle.normal : FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
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
            Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: t.fg1))),
            Icon(Icons.chevron_right_rounded, color: t.fg4),
          ],
        ),
      ),
    );
  }
}

class _ParkingSection extends StatelessWidget {
  final List<Map> slots;
  const _ParkingSection({required this.slots});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PulseCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_parking_outlined, size: 16, color: t.brand),
                const SizedBox(width: 8),
                Text('Parking', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: t.fg2)),
              ],
            ),
            const SizedBox(height: 10),
            if (slots.isEmpty)
              Text('Not available yet', style: TextStyle(fontSize: 12.5, color: t.fg5, fontStyle: FontStyle.italic))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: slots.map((s) {
                  final label = '${s['slotNumber'] ?? '—'}';
                  final sub = [s['type'], s['vehicleType']]
                      .where((v) => v != null && '$v'.isNotEmpty)
                      .join(' · ');
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: t.brandSoft, borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: t.brand)),
                        if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 10.5, color: t.fg4)),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _FamilySection extends StatelessWidget {
  final List<Map> members;
  const _FamilySection({required this.members});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PulseCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.family_restroom_outlined, size: 16, color: t.brand),
                const SizedBox(width: 8),
                Text('Family members', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: t.fg2)),
              ],
            ),
            const SizedBox(height: 10),
            if (members.isEmpty)
              Text('Not available yet', style: TextStyle(fontSize: 12.5, color: t.fg5, fontStyle: FontStyle.italic))
            else
              ...members.map((m) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${m['name'] ?? '—'}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.fg1)),
                        ),
                        Text(
                          [m['relation'], m['age'] != null ? '${m['age']} yrs' : null]
                              .where((v) => v != null && '$v'.isNotEmpty)
                              .join(' · '),
                          style: TextStyle(fontSize: 11.5, color: t.fg4),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
