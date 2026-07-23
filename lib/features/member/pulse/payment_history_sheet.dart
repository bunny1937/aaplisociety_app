import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../core/widgets/async_view.dart';
import '../bills_page.dart' show inr;
import 'pulse.dart';

Future<void> showPaymentHistorySheet(BuildContext context, Dio dio) =>
    showPulseSheet<void>(
      context,
      title: 'Payment history',
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * .68,
        child: AsyncView<List>(
          fetch: () async {
            final data = (await dio.get('/ledger')).data;
            final txns = (data['transactions'] as List?) ?? const [];
            return txns.where((e) {
              final m = e as Map;
              return m['category'] == 'Payment' || m['type'] == 'Credit';
            }).toList();
          },
          cacheKey: '/ledger?payments=1',
          builder: (context, payments) => payments.isEmpty
              ? const PulseEmptyState(
                  illo: PulseIllo.noData, title: 'No payments yet')
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: payments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) =>
                      _PaymentHistoryCard(payment: payments[i] as Map),
                ),
        ),
      ),
    );

class _PaymentHistoryCard extends StatelessWidget {
  final Map payment;
  const _PaymentHistoryCard({required this.payment});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final p = payment;
    final amount = (p['amount'] as num?) ?? 0;
    final date = DateTime.tryParse('${p['date']}');
    final b = (p['paymentBreakdown'] as Map?) ?? const {};
    final rows = <(String, String)>[
      if (p['paymentMode'] != null) ('Mode', '${p['paymentMode']}'),
      if (p['billPeriodId'] != null) ('Bill period', '${p['billPeriodId']}'),
      if (b['interestCleared'] != null)
        ('Interest cleared', inr((b['interestCleared'] as num?) ?? 0)),
      if (b['principalCleared'] != null)
        ('Principal cleared', inr((b['principalCleared'] as num?) ?? 0)),
      if (b['advanceCredit'] != null)
        ('Advance credit', inr((b['advanceCredit'] as num?) ?? 0)),
      if (p['balanceAfterTransaction'] != null)
        ('Balance after', inr((p['balanceAfterTransaction'] as num?) ?? 0)),
      if (p['transactionId'] != null)
        ('Transaction ID', '${p['transactionId']}'),
    ];
    return PulseCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.check_circle_rounded, color: t.success),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('${p['description'] ?? 'Payment received'}',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, color: t.fg1)),
                if (date != null)
                  Text('${date.day}/${date.month}/${date.year}',
                      style: TextStyle(fontSize: 11.5, color: t.fg4)),
              ])),
          Text(inr(amount),
              style: TextStyle(fontWeight: FontWeight.w800, color: t.success)),
        ]),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...rows.map((r) => Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(r.$1, style: TextStyle(fontSize: 12, color: t.fg4)),
                  Flexible(
                      child: Text(r.$2,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.fg2)))
                ],
              ))),
        ],
      ]),
    );
  }
}
