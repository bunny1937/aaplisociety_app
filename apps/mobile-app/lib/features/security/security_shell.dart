import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_x.dart';
import '../../core/theme/haptics.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ledger_shimmer.dart';
import '../../core/widgets/visitor_card.dart';
import '../../core/widgets/press_effect.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/socket/socket_bus.dart';
import '../auth/bloc/auth_bloc.dart';

class SecurityShell extends StatefulWidget {
  const SecurityShell({super.key});
  @override
  State<SecurityShell> createState() => _SecurityShellState();
}

class _SecurityShellState extends State<SecurityShell> {
  final _listKey = GlobalKey<AsyncViewState<List>>();

  @override
  void initState() {
    super.initState();
    SocketBus.visitorEvents.addListener(_onEvent);
  }

  @override
  void dispose() {
    SocketBus.visitorEvents.removeListener(_onEvent);
    super.dispose();
  }

  void _onEvent() => _listKey.currentState?.reload();

  Future<void> _act(Dio dio, String id, String action) async {
    Haptics.medium();
    try {
      await dio.post('/visitors/$id/$action');
      if (!mounted) return;
      Haptics.success();
      await _listKey.currentState?.reload();
    } on DioException catch (err) {
      if (!mounted) return;
      Haptics.heavy();
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dio = context.read<Dio>();
    return Scaffold(
      backgroundColor: context.isDark ? AppColors.ink : AppColors.paper,
      body: SafeArea(
        child: AsyncView<List>(
          key: _listKey,
          fetch: () async => (await dio.get('/visitors')).data as List,
          loadingBuilder: (_) => const LedgerListSkeleton(),
          builder: (context, all) {
            final pending = all.where((v) => v['status'] == 'Pending').toList();
            final approved = all.where((v) => v['status'] == 'Approved').toList();
            final inside = all.where((v) => v['status'] == 'Entered').toList();
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.brass.withValues(alpha: 0.5), width: 1.2),
                      ),
                      child: const Icon(Icons.shield_rounded, color: AppColors.brass),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Gate security', style: GoogleFonts.fraunces(fontSize: 20, fontWeight: FontWeight.w600, color: context.headline)),
                          Text('Visitor gate log', style: GoogleFonts.manrope(color: AppColors.inkMuted)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Log out',
                      icon: const Icon(Icons.logout_rounded, color: AppColors.inkMuted),
                      onPressed: () { Haptics.heavy(); context.read<AuthBloc>().add(LogoutRequested()); context.go('/login'); },
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: PressEffect(
                      onTap: () {
                        Haptics.light();
                        showAppToast(context, 'Gate pass scanning is coming soon', kind: AppToastKind.info);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: context.surface.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.inkMuted.withValues(alpha: 0.3), width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.qr_code_scanner_rounded, color: AppColors.inkMuted, size: 26),
                            const SizedBox(width: 14),
                            Expanded(child: Text('Scan visitor gate pass', style: GoogleFonts.manrope(color: context.headline, fontSize: 15, fontWeight: FontWeight.w600))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: AppColors.brass.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                              child: Text('Coming soon', style: GoogleFonts.manrope(fontSize: 11, color: AppColors.brass, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.15),
                _section(context, 'Awaiting member approval', "The resident hasn't responded yet", pending, null, null),
                _section(context, 'Approved — let them in', null, approved, 'Admit', (id) => _act(dio, id, 'enter')),
                _section(context, 'Inside now', null, inside, 'Exit', (id) => _act(dio, id, 'exit')),
                if (all.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 50),
                    child: Center(child: Text('All clear — nobody waiting.', style: GoogleFonts.manrope(color: AppColors.inkMuted))),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String? subtitle, List items, String? actionLabel, void Function(String id)? onAction) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.fraunces(fontWeight: FontWeight.w600, fontSize: 17, color: context.headline)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.manrope(color: AppColors.inkMuted, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          ...items.asMap().entries.map((e) {
            final v = e.value as Map;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LedgerVisitorCard(
                index: e.key,
                name: '${v['name']}',
                subtitle: '${v['purpose'] ?? ''} · ${v['phone'] ?? ''}',
                actions: actionLabel == null || onAction == null ? null : SizedBox(
                  width: double.infinity,
                  child: PressEffect(
                    onTap: () => onAction(v['_id'] as String),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: AppColors.stampGreen.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                      child: Text(actionLabel, style: GoogleFonts.manrope(color: AppColors.stampGreen, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
