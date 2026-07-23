import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/async_view.dart';
import '../../core/socket/socket_bus.dart';
import 'pulse/pulse.dart';
import 'pulse/bill_detail_sheet.dart';

// Was rounding to whole rupees and using plain 3-digit grouping - silently
// showing ₹212.50 as ₹213 and losing Indian lakh/crore grouping. Matches the
// web app's Number(n).toLocaleString("en-IN", { minimumFractionDigits: 2,
// maximumFractionDigits: 2 }) exactly (web/app must render the same paisa
// amounts identically - see 2026-07-19 billing-display investigation).
final _inrFormat =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
String inr(num n) => _inrFormat.format(n.abs());
// The backend now always sends `periodLabel` (see
// apps/mobile-backend/src/lib/periodLabel.ts) — this is the single place
// every bill-title display in the app should read from, instead of each
// call site doing its own `bill['title'] ?? bill['period']` chain, which
// rendered the literal string "null" whenever both were absent.
String billTitle(Map bill) =>
    '${bill['periodLabel'] ?? bill['title'] ?? bill['period'] ?? 'Bill'}';
// A bill that's Partial but past its due date is still overdue — the old
// early-return on `status == 'Partial'` masked this, so a bill with even ₹1
// paid would silently stop counting/flagging as Overdue no matter how many
// months late it was.
String effectiveStatus(Map b) {
  final status = '${b['displayStatus'] ?? b['status'] ?? 'Unpaid'}';
  if (status == 'Paid') return status;
  // A fully-settled bill (nothing left to pay) is Paid even if the stored
  // `status` field wasn't flipped to 'Paid' by the backend — it must never be
  // shown as Overdue/red just because its due date is in the past. This is the
  // cause of the July bill showing "12d overdue" in red: amountPaid already
  // covered totalAmount but status was still 'Unpaid'/'Partial', so the
  // due-date check below wrongly returned 'Overdue'.
  final amount = (b['totalAmount'] as num?) ?? 0;
  final paid = (b['amountPaid'] as num?) ?? 0;
  if (amount > 0 && paid >= amount - 0.005) return 'Paid';
  final due = DateTime.tryParse('${b['dueDate']}');
  if (due != null && due.isBefore(DateTime.now())) return 'Overdue';
  return status;
}

/// Bills tab — port of ui_kits/member-v2 `ScreensBills.jsx` `BillsScreen`:
/// 2-up stat cards, 4-way segmented filter (All/Overdue/Partial/Paid), 2-up
/// thumbnail-card grid. Filter uses the real `BILL_STATUS` values, not the
/// design fixture's.
class BillsPage extends StatefulWidget {
  const BillsPage({super.key});
  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  final _listKey = GlobalKey<AsyncViewState<List>>();
  String _filter = 'All';
  int? _fyStartYear;
  @override
  void initState() {
    super.initState();
    SocketBus.billEvents.addListener(_reload);
  }

