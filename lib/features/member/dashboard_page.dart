import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart' show GoRouterHelper;
import 'package:dio/dio.dart';
import '../../core/widgets/async_view.dart';
import '../../core/socket/socket_bus.dart';
import '../../core/theme/haptics.dart';
import '../auth/bloc/auth_bloc.dart';
import 'pulse/pulse.dart';
import 'pulse/notice_emoji.dart';
import 'pulse/member_display.dart';
import 'member_shell.dart';
import 'bills_page.dart' show effectiveStatus, billTitle, inr;
import '../notifications/recent_notifications_popover.dart';
import 'widgets/flat_switcher_avatar.dart';

class _DashData {
  final List bills;
  final List visitors;
  final List complaints;
  final List notices;

  /// Rent payments for the logged-in flat. Tenants see their rent ledger here
  /// instead of the owner's maintenance bill, so the dashboard needs it too.
  final List rents;

  /// Personal notifications. Distinct from `notices`: a notice is a society-wide
  /// announcement, a notification is something that happened to YOU (rent
  /// reminder, visitor at the gate, payment confirmed). The bell badge was
  /// counting urgent NOTICES, which is why a rent reminder never made it blink.
  final List notifications;

  const _DashData(this.bills, this.visitors, this.complaints, this.notices,
      this.rents, this.notifications);
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
    // Rent is fetched separately and tolerantly: owners of self-occupied flats
    // have no rent records, and a failure here must never blank the dashboard.
    List rents = const [];
    try {
      final res = await dio.get('/rent-payments');
      final body = res.data;
      rents = (body is Map
              ? (body['payments'] ?? body['rentPayments'] ?? body['items'])
              : body) as List? ??
          const [];
    } catch (_) {
      rents = const [];
    }
    // Same tolerance as rents: the bell should degrade to "no badge" rather
    // than take the whole dashboard down with it.
    List notifications = const [];
    try {
      final res = await dio.get('/notifications');
      final body = res.data;
      notifications =
          (body is Map ? body['notifications'] : body) as List? ?? const [];
    } catch (_) {
      notifications = const [];
    }
    return _DashData(
      results[0].data['bills'] as List,
      results[1].data['visitors'] as List,
      results[2].data['complaints'] as List,
      results[3].data['notices'] as List,
      rents,
      notifications,
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
        : 'Flat ${formatFlatLabel(activeProfile['wing']?.toString(), activeProfile['flatNo']?.toString())}${societyName != null ? ' · $societyName' : ''}';
    return SafeArea(
      bottom: false,
      child: AsyncView<_DashData>(
        key: _key,
        fetch: () => _load(dio),
        builder: (context, data) {
          // Server sorts bills by createdAt (import/generation order), not by
          // bill period - sort here so the hero card picks the actually-current
          // bill instead of whichever happened to be created/imported last.
          final bills = List.of(data.bills)
            ..sort((a, b) {
              final ay = (a as Map)['billYear'] as int? ?? 0;
              final am = a['billMonth'] as int? ?? 0;
              final by = (b as Map)['billYear'] as int? ?? 0;
              final bm = b['billMonth'] as int? ?? 0;
              if (ay != by) return by.compareTo(ay);
              return bm.compareTo(am);
            });
          num outstanding = 0;
          num paidThisYear = 0;
          final now = DateTime.now();
          final fyStartYear = now.month >= 4 ? now.year : now.year - 1;
          Map? currentBill;
          for (final raw in bills) {
            final b = raw as Map;
            final amount = (b['totalAmount'] as num?) ?? 0;
            final paid = (b['amountPaid'] as num?) ?? 0;
            if (b['status'] != 'Paid') {
              outstanding += (amount - paid);
              currentBill ??= b;
            }
            // Count what was actually paid regardless of status — a
            // Partial bill still has real money paid against it this year.
            final billYear = b['billYear'] as int?;
            final billMonth = b['billMonth'] as int?;
            final inFinancialYear = billYear != null &&
                billMonth != null &&
                ((billYear == fyStartYear && billMonth >= 3) ||
                    (billYear == fyStartYear + 1 && billMonth < 3));
            if (inFinancialYear) paidThisYear += paid;
          }
          currentBill ??= bills.isNotEmpty ? bills.first as Map : null;
          final pendingVisitors = data.visitors
              .where((v) => (v as Map)['status'] == 'Pending')
              .toList();
          // The bell badge now counts UNREAD NOTIFICATIONS, not urgent notices.
          final unreadNotifications =
              data.notifications.where((n) => (n as Map)['read'] != true).length;
          final sortedNotices = [...data.notices]..sort((a, b) {
              final da = DateTime.tryParse('${(a as Map)['createdAt']}') ??
                  DateTime(2000);
              final db = DateTime.tryParse('${(b as Map)['createdAt']}') ??
                  DateTime(2000);
              return db.compareTo(da);
            });
          final latestNotices = sortedNotices.take(2).toList();
          // A tenant does not owe maintenance - the flat's owner does. So the
          // whole money column of this screen switches to rent for tenants.
          final isTenant = claims['occupancyType'] == 'Tenant';
          num rentPaidTotal = 0;
          num rentPending = 0;
          Map? lastRent;
          for (final raw in data.rents) {
            final r = raw as Map;
            final amt = (r['amount'] as num?) ?? 0;
            final st = '${r['status'] ?? 'Confirmed'}';
            if (st == 'Confirmed') {
              rentPaidTotal += amt;
            } else if (st == 'Pending') {
              rentPending += amt;
            }
            lastRent ??= r;
          }
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
FlatSwitcherAvatar(
  dio: context.read<AuthBloc>().dio,
  size: 44,
),                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hi, $firstName 👋',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: t.fg1,
                                  letterSpacing: -0.3)),
                          if (flatSub != null)
                            Text(flatSub,
                                style: TextStyle(fontSize: 12.5, color: t.fg4),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    // The bell used to open the NOTICES sheet, which is a
                    // different feature entirely: notices are society-wide
                    // announcements, notifications are things that happened to
                    // YOU. That is why a rent reminder had nowhere to appear on
                    // the home screen. It now floats the three most recent
                    // notifications inline - no page transition - with a link
                    // through to the full list.
                    PulseIconButton(
                      icon: Icons.notifications_outlined,
                      badge: unreadNotifications,
                      onTap: () => showRecentNotificationsPopover(
                          context, context.read<Dio>()),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (isTenant)
                  _HeroRentCard(
                      lastRent: lastRent,
                      pendingAmount: rentPending,
                      paidTotal: rentPaidTotal)
                else if (currentBill != null)
                  _HeroBillCard(bill: currentBill),
                if (pendingVisitors.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _NeedsAttentionCard(visitor: pendingVisitors.first as Map),
                ],
                const SizedBox(height: 20),
                _QuickActions(isTenant: isTenant),
                const SizedBox(height: 24),
                Text('Account snapshot',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: t.fg1)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: _SnapshotCard(
                            label: isTenant
                                ? 'Rent awaiting confirmation'
                                : 'Total outstanding',
                            value: isTenant ? rentPending : outstanding,
                            tone: (isTenant ? rentPending : outstanding) > 0
                                ? t.danger
                                : t.success)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _SnapshotCard(
                            label: isTenant
                                ? 'Rent paid to owner'
                                : 'Paid (FY ${fyStartYear % 100}-${(fyStartYear + 1) % 100})',
                            value: isTenant ? rentPaidTotal : paidThisYear,
                            tone: t.success)),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Latest notices',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: t.fg1)),
                    GestureDetector(
                      onTap: () => memberTabNotifier.value = 2,
                      child: Text('See all',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: t.brand)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (latestNotices.isEmpty)
                  Text('No notices yet.',
                      style: TextStyle(fontSize: 12.5, color: t.fg4))
                else
                  ...latestNotices
                      .map((raw) => _NoticePreview(notice: raw as Map)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroBillCard extends StatelessWidget {
  final Map bill;
  const _HeroBillCard({required this.bill});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final status = effectiveStatus(bill);
    final overdue = status == 'Overdue';
    final amount = (bill['totalAmount'] as num?) ?? 0;
    final paid = (bill['amountPaid'] as num?) ?? 0;
    final due = amount - paid;
    final pct =
        amount > 0 ? (paid / amount * 100).clamp(0, 100).toDouble() : 0.0;
    final dueDate = bill['dueDate'] != null
        ? DateTime.tryParse('${bill['dueDate']}')
        : null;
    final overdueDays = overdue && dueDate != null
        ? DateTime.now().difference(dueDate).inDays
        : 0;
    final period = billTitle(bill);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: overdue
              ? [const Color(0xFFB4271C), t.danger, const Color(0xFFE0392C)]
              : [t.brand2, t.brand, t.accent],
        ),
        boxShadow: t.shadowPop,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08))),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (overdue)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_rounded,
                          color: Colors.white, size: 13),
                      const SizedBox(width: 5),
                      Text('OVERDUE · $overdueDays DAYS LATE',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4)),
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
                        Text('$period · Maintenance',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3)),
                        const SizedBox(height: 6),
                        Text(inr(due > 0 ? due : amount),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 4),
                        Text(
                          due > 0
                              ? (overdue && dueDate != null
                                  ? 'was due ${dueDate.day} ${_month(dueDate.month)} — pay now'
                                  : (dueDate != null
                                      ? 'due ${dueDate.day} ${_month(dueDate.month)}'
                                      : 'due soon'))
                              : 'Paid in full',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700),
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
                      child: Text('${pct.round()}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                    )
                  else
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.16),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.55),
                            width: 2),
                      ),
                      child: const Icon(Icons.priority_high_rounded,
                          color: Colors.white, size: 30),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  // "Pay now" only makes sense when something's actually due —
                  // this card falls back to the member's most recent bill even
                  // when it's fully paid (see DashboardPage's currentBill ??=
                  // fallback), and previously showed "Pay now" unconditionally,
                  // contradicting the "Paid in full" text right above it.
                  if (due > 0) ...[
                    Expanded(
                      child: PulseButton(
                        label: overdue ? 'Pay now — overdue' : 'Pay now',
                        variant: PulseBtnVariant.secondary,
                        onTap: () => memberTabNotifier.value = 1,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
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

  String _month(int m) => const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][m - 1];
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.person_add_alt_1_rounded,
                color: t.warning, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Someone's at the gate",
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: t.fg1)),
                Text(
                    '${visitor['name'] ?? 'Visitor'} · ${visitor['purpose'] ?? '—'} · needs your approval',
                    style: TextStyle(fontSize: 12, color: t.fg3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
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
  const _QuickActions({required this.isTenant});
  final bool isTenant;
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final actions = [
      // Owners land on the payment history (what was paid, when, how) rather
      // than the bills tab. Tenants land on their rent payments.
      (
        Icons.wallet_rounded,
        isTenant ? 'Rent' : 'Payments',
        t.brand,
        () => context.push(isTenant ? '/rent-payments' : '/payment-history')
      ),
      (
        Icons.receipt_long_rounded,
        'Ledger',
        t.accent,
        () => context.push('/ledger')
      ),
      (
        Icons.report_problem_rounded,
        'Complain',
        t.warning,
        () => context.push('/complaints')
      ),
      (
        Icons.person_add_alt_1_rounded,
        'Visitors',
        t.success,
        () => memberTabNotifier.value = 3
      ),
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
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(11)),
                      child: Icon(icon, color: color, size: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: t.fg2)),
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
  const _SnapshotCard(
      {required this.label, required this.value, required this.tone});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return PulseCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: t.fg4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(inr(value),
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: tone)),
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
    final urgent =
        notice['priority'] == 'urgent' || notice['priority'] == 'high';
    final createdAt = DateTime.tryParse('${notice['createdAt']}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => memberTabNotifier.value = 2,
        child: PulseCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                  emojiForNoticeType(
                      '${notice['tag'] ?? notice['type'] ?? ''}'),
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${notice['title'] ?? ''}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: t.fg1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (createdAt != null)
                      Text(
                          '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                          style: TextStyle(fontSize: 11, color: t.fg4)),
                  ],
                ),
              ),
              if (urgent)
                const PulsePill(
                    label: 'Urgent', tone: PulseTone.overdue, small: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tenant counterpart of [_HeroBillCard]. A tenant owes rent to the owner, not
/// maintenance to the society, so this shows the rent position instead.
class _HeroRentCard extends StatelessWidget {
  const _HeroRentCard({
    required this.lastRent,
    required this.pendingAmount,
    required this.paidTotal,
  });
  final Map? lastRent;
  final num pendingAmount;
  final num paidTotal;

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final r = lastRent;
    final status = r == null ? null : '${r['status'] ?? 'Confirmed'}';
    final awaiting = status == 'Pending';
    final month = r?['month']?.toString();
    final amount = (r?['amount'] as num?) ?? 0;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        context.push('/rent-payments');
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [t.brand, t.brand2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(PulseTokens.radius),
          boxShadow: t.shadowPop,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.home_work_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  r == null
                      ? 'Rent'
                      : 'Rent${month != null ? ' · $month' : ''}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (r != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      awaiting ? 'Awaiting owner' : '$status',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              r == null ? '—' : inr(amount),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8),
            ),
            const SizedBox(height: 4),
            Text(
              r == null
                  ? 'No rent payment recorded yet. Tap to submit one.'
                  : awaiting
                      ? 'Submitted. Your owner has to confirm it.'
                      : 'Last rent payment recorded.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88), fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _RentStat(label: 'Paid so far', value: inr(paidTotal)),
                const SizedBox(width: 20),
                _RentStat(
                    label: 'Awaiting confirmation', value: inr(pendingAmount)),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
              ),
              child: Text(
                'Record a rent payment',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: t.brand, fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RentStat extends StatelessWidget {
  const _RentStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800)),
      ],
    );
  }
}
