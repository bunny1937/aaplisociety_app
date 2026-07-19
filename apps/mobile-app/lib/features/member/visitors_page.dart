import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/haptics.dart';
import '../../core/widgets/async_view.dart';
import '../../core/socket/socket_bus.dart';
import 'pulse/pulse.dart';
import 'pulse/visitor_pass_card.dart';

/// Visitors tab — port of ui_kits/member-v2 `ScreensVisitorsProfile.jsx`
/// `VisitorsScreen`: 3-tier layout (at-the-gate-now / all-clear / today's
/// log), merged from the previous `visitors_page.dart` (pre-register form)
/// + `visitor_history_page.dart` (approve/deny history). Design's screen is
/// reactive/gate-triggered only with no pre-register form — per user
/// decision, the real pre-register feature is kept, moved into a "+" FAB
/// sheet instead of the old inline composer. The design's "offline confirm"
/// tier has no backing field on the real Visitor model (see
/// MEMBER_V2_GAPS.md) so it's omitted rather than faked.
class VisitorsPage extends StatefulWidget {
  const VisitorsPage({super.key});
  @override
  State<VisitorsPage> createState() => _VisitorsPageState();
}

class _VisitorsPageState extends State<VisitorsPage> {
  final _listKey = GlobalKey<AsyncViewState<List>>();

  @override
  void initState() {
    super.initState();
    SocketBus.visitorEvents.addListener(_reload);
  }

