import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/splash/splash_page.dart';
import '../features/auth/login_page.dart';
import '../features/auth/profile_select_page.dart';
import '../features/member/member_shell.dart';
import '../features/member/bills_page.dart';
import '../features/member/ledger_page.dart';
import '../features/member/receipts_page.dart';
import '../features/complaints/complaints_page.dart';
import '../features/security/security_shell.dart';
import '../features/admin/admin_shell.dart';
import '../features/auth/change_password_page.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (c, s) => const SplashPage()),
        GoRoute(path: '/login', pageBuilder: (c, s) => _fade(const LoginPage(), s)),
        GoRoute(path: '/select-profile', builder: (c, s) => const ProfileSelectPage()),
        GoRoute(path: '/member', pageBuilder: (c, s) => _fade(const MemberShell(), s)),
        GoRoute(path: '/security', pageBuilder: (c, s) => _fade(const SecurityShell(), s)),
        GoRoute(path: '/admin', pageBuilder: (c, s) => _fade(const AdminShell(), s)),
        GoRoute(path: '/change-password', pageBuilder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return _fade(ChangePasswordPage(
            forced: extra?['forced'] == true,
            roleForRedirect: extra?['role'] as String?,
          ), s);
        }),
        GoRoute(path: '/bills', pageBuilder: (c, s) => _fade(
          Scaffold(appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0), body: const BillsPage()), s)),
        GoRoute(path: '/complaints', pageBuilder: (c, s) => _fade(const ComplaintsPage(), s)),
        GoRoute(path: '/ledger', pageBuilder: (c, s) => _fade(const LedgerPage(), s)),
        GoRoute(path: '/receipts', pageBuilder: (c, s) => _fade(const ReceiptsPage(), s)),
      ],
    );

CustomTransitionPage _fade(Widget child, GoRouterState s) => CustomTransitionPage(
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
