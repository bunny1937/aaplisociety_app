import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/haptics.dart';
import '../../core/widgets/press_effect.dart';
import '../../core/widgets/app_toast.dart';
import 'bloc/auth_bloc.dart';

class ProfileSelectPage extends StatelessWidget {
  const ProfileSelectPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.paper,
        title: Text('Choose your home',
            style: GoogleFonts.fraunces(
                fontWeight: FontWeight.w600, color: AppColors.paper)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.ink, Color(0xFF0E1A44), AppColors.inkRaised],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
          BlocConsumer<AuthBloc, AuthState>(
            listener: (context, state) {
              if (state is AuthError) {
                Haptics.heavy();
                showAppToast(context, state.message, kind: AppToastKind.alert);
              } else if (state is AuthAuthed) {
                Haptics.success();
                if (state.mustChangePassword) {
                  context.go('/change-password',
                      extra: {'forced': true, 'role': state.role});
                } else {
                  context.go(homeRouteForRole(state.role));
                }
              }
            },
            builder: (context, state) {
              final profiles =
                  state is AuthNeedsProfile ? state.profiles : const [];
              final loading = state is AuthLoading;
              return Stack(
                children: [
                  ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 110, 20, 20),
                    itemCount: profiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final p = profiles[i] as Map;
                      return PressEffect(
                        onTap: loading
                            ? () {}
                            : () {
                                Haptics.medium();
                                context.read<AuthBloc>().add(
                                    SwitchProfileRequested(
                                        p['profileId'] as String));
                              },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    width: 1),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor:
                                        AppColors.brass.withValues(alpha: 0.22),
                                    child: const Icon(Icons.home_rounded,
                                        color: AppColors.brassBright),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('${p['societyName']}',
                                            style: GoogleFonts.manrope(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                                color: AppColors.paper)),
                                        Text('Flat ${p['flatNo']}',
                                            style: GoogleFonts.manrope(
                                                color: AppColors.inkMuted)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded,
                                      color: AppColors.brassBright),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ).animate(delay: (80 * i).ms).fadeIn().slideX(begin: 0.2);
                    },
                  ),
                  if (loading)
                    const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.brassBright)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