  @override
  void dispose() {
    SocketBus.visitorEvents.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _listKey.currentState?.reload();

  Future<void> _decide(BuildContext context, String id, String decision) async {
    Haptics.medium();
    try {
      await context.read<Dio>().post('/visitors/$id/decision', data: {'decision': decision});
      Haptics.success();
      _reload();
    } on DioException catch (err) {
      Haptics.heavy();
      if (context.mounted) showPulseToast(context, apiErrorMessage(err, 'Could not update visitor'), kind: PulseToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final dio = context.read<Dio>();
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          AsyncView<List>(
            key: _listKey,
            fetch: () async => (await dio.get('/visitors')).data as List,
            cacheKey: '/visitors',
            builder: (context, all) {
              final pending = all.where((v) => (v as Map)['status'] == 'Pending').toList();
              final today = all.where((v) {
                final d = DateTime.tryParse('${(v as Map)['createdAt']}');
                final now = DateTime.now();
                return d != null && d.year == now.year && d.month == now.month && d.day == now.day;
              }).toList();

              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: PulseTopBar(title: 'Visitors', subtitle: 'Gate approvals & today\'s log')),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Text('At the gate now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: t.fg1)),
                    ),
                  ),
                  if (pending.isEmpty)
                    const SliverToBoxAdapter(child: PulseEmptyState(illo: PulseIllo.allClear, title: 'All clear', subtitle: 'No one is waiting at the gate'))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      sliver: SliverList.separated(
                        itemCount: pending.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _GateCard(visitor: pending[i] as Map, onDecide: (d) => _decide(context, '${(pending[i] as Map)['_id']}', d)),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Text("Today's visitors", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: t.fg1)),
                    ),
                  ),
                  if (today.isEmpty)
                    const SliverToBoxAdapter(child: PulseEmptyState(illo: PulseIllo.noData, title: 'No visitors logged today'))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      sliver: SliverList.separated(
                        itemCount: today.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _TodayRow(visitor: today[i] as Map),
                      ),
                    ),
                ],
              );
            },
          ),
          Positioned(
            right: 20, bottom: 20,
            child: FloatingActionButton(
              backgroundColor: t.brand,
              onPressed: () => _openFabChooser(context),
              child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFabChooser(BuildContext context) async {
    Haptics.select();
    await showPulseSheet<void>(
      context,
      title: 'Add a visitor',
      builder: (sheetCtx) {
        final t = sheetCtx.pulse;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChooserOption(
              icon: Icons.qr_code_2_rounded,
              title: 'Generate a gate pass',
              subtitle: 'For an expected visitor — get a code to share in advance. The guard admits them directly, no approval needed at the gate.',
              color: t.brand,
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _openGeneratePass(context);
              },
            ),
            const SizedBox(height: 12),
            _ChooserOption(
              icon: Icons.person_add_alt_1_rounded,
              title: 'Register a walk-in guest',
              subtitle: "For someone arriving now — sends a request you'll need to approve or deny when they reach the gate.",
              color: t.warning,
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _openPreRegister(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _openGeneratePass(BuildContext context) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    var type = 'Guest';
    var validity = const Duration(hours: 4);
    var submitting = false;

    await showPulseSheet<void>(
      context,
      title: 'Generate a gate pass',
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final t = sheetCtx.pulse;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _labeled(t, 'Visitor name', TextField(controller: name, style: TextStyle(color: t.fg1), decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12), prefixIcon: Icon(Icons.person_outline_rounded)))),
              const SizedBox(height: 12),
              _labeled(t, 'Phone number', TextField(controller: phone, keyboardType: TextInputType.phone, maxLength: 10, style: TextStyle(color: t.fg1), decoration: const InputDecoration(border: InputBorder.none, counterText: '', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12), prefixIcon: Icon(Icons.phone_outlined)))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['Guest', 'Delivery', 'Cab', 'Service'].map((ty) {
                  final sel = ty == type;
                  return GestureDetector(
                    onTap: () => setSheet(() => type = ty),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: sel ? t.brandSoft : t.surface, border: Border.all(color: sel ? t.brand : t.border), borderRadius: BorderRadius.circular(999)),
                      child: Text(ty, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: sel ? t.brand : t.fg3)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text('Valid for', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: t.fg3)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  (const Duration(hours: 4), '4 hours'),
                  (const Duration(hours: 12), '12 hours'),
                  (const Duration(days: 1), 'Today'),
                  (const Duration(days: 7), '7 days'),
                ].map((opt) {
                  final sel = opt.$1 == validity;
                  return GestureDetector(
                    onTap: () => setSheet(() => validity = opt.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: sel ? t.brandSoft : t.surface, border: Border.all(color: sel ? t.brand : t.border), borderRadius: BorderRadius.circular(999)),
                      child: Text(opt.$2, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: sel ? t.brand : t.fg3)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              PulseButton(
                label: 'Generate pass',
                icon: Icons.qr_code_2_rounded,
                full: true,
                loading: submitting,
                onTap: () async {
                  final n = name.text.trim(), p = phone.text.trim();
                  if (n.length < 2) { Haptics.heavy(); showPulseToast(sheetCtx, "Enter the visitor's name", kind: PulseToastKind.error); return; }
                  if (!RegExp(r'^[0-9]{10}$').hasMatch(p)) { Haptics.heavy(); showPulseToast(sheetCtx, 'Enter a valid 10-digit phone number', kind: PulseToastKind.error); return; }
                  setSheet(() => submitting = true);
                  final now = DateTime.now();
                  final expires = now.add(validity);
                  try {
                    final res = await sheetCtx.read<Dio>().post('/visitors/pass', data: {
                      'visitorName': n,
                      'visitorPhone': p,
                      'purpose': type,
                      'passType': 'OneTime',
                      'validFrom': now.toUtc().toIso8601String(),
                      'expiresAt': expires.toUtc().toIso8601String(),
                      'maxUses': 1,
                    });
                    Haptics.success();
                    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    if (context.mounted) {
                      await showVisitorPassCard(
                        context,
                        visitorName: n,
                        visitorPhone: p,
                        otp: '${res.data['otp']}',
                        generatedAt: now,
                        expiresAt: expires,
                      );
                    }
                  } on DioException catch (err) {
                    Haptics.heavy();
                    setSheet(() => submitting = false);
                    if (sheetCtx.mounted) showPulseToast(sheetCtx, apiErrorMessage(err, 'Could not generate pass'), kind: PulseToastKind.error);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openPreRegister(BuildContext context) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    var type = 'Guest';
    var submitting = false;

    await showPulseSheet(
      context,
      title: 'Register a walk-in guest',
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final t = sheetCtx.pulse;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This sends a request the guard will hold at the gate until you approve or deny it — for a visitor who\'s already arrived without a pass.', style: TextStyle(fontSize: 11.5, color: t.fg4, height: 1.4)),
              const SizedBox(height: 16),
              _labeled(t, 'Visitor name', TextField(controller: name, style: TextStyle(color: t.fg1), decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12), prefixIcon: Icon(Icons.person_outline_rounded)))),
              const SizedBox(height: 12),
              _labeled(t, 'Phone number', TextField(controller: phone, keyboardType: TextInputType.phone, maxLength: 10, style: TextStyle(color: t.fg1), decoration: const InputDecoration(border: InputBorder.none, counterText: '', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12), prefixIcon: Icon(Icons.phone_outlined)))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['Guest', 'Delivery', 'Cab', 'Service'].map((ty) {
                  final sel = ty == type;
                  return GestureDetector(
                    onTap: () => setSheet(() => type = ty),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: sel ? t.brandSoft : t.surface, border: Border.all(color: sel ? t.brand : t.border), borderRadius: BorderRadius.circular(999)),
                      child: Text(ty, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: sel ? t.brand : t.fg3)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              PulseButton(
                label: 'Send for approval',
                icon: Icons.person_add_alt_1_rounded,
                full: true,
                loading: submitting,
                onTap: () async {
                  final n = name.text.trim(), p = phone.text.trim();
                  if (n.length < 2) { Haptics.heavy(); showPulseToast(sheetCtx, "Enter the visitor's name", kind: PulseToastKind.error); return; }
                  if (!RegExp(r'^[0-9]{10}$').hasMatch(p)) { Haptics.heavy(); showPulseToast(sheetCtx, 'Enter a valid 10-digit phone number', kind: PulseToastKind.error); return; }
                  setSheet(() => submitting = true);
                  try {
                    await sheetCtx.read<Dio>().post('/visitors', data: {'name': n, 'phone': p, 'purpose': type});
                    Haptics.success();
                    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    _reload();
                    if (context.mounted) showPulseToast(context, 'Sent — waiting for your approval when they arrive', kind: PulseToastKind.success);
                  } on DioException catch (err) {
                    Haptics.heavy();
                    setSheet(() => submitting = false);
                    if (sheetCtx.mounted) showPulseToast(sheetCtx, apiErrorMessage(err, 'Could not register visitor'), kind: PulseToastKind.error);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _labeled(PulseTokens t, String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: t.fg3)),
        const SizedBox(height: 6),
        Container(decoration: BoxDecoration(color: t.surface, border: Border.all(color: t.border), borderRadius: BorderRadius.circular(PulseTokens.radiusSm)), child: field),
      ],
    );
  }
}

class _GateCard extends StatelessWidget {
  final Map visitor;
  final ValueChanged<String> onDecide;
  const _GateCard({required this.visitor, required this.onDecide});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return PulseCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: t.warningSoft, borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.person_rounded, color: t.warning, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${visitor['name'] ?? 'Visitor'}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: t.fg1)),
                    Text('${visitor['purpose'] ?? '—'}', style: TextStyle(fontSize: 12, color: t.fg4)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PulseButton(label: 'Deny', variant: PulseBtnVariant.danger, size: PulseBtnSize.sm, onTap: () => onDecide('deny')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PulseButton(label: 'Allow', variant: PulseBtnVariant.success, size: PulseBtnSize.sm, onTap: () => onDecide('approve')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChooserOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ChooserOption({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: t.surface, border: Border.all(color: t.border), borderRadius: BorderRadius.circular(PulseTokens.radius)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: t.fg1)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(fontSize: 11.5, color: t.fg4, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  final Map visitor;
  const _TodayRow({required this.visitor});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final status = '${visitor['status'] ?? ''}';
    final tone = switch (status) { 'Entered' || 'Approved' => PulseTone.entered, 'Exited' => PulseTone.exited, 'Pending' => PulseTone.pending, _ => PulseTone.expired };
    final created = DateTime.tryParse('${visitor['createdAt']}');
    final when = created != null ? '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}' : '';

    return PulseCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${visitor['name'] ?? 'Visitor'}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: t.fg1)),
                Text('$when · ${visitor['purpose'] ?? ''}', style: TextStyle(fontSize: 11.5, color: t.fg4)),
              ],
            ),
          ),
          PulsePill(label: status, tone: tone, small: true),
        ],
      ),
    );
  }
}
