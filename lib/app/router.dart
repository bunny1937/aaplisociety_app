import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/splash/splash_page.dart';
import '../features/auth/login_page.dart';
import '../features/auth/profile_select_page.dart';
import '../features/member/member_shell.dart';
import '../features/member/bills_page.dart';
import '../features/member/ledger_page.dart';
import '../features/tenant/tenant_profile_page.dart';
import '../features/member/receipts_page.dart';
import '../features/complaints/complaints_page.dart';
import '../features/security/security_shell.dart';
import '../features/admin/admin_shell.dart';
import '../features/auth/change_password_page.dart';
import '../features/auth/forgot_password_page.dart';
import '../features/auth/reset_password_page.dart';
import '../features/tenant/add_tenant_page.dart';
import '../features/tenant/rent_payment_page.dart';
import '../features/tenant/tenant_history_page.dart';
import '../features/tenant/my_tenant_page.dart';
import '../features/tenant/manage_tenants_page.dart';
import '../features/member/payment_history_page.dart';
import '../features/notifications/notification_center_page.dart';
import '../features/member/profile/flat_details_page.dart';
import '../features/member/profile/parking_page.dart';
import '../features/member/profile/family_members_page.dart';
import '../features/member/profile/emergency_contact_page.dart';
import '../features/member/profile/basic_details_page.dart';
import '../features/member/essential_contacts_page.dart';
import '../features/onboarding/data/onboarding_api.dart';
import '../features/onboarding/existing_account_page.dart';
import '../features/onboarding/new_account_setup_page.dart';
import '../features/onboarding/onboarding_gate_page.dart';
import '../features/amenities/amenities_page.dart';
import '../features/amenities/amenity_detail_page.dart';
import '../features/amenities/amenity_qr_scan_page.dart';
import '../features/amenities/my_attendance_page.dart';
import '../features/amenities/amenity_events_page.dart';
import '../features/commercial/commercial_directory_page.dart';
import '../features/commercial/business_detail_page.dart';
import '../features/commercial/my_business_page.dart';
import '../features/commercial/business_profile_edit_page.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (c, s) => const SplashPage()),
        GoRoute(
            path: '/login', pageBuilder: (c, s) => _fade(const LoginPage(), s)),
        // ── Onboarding ──────────────────────────────────────────────
        // Reached by deep link from the activation email, or manually from
        // the login screen's "Activate my flat" link.
        GoRoute(
            path: '/onboarding',
            pageBuilder: (c, s) => _fade(
                OnboardingGatePage(token: s.uri.queryParameters['token']), s)),
        GoRoute(
            path: '/onboarding/setup',
            pageBuilder: (c, s) {
              final extra = (s.extra as Map<String, dynamic>?) ?? const {};
              return _fade(
                NewAccountSetupPage(
                  token: (extra['token'] ?? '') as String,
                  email: (extra['email'] ?? '') as String,
                  name: extra['name'] as String?,
                  flats: (extra['flats'] as List<FlatSummary>?) ?? const [],
                ),
                s,
              );
            }),
        GoRoute(
            path: '/onboarding/existing',
            pageBuilder: (c, s) {
              final extra = (s.extra as Map<String, dynamic>?) ?? const {};
              return _fade(
                ExistingAccountPage(
                  result: extra['result'] as LookupResult,
                  email: (extra['email'] ?? '') as String,
                ),
                s,
              );
            }),
        GoRoute(
            path: '/select-profile',
            builder: (c, s) => const ProfileSelectPage()),
        GoRoute(
            path: '/forgot-password',
            pageBuilder: (c, s) => _fade(const ForgotPasswordPage(), s)),
        GoRoute(
            path: '/reset-password',
            pageBuilder: (c, s) {
              final extra = s.extra as Map<String, dynamic>?;
              return _fade(
                  ResetPasswordPage(
                      identifier: extra?['identifier'] as String? ?? ''),
                  s);
            }),
        GoRoute(
            path: '/member',
            pageBuilder: (c, s) => _fade(const MemberShell(), s)),
        GoRoute(
            path: '/security',
            pageBuilder: (c, s) => _fade(const SecurityShell(), s)),
        GoRoute(
            path: '/admin',
            pageBuilder: (c, s) => _fade(const AdminShell(), s)),
        GoRoute(
            path: '/change-password',
            pageBuilder: (c, s) {
              final extra = s.extra as Map<String, dynamic>?;
              return _fade(
                  ChangePasswordPage(
                    forced: extra?['forced'] == true,
                    roleForRedirect: extra?['role'] as String?,
                  ),
                  s);
            }),
        GoRoute(
            path: '/bills',
            pageBuilder: (c, s) => _fade(
                Scaffold(
                    appBar: AppBar(
                        backgroundColor: Colors.transparent, elevation: 0),
                    body: const BillsPage()),
                s)),
        GoRoute(
            path: '/complaints',
            pageBuilder: (c, s) => _fade(const ComplaintsPage(), s)),
        GoRoute(
            path: '/ledger',
            pageBuilder: (c, s) => _fade(const LedgerPage(), s)),
        GoRoute(
            path: '/receipts',
            pageBuilder: (c, s) => _fade(const ReceiptsPage(), s)),
        GoRoute(
            path: '/add-tenant',
            pageBuilder: (c, s) => _fade(const AddTenantPage(), s)),
        GoRoute(
            path: '/rent-payments',
            pageBuilder: (c, s) => _fade(const RentPaymentPage(), s)),
        GoRoute(
            path: '/my-tenant',
            pageBuilder: (c, s) => _fade(const MyTenantPage(), s)),
        GoRoute(
            path: '/manage-tenants',
            // My Tenant's "Past tenants" row deep-links straight to the
            // history tab: context.push('/manage-tenants', extra: {'tab':'past'}).
            pageBuilder: (c, s) {
              final extra = s.extra as Map?;
              return _fade(
                ManageTenantsPage(
                    initialTab: extra?['tab']?.toString() ?? 'add'),
                s,
              );
            }),
        GoRoute(
            path: '/tenant-profile',
            pageBuilder: (c, s) => _fade(const TenantProfilePage(), s)),
        GoRoute(
            path: '/payment-history',
            pageBuilder: (c, s) => _fade(const PaymentHistoryPage(), s)),
        GoRoute(
            path: '/tenant-history',
            pageBuilder: (c, s) => _fade(const TenantHistoryPage(), s)),
        GoRoute(
            path: '/notifications',
            pageBuilder: (c, s) => _fade(const NotificationCenterPage(), s)),
        // ── Amenities ─────────────────────────────────────────
        // Reachable from the member home shell, and from the QR deep link
        // applisociety://amenities/checkin?t=<token>, which lands on /amenities/scan.
        GoRoute(
            path: '/amenities',
            pageBuilder: (c, s) => _fade(const AmenitiesPage(), s)),
        GoRoute(
            path: '/amenities/scan',
            pageBuilder: (c, s) => _fade(const AmenityQrScanPage(), s)),
        GoRoute(
            path: '/amenities/attendance',
            pageBuilder: (c, s) => _fade(const MyAttendancePage(), s)),
        GoRoute(
            path: '/amenities/events',
            pageBuilder: (c, s) => _fade(const AmenityEventsPage(), s)),
        // Kept last: a literal path above would otherwise be swallowed by :id.
        GoRoute(
            path: '/amenities/:id',
            pageBuilder: (c, s) => _fade(
                AmenityDetailPage(amenityId: s.pathParameters['id'] ?? ''), s)),
        // The services/contacts directory - ambulance, fire, society office,
        // electricity, plumber. Linked from BOTH the owner profile and the
        // tenant profile; it existed in neither before.
        GoRoute(
            path: '/essential-contacts',
            pageBuilder: (c, s) => _fade(const EssentialContactsPage(), s)),
        // Commercial (shops and offices inside the society). Additive routes
        // only: no existing path changes, and nothing here is reachable unless
        // /auth/me returns the matching capability, so an older server simply
        // never surfaces an entry point to them.
        GoRoute(
            path: '/commercial',
            pageBuilder: (c, s) => _fade(const CommercialDirectoryPage(), s)),
        GoRoute(
            path: '/commercial/business/:id',
            pageBuilder: (c, s) => _fade(
                BusinessDetailPage(businessId: s.pathParameters['id'] ?? ''), s)),
        GoRoute(
            path: '/commercial/me',
            pageBuilder: (c, s) => _fade(const MyBusinessPage(), s)),
        GoRoute(
            path: '/commercial/me/edit',
            pageBuilder: (c, s) => _fade(const BusinessProfileEditPage(), s)),
        GoRoute(
            path: '/profile/basic-details',
            pageBuilder: (c, s) {
              final extra = s.extra as Map<String, dynamic>?;
              return _fade(
                  BasicDetailsPage(
                    member: extra?['member'] as Map?,
                    flatNo: extra?['flatNo'] as String?,
                    wing: extra?['wing'] as String?,
                    email: extra?['email'] as String?,
                    canEdit: extra?['canEdit'] == true,
                    parkingSlots:
                        (extra?['parkingSlots'] as List?)?.cast<Map>() ??
                            const <Map>[],
                    familyMembers:
                        (extra?['familyMembers'] as List?)?.cast<Map>() ??
                            const <Map>[],
                  ),
                  s);
            }),
        GoRoute(
            path: '/profile/flat-details',
            pageBuilder: (c, s) {
              final extra = s.extra as Map<String, dynamic>?;
              return _fade(
                  FlatDetailsPage(
                    member: extra?['member'] as Map?,
                    flatNo: extra?['flatNo'] as String?,
                    wing: extra?['wing'] as String?,
                  ),
                  s);
            }),
        // '/profile/contact' removed as a standalone destination. It was a whole
        // route whose only content was the phone/email that Basic details
        // already shows in its Contact tab, so for most users tapping it opened
        // an empty screen.
        //
        // Do NOT delete lib/features/member/profile/contact_page.dart: the
        // ContactPage widget is still embedded as the Contact tab inside
        // basic_details_page.dart. Only the duplicate top-level route is gone.
        GoRoute(
            path: '/profile/parking',
            pageBuilder: (c, s) {
              final extra = s.extra as Map<String, dynamic>?;
              return _fade(
                  ParkingPage(
                      slots: (extra?['slots'] as List?)?.cast<Map>() ??
                          const <Map>[]),
                  s);
            }),
        GoRoute(
            path: '/profile/family-members',
            pageBuilder: (c, s) {
              final extra = s.extra as Map<String, dynamic>?;
              return _fade(
                  FamilyMembersPage(
                    members: (extra?['members'] as List?)?.cast<Map>() ??
                        const <Map>[],
                    canEdit: extra?['canEdit'] == true,
                  ),
                  s);
            }),
        GoRoute(
            path: '/profile/emergency-contact',
            pageBuilder: (c, s) {
              final extra = s.extra as Map<String, dynamic>?;
              return _fade(
                  EmergencyContactPage(
                    member: extra?['member'] as Map?,
                    canEdit: extra?['canEdit'] == true,
                  ),
                  s);
            }),
      ],
    );
CustomTransitionPage _fade(Widget child, GoRouterState s) =>
    CustomTransitionPage(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (c, anim, sec, ch) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: ch,
        ),
      ),
    );