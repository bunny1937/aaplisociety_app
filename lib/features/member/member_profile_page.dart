import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/haptics.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/pulse_scaffold.dart';
import '../auth/bloc/auth_bloc.dart';
import '../tenant/tenant_profile_page.dart';
import 'profile/tenant_details_page.dart';
import 'sos_control.dart';
import 'pulse/member_display.dart';
import 'pulse/pulse.dart';

/// Profile tab.
///
/// Restructured per the audit (3.3): the old page was one flat 11-row list
/// where "Raise SOS" sat second, between Notifications and Change password,
/// styled like every other row. Rows are now grouped by job with section
/// labels — Account, My Tenancy, Preferences, Emergency — so tenancy work has
/// a real home and the emergency action is isolated at the bottom behind a
/// deliberate press-and-hold (see [HoldToConfirm]).
///
/// Tenants are routed to [TenantProfilePage] instead, which is their own
/// environment rather than this page with everything disabled.
class MemberProfilePage extends StatelessWidget {
  const MemberProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthed ? auth.user : const <String, dynamic>{};
    final claims = auth is AuthAuthed ? auth.claims : const <String, dynamic>{};
    final occupancyType = claims['occupancyType']?.toString();

    // Tenants get the tenant environment, not a crippled owner page.
    if (occupancyType == 'Tenant') return const TenantProfilePage();

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
    final parkingSlots =
        (member?['parkingSlots'] as List?)?.cast<Map>() ?? const <Map>[];
    final familyMembers =
        (member?['familyMembers'] as List?)?.cast<Map>() ?? const <Map>[];

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
          const SizedBox(height: 22),

          // ---- Account ---------------------------------------------------
          const PulseSectionLabel('Account'),
          PulseGroup(
            children: [
              PulseRow(
                icon: Icons.badge_outlined,
                label: 'Basic details',
                sublabel: 'Name, flat, family and parking',
                onTap: () {
                  Haptics.light();
                  context.push('/profile/basic-details', extra: {
                    'member': member,
                    'flatNo': flatNo,
                    'wing': wing,
                    'email': email,
                    'canEdit': true,
                    'parkingSlots': parkingSlots,
                    'familyMembers': familyMembers,
                  });
                },
              ),
              PulseRow(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                onTap: () {
                  Haptics.light();
                  context.push('/notifications');
                },
              ),
              PulseRow(
                icon: Icons.report_problem_outlined,
                label: 'My complaints',
                onTap: () {
                  Haptics.light();
                  context.push('/complaints');
                },
              ),
              // The services directory - ambulance, fire, society office,
              // electricity, plumber. It was asked for and never built, so the
              // numbers a resident needs at 11pm lived nowhere in the app.
              PulseRow(
                icon: Icons.contact_phone_outlined,
                label: 'Essential contacts',
                sublabel: 'Emergency, society and utility numbers',
                onTap: () {
                  Haptics.light();
                  context.push('/essential-contacts');
                },
              ),
              PulseRow(
                icon: Icons.lock_outline_rounded,
                label: 'Change password',
                onTap: () {
                  Haptics.light();
                  context.push('/change-password');
                },
              ),
            ],
          ),

          // ---- My Tenancy -------------------------------------------------
          // The three ported tenancy screens, grouped so it is obvious they
          // belong together. Previously "Add Tenant", "Rent Payments" and
          // "Tenant History" were scattered among unrelated settings rows and
          // used three different words for the same subject.
          const PulseSectionLabel('My tenancy'),
          PulseGroup(
            children: [
              PulseRow(
                icon: Icons.people_alt_outlined,
                label: 'My tenant',
                sublabel: 'Current tenancy, rent confirmations and notes',
                onTap: () {
                  Haptics.light();
                  context.push('/my-tenant');
                },
              ),
              PulseRow(
                icon: Icons.key_outlined,
                label: 'Manage tenants',
                sublabel: 'Add a tenant or record past tenancies',
                onTap: () {
                  Haptics.light();
                  context.push('/manage-tenants');
                },
              ),
              PulseRow(
                icon: Icons.currency_rupee_rounded,
                label: 'Rent payments',
                sublabel: 'Record and track rent',
                onTap: () {
                  Haptics.light();
                  context.push('/rent-payments');
                },
              ),
            ],
          ),

          // ---- Preferences ------------------------------------------------
          const PulseSectionLabel('Preferences'),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (_, mode, __) => PulseGroup(
              children: [
                PulseRow(
                  icon: mode == ThemeMode.dark
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  label: 'Dark mode',
                  trailing: Switch(
                    value: mode == ThemeMode.dark,
                    onChanged: (_) {
                      Haptics.select();
                      toggleTheme();
                    },
                  ),
                  // Tapping the row toggles too — a 20px switch was the only
                  // hit target before.
                  onTap: () {
                    Haptics.select();
                    toggleTheme();
                  },
                ),
              ],
            ),
          ),

          // ---- Emergency --------------------------------------------------
          const PulseSectionLabel('Emergency'),
          // Now the shared SosControl from sos_control.dart. It used to be a
          // private class in this file, which is why tenants - who have their
          // own profile screen - had no panic button at all.
          const SosControl(),

          const SizedBox(height: 18),
          PulseButton(
            label: 'Sign out',
            full: true,
            // Destructive, so it reads as destructive. A ghost button made it
            // look like just another row.
            variant: PulseBtnVariant.danger,
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

// The private _SosControl that used to live here has moved to
// features/member/sos_control.dart as a public SosControl widget.
// It was private to the OWNER's profile screen, which meant tenants -
// who have their own profile screen - had no panic button anywhere in
// the app. Both surfaces now mount the same control.

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
                          '${role ?? ''}${status != null ? ' \u00B7 $status' : ''}',
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
              Text(flatNo != null ? formatFlatLabel(wing, flatNo) : '\u2014',
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

/// Kept for the tenant route that still pushes a details page directly.
/// [TenantProfilePage] is the primary tenant surface; this preserves the
/// existing deep link into the tenant's own record.
Route<void> tenantDetailsRoute({
  required Map user,
  required Map? member,
  String? flatNo,
  String? wing,
  String? email,
  String? societyName,
  List<Map> parkingSlots = const [],
  List<Map> familyMembers = const [],
}) {
  return MaterialPageRoute(
    builder: (_) => TenantDetailsPage(
      user: user,
      member: member,
      flatNo: flatNo,
      wing: wing,
      email: email,
      societyName: societyName,
      parkingSlots: parkingSlots,
      familyMembers: familyMembers,
    ),
  );
}
