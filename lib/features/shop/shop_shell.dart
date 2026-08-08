// lib/features/shop/shop_shell.dart
//
// Commercial profile landing screen. Deliberately minimal — the shop-context
// login work (spec: docs/superpowers/specs/2026-08-08-shop-context-multi-profile-login-design.md,
// web repo) ships the routing/auth contract; shop-facing billing/directory
// screens are future work, tracked separately. This shell exists so login
// for a Commercial profile has somewhere real to land, the same way
// MemberShell is /member's entry point.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth/bloc/auth_bloc.dart';
import '../../core/theme/haptics.dart';

class ShopShell extends StatelessWidget {
  const ShopShell({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final shop = state is AuthAuthed
            ? state.user['shop'] as Map<String, dynamic>?
            : null;
        final tradeName = shop?['tradeName'] as String? ?? 'Your shop';
        final unitLabel = [shop?['wing'], shop?['shopNo']]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join('-');

        return Scaffold(
          backgroundColor: const Color(0xFF0B1120),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(tradeName,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: Colors.white)),
            actions: [
              IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout_rounded, color: Colors.white70),
                onPressed: () {
                  Haptics.medium();
                  context.read<AuthBloc>().add(LogoutRequested());
                  context.go('/login');
                },
              ),
            ],
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storefront_rounded,
                      size: 56, color: Colors.amber.withValues(alpha: 0.8)),
                  const SizedBox(height: 16),
                  Text(
                    unitLabel.isEmpty ? tradeName : '$unitLabel · $tradeName',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Shop billing and directory management are coming soon.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: Colors.white.withValues(alpha: 0.55)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
