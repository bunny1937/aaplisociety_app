import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../core/widgets/async_view.dart';
import '../auth/bloc/auth_bloc.dart';
import 'pulse/pulse.dart';
import 'bills_page.dart' show inr;

/// Ledger tab.
///
/// This page used to render three fields per row (title, date, amount) for
/// everybody, which told an owner nothing about HOW a payment was applied and
/// showed a tenant a maintenance ledger they are not even liable for.
///
/// It is now role-aware:
///  * Owner  -> full transaction ledger with allocation (interest / principal /
///              advance), payment mode, reference number and running balance.
///  * Tenant -> their rent ledger: what they paid the owner, when, by which
///              mode, and whether the owner has confirmed it yet.
class LedgerPage extends StatelessWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dio = context.read<Dio>();
    final auth = context.watch<AuthBloc>().state;
    final claims = auth is AuthAuthed ? auth.claims : const <String, dynamic>{};
    final isTenant = claims['occupancyType'] == 'Tenant';

    // P0 crash fix: this page is pushed as a route from /ledger, but returned
    // a bare SafeArea + Column with no Scaffold or Material ancestor. Every
    // Text below then fell back to Flutter's _kErrorTextStyle, which is why
    // the whole screen rendered as monospace with yellow double underlines.
    // A Scaffold supplies both the Material ancestor and the themed canvas.
    return Scaffold(
      backgroundColor: context.pulse.canvas,
      body: SafeArea(
        child: Column(
          children: [
            PulseTopBar(
              title: isTenant ? 'Rent Ledger' : 'My Ledger',
              subtitle: isTenant
                  ? 'Every rent payment you recorded'
                  : 'Bills, payments, interest & adjustments',
            ),
            Expanded(
            child: AsyncView<List>(
              cacheKey: isTenant ? '/rent-payments' : '/ledger',
              fetch: () async {
                if (isTenant) {
                  final body = (await dio.get('/rent-payments')).data;
                  return (body is Map
                          ? (body['payments'] ??
                              body['rentPayments'] ??
                              body['items'])
                          : body) as List? ??
                      const [];
                }
                return (await dio.get('/ledger')).data['transactions'] as List;
              },
              builder: (context, entries) => isTenant
                    ? _RentLedger(entries: entries)
                    : _OwnerLedger(entries: entries),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

String _fmtDate(dynamic raw) {
  final d = DateTime.tryParse('$raw');
  if (d == null) return '\u2014';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv({required this.k, required this.v});
  final String k;
  final String v;
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(k, style: TextStyle(fontSize: 11.5, color: t.fg4)),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                  fontSize: 11.5, color: t.fg2, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.items});
  final List<(String, String, Color)> items;
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(PulseTokens.radius),
        border: Border.all(color: t.hairline),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Container(width: 1, height: 30, color: t.hairline),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(items[i].$1,
                        style: TextStyle(fontSize: 11, color: t.fg4)),
                    const SizedBox(height: 3),
                    Text(
                      items[i].$2,
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: items[i].$3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Owner ledger
// ---------------------------------------------------------------------------

class _OwnerLedger extends StatelessWidget {
  const _OwnerLedger({required this.entries});
  final List entries;

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    if (entries.isEmpty) {
      return const PulseEmptyState(
        illo: PulseIllo.noData,
        title: 'No ledger entries yet',
      );
    }

    num debits = 0;
    num credits = 0;
    for (final raw in entries) {
      final e = raw as Map;
      final amt = (e['amount'] as num?) ?? 0;
      if (e['type'] == 'Credit') {
        credits += amt;
      } else {
        debits += amt;
      }
    }
    final balance =
        (entries.first as Map)['balanceAfterTransaction'] as num? ?? 0;

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _SummaryBar(items: [
          ('Billed', inr(debits), t.fg1),
          ('Paid', inr(credits), t.success),
          ('Balance', inr(balance), balance > 0 ? t.danger : t.success),
        ]),
        for (final raw in entries) _OwnerRow(e: raw as Map),
      ],
    );
  }
}

class _OwnerRow extends StatelessWidget {
  const _OwnerRow({required this.e});
  final Map e;

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final isCredit = e['type'] == 'Credit';
    final reversed = e['isReversed'] == true;
    final amount = (e['amount'] as num?) ?? 0;
    final breakdown = (e['paymentBreakdown'] as Map?) ?? const {};
    final interest = (breakdown['interestCleared'] as num?) ?? 0;
    final principal = (breakdown['principalCleared'] as num?) ?? 0;
    final advance = (breakdown['advanceCredit'] as num?) ?? 0;
    final mode = e['paymentMode']?.toString();
    final ref = (e['transactionRef'] ?? e['chequeNo'])?.toString();

    return Opacity(
      opacity: reversed ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(PulseTokens.radius),
          border: Border.all(color: t.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${e['description'] ?? e['category'] ?? 'Transaction'}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: t.fg1),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_fmtDate(e['date'])}  \u00b7  ${e['transactionId'] ?? ''}',
                        style: TextStyle(fontSize: 11.5, color: t.fg4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isCredit ? '-' : '+'}${inr(amount)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: isCredit ? t.success : t.fg1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _Chip(
                      text: reversed
                          ? 'REVERSED'
                          : (isCredit ? 'PAYMENT' : 'CHARGE'),
                      bg: reversed
                          ? t.dangerSoft
                          : (isCredit ? t.successSoft : t.warningSoft),
                      fg: reversed
                          ? t.danger
                          : (isCredit ? t.success : t.warning),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: t.hairline, height: 1),
            const SizedBox(height: 6),
            if (e['category'] != null)
              _Kv(k: 'Category', v: '${e['category']}'),
            if (e['billPeriodId'] != null)
              _Kv(k: 'Bill period', v: '${e['billPeriodId']}'),
            if (mode != null && mode.isNotEmpty)
              _Kv(k: 'Mode', v: mode),
            if (ref != null && ref.isNotEmpty) _Kv(k: 'Reference', v: ref),
            if (isCredit && (interest > 0 || principal > 0 || advance > 0)) ...[
              const SizedBox(height: 6),
              Text('How this payment was applied',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: t.fg3)),
              _Kv(k: 'Interest cleared', v: inr(interest)),
              _Kv(k: 'Principal cleared', v: inr(principal)),
              if (advance > 0)
                _Kv(k: 'Kept as advance', v: inr(advance)),
            ],
            _Kv(
              k: 'Balance after',
              v: inr((e['balanceAfterTransaction'] as num?) ?? 0),
            ),
            if ('${e['notes'] ?? ''}'.isNotEmpty)
              _Kv(k: 'Notes', v: '${e['notes']}'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tenant rent ledger
// ---------------------------------------------------------------------------

class _RentLedger extends StatelessWidget {
  const _RentLedger({required this.entries});
  final List entries;

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    if (entries.isEmpty) {
      return const PulseEmptyState(
        illo: PulseIllo.noData,
        title: 'No rent payments recorded yet',
      );
    }

    num confirmed = 0;
    num pending = 0;
    num rejected = 0;
    for (final raw in entries) {
      final r = raw as Map;
      final amt = (r['amount'] as num?) ?? 0;
      switch ('${r['status'] ?? 'Confirmed'}') {
        case 'Pending':
          pending += amt;
          break;
        case 'Rejected':
          rejected += amt;
          break;
        default:
          confirmed += amt;
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _SummaryBar(items: [
          ('Confirmed', inr(confirmed), t.success),
          ('Awaiting owner', inr(pending), t.warning),
          ('Rejected', inr(rejected), rejected > 0 ? t.danger : t.fg3),
        ]),
        for (final raw in entries) _RentRow(r: raw as Map),
      ],
    );
  }
}

class _RentRow extends StatelessWidget {
  const _RentRow({required this.r});
  final Map r;

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final status = '${r['status'] ?? 'Confirmed'}';
    final (Color bg, Color fg) = switch (status) {
      'Pending' => (t.warningSoft, t.warning),
      'Rejected' => (t.dangerSoft, t.danger),
      _ => (t.successSoft, t.success),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(PulseTokens.radius),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rent \u00b7 ${r['month'] ?? _fmtDate(r['paidAt'])}',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: t.fg1),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Paid on ${_fmtDate(r['paidAt'] ?? r['createdAt'])}',
                      style: TextStyle(fontSize: 11.5, color: t.fg4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    inr((r['amount'] as num?) ?? 0),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: t.fg1),
                  ),
                  const SizedBox(height: 4),
                  _Chip(
                    text: status == 'Pending'
                        ? 'AWAITING OWNER'
                        : status.toUpperCase(),
                    bg: bg,
                    fg: fg,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: t.hairline, height: 1),
          const SizedBox(height: 6),
          if (r['paymentMode'] != null)
            _Kv(k: 'Mode', v: '${r['paymentMode']}'),
          if ('${r['reference'] ?? ''}'.isNotEmpty)
            _Kv(k: 'Reference', v: '${r['reference']}'),
          if (r['submittedByRole'] != null)
            _Kv(k: 'Recorded by', v: '${r['submittedByRole']}'),
          if (r['confirmedAt'] != null)
            _Kv(k: 'Confirmed on', v: _fmtDate(r['confirmedAt'])),
          if ('${r['rejectionReason'] ?? ''}'.isNotEmpty)
            _Kv(k: 'Rejection reason', v: '${r['rejectionReason']}'),
          if ('${r['notes'] ?? ''}'.isNotEmpty)
            _Kv(k: 'Notes', v: '${r['notes']}'),
        ],
      ),
    );
  }
}