  @override
  void dispose() {
    SocketBus.billEvents.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _listKey.currentState?.reload();
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final dio = context.read<Dio>();
    return SafeArea(
      bottom: false,
      child: AsyncView<List>(
        key: _listKey,
        fetch: () async => (await dio.get('/bills')).data['bills'] as List,
        cacheKey: '/bills',
        builder: (context, rawBills) {
          // Server sorts by createdAt (import/generation order), not by bill
          // period - a bill created out of period order (e.g. bulk-imported
          // later) would otherwise land in the wrong spot in the grid.
          final allBills = List.of(rawBills)
            ..sort((a, b) {
              final ay = (a as Map)['billYear'] as int? ?? 0;
              final am = a['billMonth'] as int? ?? 0;
              final by = (b as Map)['billYear'] as int? ?? 0;
              final bm = b['billMonth'] as int? ?? 0;
              if (ay != by) return by.compareTo(ay);
              return bm.compareTo(am);
            });
          // FY = Apr(month idx 3) .. Mar. A bill's FY start year is its billYear
          // unless it's Jan-Mar (billMonth < 3), which belongs to the FY that
          // started the previous calendar year.
          int fyOf(Map b) {
            final y = (b['billYear'] as int?) ?? 0;
            final m = (b['billMonth'] as int?) ?? 0;
            return m >= 3 ? y : y - 1;
          }

          final availableFys =
              allBills.map((raw) => fyOf(raw as Map)).toSet().toList()..sort();
          final now = DateTime.now();
          final currentFy = now.month >= 4 ? now.year : now.year - 1;
          if (_fyStartYear != null && !availableFys.contains(_fyStartYear)) {
            _fyStartYear = null;
          }
          final fyStartYear = _fyStartYear ??
              (availableFys.contains(currentFy)
                  ? currentFy
                  : (availableFys.isNotEmpty ? availableFys.last : currentFy));
          final fyLabel = 'FY ${fyStartYear % 100}-${(fyStartYear + 1) % 100}';
          final fyBills =
              allBills.where((raw) => fyOf(raw as Map) == fyStartYear).toList();
          num outstanding = 0, totalPaid = 0;
          final counts = <String, int>{'Overdue': 0, 'Partial': 0, 'Paid': 0};
          for (final raw in fyBills) {
            final b = raw as Map;
            final amount = (b['totalAmount'] as num?) ?? 0;
            final paid = (b['amountPaid'] as num?) ?? 0;
            if (b['status'] != 'Paid') {
              outstanding += (amount - paid);
            } else {
              totalPaid += paid;
            }
            final st = effectiveStatus(b);
            if (counts.containsKey(st)) counts[st] = counts[st]! + 1;
          }
          final bills = fyBills.where((raw) {
            if (_filter == 'All') return true;
            return effectiveStatus(raw as Map) == _filter;
          }).toList();
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: PulseTopBar(
                  title: 'My Bills',
                  subtitle: 'Maintenance bills for your flat',
                  trailing: availableFys.length > 1
                      ? [
                          PopupMenuButton<int>(
                            initialValue: fyStartYear,
                            onSelected: (y) => setState(() => _fyStartYear = y),
                            itemBuilder: (_) => availableFys.reversed
                                .map((y) => PopupMenuItem(
                                    value: y,
                                    child:
                                        Text('FY ${y % 100}-${(y + 1) % 100}')))
                                .toList(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                  color: t.surface,
                                  border: Border.all(color: t.border),
                                  borderRadius: BorderRadius.circular(999)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(fyLabel,
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: t.fg1)),
                                  const SizedBox(width: 4),
                                  Icon(Icons.expand_more_rounded,
                                      size: 16, color: t.fg3),
                                ],
                              ),
                            ),
                          )
                        ]
                      : const [],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: _AccentStat(
                                  label: 'Outstanding',
                                  value: outstanding,
                                  accent: t.danger)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _AccentStat(
                                  label: 'Total paid ($fyLabel)',
                                  value: totalPaid,
                                  accent: t.success)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      PulseSegmented<String>(
                        value: _filter,
                        onChanged: (v) => setState(() => _filter = v),
                        options: [
                          PulseSegmentedOption(
                              value: 'All',
                              label: 'All',
                              count: fyBills.length),
                          PulseSegmentedOption(
                              value: 'Overdue',
                              label: 'Overdue',
                              count: counts['Overdue']),
                          PulseSegmentedOption(
                              value: 'Partial',
                              label: 'Partial',
                              count: counts['Partial']),
                          PulseSegmentedOption(
                              value: 'Paid',
                              label: 'Paid',
                              count: counts['Paid']),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
              if (bills.isEmpty)
                SliverToBoxAdapter(
                    child: PulseEmptyState(
                        illo: PulseIllo.noData,
                        title: 'No bills in "$_filter"'))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final textScale =
                          MediaQuery.textScalerOf(context).scale(1);
                      final oneColumn =
                          constraints.crossAxisExtent < 340 || textScale > 1.15;
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: oneColumn ? 1 : 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          // The previous 0.98 aspect ratio made the card only
                          // ~140-165 px tall on older/narrow phones, while its
                          // content needs over 200 px at normal font scale.
                          mainAxisExtent: oneColumn ? 224 : 236,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _BillThumbCard(
                            bill: bills[i] as Map,
                            onTap: () async {
                              final changed = await showBillDetailSheet(
                                  context, bills[i] as Map);
                              if (changed == true) _reload();
                            },
                          ),
                          childCount: bills.length,
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AccentStat extends StatelessWidget {
  final String label;
  final num value;
  final Color accent;
  const _AccentStat(
      {required this.label, required this.value, required this.accent});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(PulseTokens.radius),
        boxShadow: t.shadowCard,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
                width: 4,
                decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(PulseTokens.radius)))),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            color: t.fg4,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(inr(value),
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: t.fg1)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillThumbCard extends StatelessWidget {
  final Map bill;
  final VoidCallback onTap;
  const _BillThumbCard({required this.bill, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final status = effectiveStatus(bill);
    final amount = (bill['totalAmount'] as num?) ?? 0;
    final paid = (bill['amountPaid'] as num?) ?? 0;
    final balance = amount - paid;
    final due = DateTime.tryParse('${bill['dueDate']}');
    final overdue = status == 'Overdue';
    final overdueDays =
        overdue && due != null ? DateTime.now().difference(due).inDays : 0;
    final tone = switch (status) {
      'Paid' => PulseTone.paid,
      'Partial' => PulseTone.partial,
      'Overdue' => PulseTone.overdue,
      _ => PulseTone.unpaid
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(
              color: overdue ? t.danger.withValues(alpha: 0.45) : t.border,
              width: overdue ? 1.4 : 1),
          borderRadius: BorderRadius.circular(PulseTokens.radius),
          boxShadow: t.shadowCard,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: overdue
                      ? [t.danger, const Color(0xFFB4271C)]
                      : [t.brand2, t.brand],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(billTitle(bill),
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(inr(amount),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800)),
                  // `amount` is totalAmount/totalBillDue (this month's charge
                  // + any carried-over balance + interest), not just this
                  // month's charge - label it so it isn't mistaken for the
                  // "Current Bill" figure shown separately on the web admin
                  // table, which is a smaller number for the same bill.
                  Text('Total due',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PulsePill(label: status, tone: tone, small: true),
                    const SizedBox(height: 8),
                    Text(
                      overdue
                          ? '⚠ ${overdueDays}d overdue'
                          : (balance > 0
                              ? (due != null
                                  ? 'Due ${due.day}/${due.month}/${due.year}'
                                  : 'Balance ${inr(balance)}')
                              : 'Paid in full'),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: overdue ? FontWeight.w800 : FontWeight.w600,
                        color: overdue
                            ? t.danger
                            : (balance > 0 ? t.fg3 : t.success),
                      ),
                    ),
                    if (balance > 0) ...[
                      const SizedBox(height: 4),
                      Text('Balance ${inr(balance)}',
                          style: TextStyle(
                              fontSize: 11,
                              color: t.fg4,
                              fontWeight: FontWeight.w600)),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        Icon(Icons.remove_red_eye_outlined,
                            size: 15, color: t.fg4),
                        const SizedBox(width: 10),
                        Icon(Icons.download_outlined, size: 15, color: t.fg4),
                        const SizedBox(width: 10),
                        Icon(Icons.ios_share_rounded, size: 14, color: t.fg4),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}