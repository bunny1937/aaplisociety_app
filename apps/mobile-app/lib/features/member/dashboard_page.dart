import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart' show GoRouterHelper;
import 'package:dio/dio.dart';
import '../../core/widgets/async_view.dart';
import '../../core/socket/socket_bus.dart';
import '../auth/bloc/auth_bloc.dart';
import 'pulse/pulse.dart';
import 'pulse/notice_emoji.dart';
import 'pulse/member_display.dart';
import 'member_shell.dart';
import 'bills_page.dart' show effectiveStatus, billTitle;

class _DashData {
  final List bills;
  final List visitors;
  final List complaints;
  final List notices;
  const _DashData(this.bills, this.visitors, this.complaints, this.notices);
}

/// Home tab — port of ui_kits/member-v2 `MemberV2ScreensDashboard.jsx`
/// `DashboardScreen`: avatar+ring header, gradient hero with progress ring,
/// conditional "needs attention" gate card, 4-up quick actions, 2-up account
/// snapshot, latest-notices preview. Real data via existing `/bills`,
/// `/visitors`, `/complaints`, `/notices` endpoints (same calls the previous
/// dashboard made) — only the layout/visual language changed.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _key = GlobalKey<AsyncViewState<_DashData>>();

  @override
  void initState() {
    super.initState();
    SocketBus.visitorEvents.addListener(_reload);
    SocketBus.billEvents.addListener(_reload);
    SocketBus.noticeEvents.addListener(_reload);
  }

  @override
  void dispose() {
    SocketBus.visitorEvents.removeListener(_reload);
    SocketBus.billEvents.removeListener(_reload);
    SocketBus.noticeEvents.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _key.currentState?.reload();

  Future<_DashData> _load(Dio dio) async {
    final results = await Future.wait([
      dio.get('/bills'),
      dio.get('/visitors'),
      dio.get('/complaints'),
      dio.get('/notices'),
    ]);
    return _DashData(
      results[0].data as List,
      results[1].data as List,
      results[2].data as List,
      results[3].data as List,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final dio = context.read<Dio>();
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthed ? auth.user : const <String, dynamic>{};
    final claims = auth is AuthAuthed ? auth.claims : const <String, dynamic>{};
    final displayName = resolveDisplayName(user);
    final firstName = displayName.split(RegExp(r'\s+')).first;
    final profiles = (user['profiles'] as List?) ?? const [];
    final activeProfile = profiles.cast<Map?>().firstWhere(
          (p) => p != null && '${p['_id']}' == '${claims['activeProfileId']}',
          orElse: () => profiles.isNotEmpty ? profiles.first as Map : null,
        );
    final societyName = resolveSocietyName(user, activeProfile);
    final flatSub = activeProfile == null
        ? null
        : 'Flat ${activeProfile['wing'] ?? ''}${activeProfile['wing'] != null && activeProfile['wing'] != '' ? '-' : ''}${activeProfile['flatNo'] ?? ''}${societyName != null ? ' · $societyName' : ''}';

    return SafeArea(
      bottom: false,
      child: AsyncView<_DashData>(
        key: _key,
        fetch: () => _load(dio),
        builder: (context, data) {
          num outstanding = 0;
          num paidThisYear = 0;
          Map? currentBill;
          for (final raw in data.bills) {
            final b = raw as Map;
            final amount = (b['amount'] as num?) ?? 0;
            final paid = (b['amountPaid'] as num?) ?? 0;
            if (b['status'] != 'Paid') {
              outstanding += (amount - paid);
              currentBill ??= b;
            } else {
              paidThisYear += paid;
            }
          }
          currentBill ??= data.bills.isNotEmpty ? data.bills.first as Map : null;

          final pendingVisitors = data.visitors.where((v) => (v as Map)['status'] == 'Pending').toList();
          final urgentNotices = data.notices.where((n) {
            final p = (n as Map)['priority'];
            return p == 'urgent' || p == 'high';
          }).length;
          final sortedNotices = [...data.notices]..sort((a, b) {
              final da = DateTime.tryParse('${(a as Map)['createdAt']}') ?? DateTime(2000);
              final db = DateTime.tryParse('${(b as Map)['createdAt']}') ?? DateTime(2000);
              return db.compareTo(da);
            });
          final latestNotices = sortedNotices.take(2).toList();

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PulseAvatar(name: displayName, size: 44, ring: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hi, $firstName 👋', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.fg1, letterSpacing: -0.3)),
                          if (flatSub != null)
                            Text(flatSub, style: TextStyle(fontSize: 12.5, color: t.fg4), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    PulseIconButton(
                      icon: Icons.notifications_outlined,
                      badge: urgentNotices,
                      onTap: () => memberTabNotifier.value = 2,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (currentBill != null) _HeroBillCard(bill: currentBill),
                if (pendingVisitors.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _NeedsAttentionCard(visitor: pendingVisitors.first as Map),
                ],
                const SizedBox(height: 20),
                _QuickActions(),
                const SizedBox(height: 24),
                Text('Account snapshot', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: t.fg1)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _SnapshotCard(label: 'Total outstanding', value: outstanding, tone: outstanding > 0 ? t.danger : t.success)),
                    const SizedBox(width: 12),
                    Expanded(child: _SnapshotCard(label: 'Paid this year', value: paidThisYear, tone: t.success)),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Latest notices', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: t.fg1)),
                    GestureDetector(
                      onTap: () => memberTabNotifier.value = 2,
                      child: Text('See all', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.brand)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (latestNotices.isEmpty)
                  Text('No notices yet.', style: TextStyle(fontSize: 12.5, color: t.fg4))
                else
                  ...latestNotices.map((raw) => _NoticePreview(notice: raw as Map)),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _inr(num n) => '₹${n.abs().round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+\d$)'), (m) => '${m[1]},')}';

class _HeroBillCard extends StatelessWidget {
  final Map bill;
  const _HeroBillCard({required this.bill});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final status = effectiveStatus(bill);
    final overdue = status == 'Overdue';
    final amount = (bill['amount'] as num?) ?? 0;
    final paid = (bill['amountPaid'] as num?) ?? 0;
    final due = amount - paid;
    final pct = amount > 0 ? (paid / amount * 100).clamp(0, 100).toDouble() : 0.0;
    final dueDate = bill['dueDate'] != null ? DateTime.tryParse('${bill['dueDate']}') : null;
    final overdueDays = overdue && dueDate != null ? DateTime.now().difference(dueDate).inDays : 0;
    final period = billTitle(bill);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: overdue ? [const Color(0xFFB4271C), t.danger, const Color(0xFFE0392C)] : [t.brand2, t.brand, t.accent],
        ),
        boxShadow: t.shadowPop,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30, right: -30,
            child: Container(width: 120, height: 120, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.08))),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (overdue)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_rounded, color: Colors.white, size: 13),
                      const SizedBox(width: 5),
                      Text('OVERDUE · $overdueDays DAYS LATE', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$period · Maintenance', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                        const SizedBox(height: 6),
                        Text(_inr(due > 0 ? due : amount), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        const SizedBox(height: 4),
                        Text(
                          due > 0
                              ? (overdue && dueDate != null
                                  ? 'was due ${dueDate.day} ${_month(dueDate.month)} — pay now'
                                  : (dueDate != null ? 'due ${dueDate.day} ${_month(dueDate.month)}' : 'due soon'))
                              : 'Paid in full',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  if (!overdue)
                    PulseProgressRing(
                      pct: pct,
                      size: 64,
                      stroke: 7,
                      color: Colors.white,
                      child: Text('${pct.round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    )
                  else
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 2),
                      ),
                      child: const Icon(Icons.priority_high_rounded, color: Colors.white, size: 30),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: PulseButton(
                      label: overdue ? 'Pay now — overdue' : 'Pay now',
                      variant: PulseBtnVariant.secondary,
                      onTap: () => memberTabNotifier.value = 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PulseButton(
                      label: 'View bill',
                      variant: PulseBtnVariant.ghost,
                      onTap: () => memberTabNotifier.value = 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _month(int m) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];
}

class _NeedsAttentionCard extends StatelessWidget {
  final Map visitor;
  const _NeedsAttentionCard({required this.visitor});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return PulseCard(
      onTap: () => memberTabNotifier.value = 3,
      padding: const EdgeInsets.all(14),
      color: t.warningSoft,
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.person_add_alt_1_rounded, color: t.warning, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Someone's at the gate", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: t.fg1)),
                Text('${visitor['name'] ?? 'Visitor'} · ${visitor['purpose'] ?? '—'} · needs your approval', style: TextStyle(fontSize: 12, color: t.fg3), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: t.fg4),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final actions = [
      (Icons.wallet_rounded, 'Pay', t.brand, () => memberTabNotifier.value = 1),
      (Icons.receipt_long_rounded, 'Ledger', t.accent, () => context.push('/ledger')),
      (Icons.report_problem_rounded, 'Complain', t.warning, () => context.push('/complaints')),
      (Icons.person_add_alt_1_rounded, 'Visitors', t.success, () => memberTabNotifier.value = 3),
    ];
    return Row(
      children: actions.map((a) {
        final (icon, label, color, onTap) = a;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: a == actions.last ? 0 : 10),
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                      child: Icon(icon, color: color, size: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.fg2)),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  final String label;
  final num value;
  final Color tone;
  const _SnapshotCard({required this.label, required this.value, required this.tone});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return PulseCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: t.fg4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(_inr(value), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: tone)),
        ],
      ),
    );
  }
}

class _NoticePreview extends StatelessWidget {
  final Map notice;
  const _NoticePreview({required this.notice});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final urgent = notice['priority'] == 'urgent' || notice['priority'] == 'high';
    final createdAt = DateTime.tryParse('${notice['createdAt']}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => memberTabNotifier.value = 2,
        child: PulseCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(emojiForNoticeType('${notice['tag'] ?? notice['type'] ?? ''}'), style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${notice['title'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: t.fg1), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (createdAt != null)
                      Text('${createdAt.day}/${createdAt.month}/${createdAt.year}', style: TextStyle(fontSize: 11, color: t.fg4)),
                  ],
                ),
              ),
              if (urgent) const PulsePill(label: 'Urgent', tone: PulseTone.overdue, small: true),
            ],
          ),
        ),
      ),
    );
  }
}
