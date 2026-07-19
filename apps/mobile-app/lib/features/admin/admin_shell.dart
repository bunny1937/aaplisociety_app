import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_x.dart';
import '../../core/theme/haptics.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/press_effect.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/socket/socket_bus.dart';
import '../auth/bloc/auth_bloc.dart';

class _Stats {
  final int members;
  final int openComplaints;
  final int visitorsToday;
  final int collectedPct;
  const _Stats(this.members, this.openComplaints, this.visitorsToday, this.collectedPct);
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final _statsKey = GlobalKey<AsyncViewState<_Stats>>();

  @override
  void initState() {
    super.initState();
    SocketBus.visitorEvents.addListener(_reload);
    SocketBus.billEvents.addListener(_reload);
  }

  @override
  void dispose() {
    SocketBus.visitorEvents.removeListener(_reload);
    SocketBus.billEvents.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _statsKey.currentState?.reload();

  Future<_Stats> _load(Dio dio) async {
    final results = await Future.wait([dio.get('/auth/members'), dio.get('/complaints'), dio.get('/visitors'), dio.get('/bills')]);
    final members = (results[0].data as List).length;
    final complaints = (results[1].data as List);
    final visitors = (results[2].data as List);
    final bills = (results[3].data as List);
    final openComplaints = complaints.where((c) => c['status'] == 'Open' || c['status'] == 'In progress').length;
    final today = DateTime.now();
    final visitorsToday = visitors.where((v) {
      final d = DateTime.tryParse('${v['createdAt']}');
      return d != null && d.year == today.year && d.month == today.month && d.day == today.day;
    }).length;
    num total = 0, paid = 0;
    for (final b in bills) {
      total += (b['amount'] as num);
      paid += (b['amountPaid'] as num? ?? 0);
    }
    final collectedPct = total > 0 ? ((paid / total) * 100).round() : 0;
    return _Stats(members, openComplaints, visitorsToday, collectedPct);
  }

  @override
  Widget build(BuildContext context) {
    final dio = context.read<Dio>();
    final auth = context.watch<AuthBloc>().state;
    final activeProfile = auth is AuthAuthed
        ? ((auth.user['profiles'] as List?) ?? const []).cast<Map?>().firstWhere(
              (p) => p != null && '${p['_id']}' == '${auth.claims['activeProfileId']}',
              orElse: () => null,
            )
        : null;
    final societyName = activeProfile?['societyName']?.toString() ?? 'Admin console';

    return Scaffold(
      body: SafeArea(
        child: AsyncView<_Stats>(
          key: _statsKey,
          fetch: () => _load(dio),
          builder: (context, s) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Admin console', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                          Text(societyName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: context.headline)),
                        ],
                      ),
                    ),
                    PressEffect(
                      onTap: () { Haptics.heavy(); context.read<AuthBloc>().add(LogoutRequested()); context.go('/login'); },
                      child: const Icon(Icons.logout, color: AppColors.textMuted),
                    ),
                  ],
                ).animate().fadeIn(duration: 350.ms).slideX(begin: -0.1),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 1.15,
                  children: [
                    StatCard(index: 0, icon: Icons.groups, label: 'Members', value: '${s.members}', color: AppColors.blue),
                    StatCard(index: 1, icon: Icons.currency_rupee, label: 'Collected', value: '${s.collectedPct}%', color: const Color(0xFF00B894)),
                    StatCard(index: 2, icon: Icons.report_problem, label: 'Open complaints', value: '${s.openComplaints}', color: const Color(0xFFE17055), onTap: () { Haptics.light(); context.push('/complaints'); }),
                    StatCard(index: 3, icon: Icons.people_alt, label: 'Visitors today', value: '${s.visitorsToday}', color: const Color(0xFF6C5CE7)),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Quick actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.headline)),
                const SizedBox(height: 14),
                _action(context, Icons.campaign, 'Post a notice', 'Announce to the whole society', () => _postNotice(context, dio)),
                _action(context, Icons.receipt_long, 'Generate bill', 'Raise maintenance for a member', () => _generateBill(context, dio)),
                _action(context, Icons.fact_check, 'Manage complaints', 'Review and resolve tickets', () { Haptics.light(); context.push('/complaints'); }),
                _action(context, Icons.notifications_outlined, 'Notifications', 'Society-wide alerts and SOS', () { Haptics.light(); context.push('/notifications'); }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(BuildContext context, IconData icon, String title, String sub, VoidCallback onTap) {
    return PressEffect(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: AppColors.blue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: context.headline)),
                  Text(sub, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.08);
  }

  void _postNotice(BuildContext context, Dio dio) {
    Haptics.light();
    final title = TextEditingController();
    final description = TextEditingController();
    String type = 'custom';
    String priority = 'medium';
    _sheet(context, 'Post a notice', [
      DropdownButtonFormField<String>(
        initialValue: type,
        items: const [
          DropdownMenuItem(value: 'maintenance', child: Text('Maintenance')),
          DropdownMenuItem(value: 'meeting', child: Text('Meeting')),
          DropdownMenuItem(value: 'water', child: Text('Water')),
          DropdownMenuItem(value: 'electricity', child: Text('Electricity')),
          DropdownMenuItem(value: 'parking', child: Text('Parking')),
          DropdownMenuItem(value: 'security', child: Text('Security')),
          DropdownMenuItem(value: 'event', child: Text('Event')),
          DropdownMenuItem(value: 'billing', child: Text('Billing')),
          DropdownMenuItem(value: 'custom', child: Text('Custom')),
        ],
        onChanged: (v) => type = v ?? type,
        decoration: const InputDecoration(labelText: 'Type'),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: priority,
        items: const [
          DropdownMenuItem(value: 'low', child: Text('Low')),
          DropdownMenuItem(value: 'medium', child: Text('Medium')),
          DropdownMenuItem(value: 'high', child: Text('High')),
          DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
        ],
        onChanged: (v) => priority = v ?? priority,
        decoration: const InputDecoration(labelText: 'Priority'),
      ),
      const SizedBox(height: 12),
      TextField(controller: title, decoration: const InputDecoration(hintText: 'Title (at least 10 characters)')),
      const SizedBox(height: 12),
      TextField(controller: description, maxLines: 3, decoration: const InputDecoration(hintText: 'Message (at least 30 characters)')),
    ], 'Publish', () async {
      if (title.text.trim().length < 10) return 'Title must be at least 10 characters';
      if (description.text.trim().length < 30) return 'Message must be at least 30 characters';
      await dio.post('/notices', data: {
        'type': type,
        'priority': priority,
        'title': title.text.trim(),
        'description': description.text.trim(),
      });
      return null;
    });
  }

  void _generateBill(BuildContext context, Dio dio) {
    Haptics.light();
    final flat = TextEditingController();
    final amount = TextEditingController();
    _sheet(context, 'Generate bill', [
      TextField(controller: flat, decoration: const InputDecoration(hintText: 'Flat number, e.g. A-1203')),
      const SizedBox(height: 12),
      TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Amount (Rs)')),
    ], 'Generate', () async {
      final amt = num.tryParse(amount.text.trim());
      if (flat.text.trim().isEmpty || amt == null || amt <= 0) return 'Enter a valid flat number and amount';
      final members = (await dio.get('/auth/members')).data as List;
      final match = members.cast<Map?>().firstWhere(
            (m) => '${m?['flatNo']}'.toLowerCase() == flat.text.trim().toLowerCase(),
            orElse: () => null,
          );
      if (match == null) return 'No member found for flat ${flat.text.trim()}';
      final now = DateTime.now();
      final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      await dio.post('/bills', data: {
        'memberId': match['memberId'],
        'period': period,
        'title': 'Maintenance - $period',
        'amount': amt,
      });
      return null;
    });
  }

  void _sheet(BuildContext context, String title, List<Widget> fields, String cta, Future<String?> Function() onSubmit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetCtx) {
        bool submitting = false;
        String? error;
        return StatefulBuilder(
          builder: (sheetCtx, setState) => Padding(
            padding: EdgeInsets.fromLTRB(22, 18, 22, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 18),
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.headline)),
                const SizedBox(height: 18),
                ...fields,
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                PrimaryButton(
                  label: cta,
                  loading: submitting,
                  onPressed: () async {
                    setState(() { submitting = true; error = null; });
                    try {
                      final validationError = await onSubmit();
                      if (validationError != null) {
                        Haptics.heavy();
                        setState(() { submitting = false; error = validationError; });
                        return;
                      }
                      Haptics.success();
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      _statsKey.currentState?.reload();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title done')));
                      }
                    } on DioException catch (err) {
                      Haptics.heavy();
                      setState(() { submitting = false; error = apiErrorMessage(err); });
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
