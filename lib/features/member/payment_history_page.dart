import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_error.dart';
import 'bills_page.dart' show inr;

/// Full payment + transaction history. Owners see maintenance payments; tenants
/// see their RENT payments (the API reports which via `viewerRole`), so the
/// "Pay" action never dumps either role into a raw bill list again.
class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({super.key});
  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  bool _loading = true;
  String? _error;
  String _viewerRole = 'Owner';
  List _rows = const [];
  num _total = 0, _pending = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dio = context.read<Dio>();
    setState(() { _loading = true; _error = null; });
    try {
      // Rent view first — it also tells us the viewer's role.
      final rentRes = await dio.get('/rent-payments');
      final rentData = Map<String, dynamic>.from(rentRes.data as Map);
      final role = '${rentData['viewerRole'] ?? 'Owner'}';
      List rows;
      if (role == 'Tenant') {
        rows = (rentData['rentPayments'] as List? ?? const [])
            .map((r) => {
                  'date': r['paidAt'],
                  'label': 'Rent · ${r['month'] ?? ''}',
                  'mode': r['paymentMode'],
                  'amount': r['amount'],
                  'status': r['status'] ?? 'Confirmed',
                })
            .toList();
      } else {
        // Owner "payment history" is the Credit side of /ledger — there is no
        // separate /payments/history endpoint (that call 404'd forever).
        final res = await dio.get('/ledger');
        final data = Map<String, dynamic>.from(res.data as Map);
        final txns = (data['transactions'] as List? ?? const [])
            .cast<Map>()
            .where((t) => t['type'] == 'Credit');
        rows = txns
            .map((p) {
              final breakdown = (p['paymentBreakdown'] as Map?) ?? const {};
              return {
                'date': p['date'],
                'label': p['description'] ?? p['category'] ?? 'Payment',
                'mode': p['paymentMode'],
                'amount': p['amount'],
                'status': 'Confirmed',
                'applied': breakdown['principalCleared'],
                'interest': breakdown['interestCleared'],
                'advance': breakdown['advanceCredit'],
                'receiptNo': p['transactionRef'] ?? p['chequeNo'] ?? p['transactionId'],
              };
            })
            .toList();
      }
      num total = 0, pending = 0;
      for (final r in rows) {
        final a = (r['amount'] as num?) ?? 0;
        if (r['status'] == 'Pending') { pending += a; } else { total += a; }
      }
      if (!mounted) return;
      setState(() {
        _viewerRole = role; _rows = rows; _total = total; _pending = pending; _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() { _error = apiErrorMessage(err); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTenant = _viewerRole == 'Tenant';
    return Scaffold(
      appBar: AppBar(title: Text(isTenant ? 'Rent payments' : 'Payment history')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline_rounded, size: 34, color: Colors.red),
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Row(children: [
                        Expanded(child: _Stat(label: isTenant ? 'Rent confirmed' : 'Total paid', value: inr(_total), color: Colors.green)),
                        const SizedBox(width: 10),
                        Expanded(child: _Stat(label: 'Awaiting confirmation', value: inr(_pending), color: Colors.orange)),
                      ]),
                      const SizedBox(height: 16),
                      const Text('All transactions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 8),
                      if (_rows.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('No payments recorded yet.'))
                      else
                        ..._rows.map(_row),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }

  Widget _row(dynamic r) {
    final d = DateTime.tryParse('${r['date'] ?? ''}');
    final status = '${r['status'] ?? ''}';
    final pending = status == 'Pending';
    final breakdown = <String>[
      if ((r['applied'] as num?) != null && (r['applied'] as num) > 0) 'principal ${inr(r['applied'] as num)}',
      if ((r['interest'] as num?) != null && (r['interest'] as num) > 0) 'interest ${inr(r['interest'] as num)}',
      if ((r['advance'] as num?) != null && (r['advance'] as num) > 0) 'advance ${inr(r['advance'] as num)}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${r['label']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            Text(inr((r['amount'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
          const SizedBox(height: 3),
          Text(
            [
              if (d != null) '${d.day}/${d.month}/${d.year}',
              if (r['mode'] != null) '${r['mode']}',
              if (r['receiptNo'] != null) 'Receipt ${r['receiptNo']}',
              status,
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: pending ? Colors.orange.shade800 : Colors.grey.shade600, fontWeight: FontWeight.w600),
          ),
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Applied as: ${breakdown.join(', ')}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(11)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
      );
}
