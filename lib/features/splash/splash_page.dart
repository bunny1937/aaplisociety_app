import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/permissions/permission_onboarding.dart';
import '../../core/remote_config/app_gate.dart';
import '../../core/storage/token_store.dart';
import '../../core/storage/offline_cache.dart';
import '../../core/storage/offline_outbox.dart';
import '../../core/theme/app_colors.dart';
import '../auth/bloc/auth_bloc.dart';

// App Launch -> animated intro -> Remote Config gate -> route by session.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String? _blocker;
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // Firebase.initializeApp() already ran (and was awaited) in main() before
    // runApp - safe to touch FirebaseMessaging here. showNotificationOnboardingIfNeeded
    // no-ops instantly (no dialog) once already shown, so this is cheap on
    // every subsequent launch, not just the first.
    final token = await TokenStore().access;
    if (mounted) await showNotificationOnboardingIfNeeded(context);
    // Android can kill a background process on a low-RAM/OEM-aggressive
    // device. Do not replay the full branding delay when a session survives.
    if (token == null) {
      await Future.delayed(const Duration(milliseconds: 900));
    }
    try {
      final gate = await AppGate.evaluate('1.0.0');
      if (gate.forceUpdate) {
        setState(
            () => _blocker = 'Please update to the latest version to continue');
        return;
      }
      if (gate.maintenance) {
        setState(() => _blocker = 'We are under maintenance - back shortly');
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    if (token == null) {
      context.go('/login');
      return;
    }
    try {
      final me = await context.read<Dio>().get('/auth/me');
      final claims = Map<String, dynamic>.from(me.data['claims']);
      final role = claims['role'] as String;
      if (!mounted) return;
      final user = Map<String, dynamic>.from(me.data['user']);
      if (me.data['member'] != null) user['member'] = me.data['member'];
      if (me.data['society'] != null) user['society'] = me.data['society'];
      context.read<AuthBloc>().add(SessionRestored(role, user, claims));
      final staff =
          role == 'Admin' || role == 'Secretary' || role == 'Accountant';
      context.go(
          staff ? '/admin' : (role == 'Security' ? '/security' : '/member'));
    } on DioException catch (err) {
      if (err.response?.statusCode == 401) {
        await TokenStore().clear();
        await OfflineCache.clear();
        await OfflineOutbox.clear();
      }
      if (mounted) {
        context.go(
            '/login'); // network-down: token stays, next launch retries restore
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: Center(
          child: _blocker != null
              ? Padding(
                  padding: const EdgeInsets.all(36),
                  child: Text(_blocker!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.4)),
                ).animate().fadeIn()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 100,
                      width: 100,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30)),
                      child: const Icon(Icons.apartment_rounded,
                          size: 54, color: AppColors.navy),
                    )
                        .animate()
                        .scale(duration: 600.ms, curve: Curves.easeOutBack)
                        .then()
                        .shimmer(duration: 1100.ms, color: AppColors.blue),
                    const SizedBox(height: 24),
                    const Text('Aapli Society',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 27,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3))
                        .animate()
                        .fadeIn(delay: 300.ms)
                        .slideY(begin: 0.3, curve: Curves.easeOut),
                    const SizedBox(height: 8),
                    const Text('Your society, simplified',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 14))
                        .animate()
                        .fadeIn(delay: 600.ms),
                    const SizedBox(height: 40),
                    const SizedBox(
                      height: 26,
                      width: 26,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white54),
                    ).animate().fadeIn(delay: 800.ms),
                  ],
                ),
        ),
      ),
    );
  }
}
