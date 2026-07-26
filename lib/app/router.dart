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
import '../features/member/profile/contact_page.dart';
import '../features/member/profile/parking_page.dart';
import '../features/member/profile/family_members_page.dart';
import '../features/member/profile/emergency_contact_page.dart';
import '../features/member/profile/basic_details_page.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (c, s) => const SplashPage()),
        GoRoute(
            path: '/login', pageBuilder: (c, s) => _fade(const LoginPage(), s)),
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
        GoRoute(
            path: '/profile/contact',
            pageBuilder: (c, s) {
              final extra = s.extra as Map<String, dynamic>?;
              return _fade(
                  ContactPage(
                    member: extra?['member'] as Map?,
                    email: extra?['email'] as String?,
                    canEdit: extra?['canEdit'] == true,
                  ),
                  s);
            }),
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
