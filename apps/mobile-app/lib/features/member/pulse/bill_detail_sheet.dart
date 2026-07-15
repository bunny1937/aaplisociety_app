import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:printing/printing.dart';
import '../bills_page.dart' show inr, effectiveStatus, billTitle;
import 'pulse.dart';
import 'bill_format_sheet.dart';
import 'bill_pdf.dart';
import 'payment_sheet.dart';

/// Port of Primitives.jsx `BillDetailSheet` (member-v2 `ScreensBills.jsx`):
/// itemized breakdown, Paid/Balance summary, "View full bill" → Bill Format
/// sheet, "Pay" → Make Payment sheet chained on top, Save/Share row.
/// Returns `true` via Navigator.pop if a payment was made, so the bills list
/// knows to reload.
Future<bool?> showBillDetailSheet(BuildContext context, Map bill) {
  return showPulseSheet<bool>(
    context,
    title: billTitle(bill),
    builder: (context) => _BillDetailBody(bill: bill),
  );
}

class _BillDetailBody extends StatefulWidget {
  final Map bill;
  const _BillDetailBody({required this.bill});
  @override
  State<_BillDetailBody> createState() => _BillDetailBodyState();
}

class _BillDetailBodyState extends State<_BillDetailBody> {
  bool _paid = false;
  String _tab = 'Bill';
  Map? _lastReceipt;

  @override
  void initState() {
    super.initState();
    _loadLastReceipt();
  }

  // Finds the most recent receipt from a period strictly before this bill's
  // — e.g. viewing the June bill surfaces May's paid receipt as a reference,
  // so a member can compare before paying instead of digging through the
  // separate Receipts tab.
  Future<void> _loadLastReceipt() async {
    try {
      final dio = context.read<Dio>();
      final res = await dio.get('/receipts');
      final receipts = (res.data as List).cast<Map>();
      final billPeriod = '${widget.bill['billPeriodId'] ?? ''}';
      List<Map> candidates;
      if (billPeriod.isNotEmpty) {
        candidates = receipts.where((r) => '${r['billPeriodId'] ?? ''}'.compareTo(billPeriod) < 0).toList()
          ..sort((a, b) => '${b['billPeriodId'] ?? ''}'.compareTo('${a['billPeriodId'] ?? ''}'));
      } else {
        candidates = receipts.where((r) => '${r['billId'] ?? ''}' != '${widget.bill['_id'] ?? ''}').toList();
      }
      if (mounted && candidates.isNotEmpty) setState(() => _lastReceipt = candidates.first);
    } catch (_) {
      // No receipts endpoint reachable / none exist yet — tab simply doesn't show.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final bill = widget.bill;
    final status = effectiveStatus(bill);
    final amount = (bill['amount'] as num?) ?? 0;
    final paidAmt = (bill['amountPaid'] as num?) ?? 0;
    final balance = amount - paidAmt;
    final settled = _paid || status == 'Paid';
    final charges = (bill['charges'] as Map?)?.cast<String, dynamic>();
    final tone = switch (status) { 'Paid' => PulseTone.paid, 'Partial' => PulseTone.partial, 'Overdue' => PulseTone.overdue, _ => PulseTone.unpaid };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Bill #${bill['_id'] != null ? '${bill['_id']}'.substring(0, 8).toUpperCase() : '—'}', style: TextStyle(fontSize: 12, color: t.fg4, fontWeight: FontWeight.w600)),
            PulsePill(label: settled ? 'Paid' : status, tone: settled ? PulseTone.paid : tone),
          ],
        ),
        if (_lastReceipt != null) ...[
          const SizedBox(height: 14),
          PulseSegmented<String>(
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
            options: [
              PulseSegmentedOption(value: 'Bill', label: billTitle(bill)),
              PulseSegmentedOption(value: 'Receipt', label: 'Last paid · ${_lastReceipt!['periodLabel'] ?? ''}', icon: Icons.receipt_long_rounded),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (_tab == 'Receipt' && _lastReceipt != null)
          _LastReceiptView(receipt: _lastReceipt!)
        else ...[
        if (charges != null && charges.isNotEmpty)
          PulseCard(
            padding: const EdgeInsets.all(4),
            color: t.surface2,
            child: Column(
              children: [
                ...charges.entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(e.key, style: TextStyle(fontSize: 13, color: t.fg3))),
                          Text(inr((e.value as num?) ?? 0), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.fg2)),
                        ],
                      ),
                    )),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: t.brandSoft, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(PulseTokens.radiusSm))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: t.brand)),
                      Text(inr(amount), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: t.brand)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _SummaryChip(label: 'Paid', value: paidAmt, color: t.success)),
            const SizedBox(width: 10),
            Expanded(child: _SummaryChip(label: 'Balance', value: settled ? 0 : balance, color: settled ? t.success : t.danger)),
          ],
        ),
        const SizedBox(height: 18),
        if (!settled)
          PulseButton(
            label: 'Pay ${inr(balance)}',
            full: true,
            onTap: () async {
              final ok = await showMakePaymentSheet(context, bill: bill, amount: balance);
              if (ok == true && mounted) {
                setState(() => _paid = true);
                Navigator.of(context).pop(true);
              }
            },
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.successSoft, borderRadius: BorderRadius.circular(14)),
            child: Text('This bill is fully settled', style: TextStyle(color: t.success, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
        const SizedBox(height: 10),
        PulseButton(
          label: 'View full bill',
          full: true,
          variant: PulseBtnVariant.secondary,
          onTap: () => showBillFormatSheet(context, bill),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: PulseButton(
                label: 'Save PDF',
                icon: Icons.download_outlined,
                variant: PulseBtnVariant.ghost,
                onTap: () async {
                  final bytes = await renderBillPdf(bill);
                  await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${billTitle(bill)}.pdf');
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PulseButton(
                label: 'Share',
                icon: Icons.ios_share_rounded,
                variant: PulseBtnVariant.ghost,
                onTap: () async {
                  final bytes = await renderBillPdf(bill);
                  await Printing.sharePdf(bytes: bytes, filename: '${billTitle(bill)}.pdf');
                },
              ),
            ),
          ],
        ),
        ],
      ],
    );
  }
}

class _LastReceiptView extends StatelessWidget {
  final Map receipt;
  const _LastReceiptView({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final amount = (receipt['amount'] as num?) ?? 0;
    final periodLabel = '${receipt['periodLabel'] ?? ''}';
    final receiptNo = '${receipt['receiptNo'] ?? '—'}';
    final paidAt = DateTime.tryParse('${receipt['paidAt']}');
    final paymentMode = '${receipt['paymentMode'] ?? '—'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PulseCard(
          padding: const EdgeInsets.all(16),
          color: t.successSoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: t.success, size: 18),
                  const SizedBox(width: 8),
                  Text('Paid in full · $periodLabel', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: t.fg1)),
                ],
              ),
              const SizedBox(height: 14),
              Text(inr(amount), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: t.success)),
              const SizedBox(height: 10),
              _ReceiptRow(label: 'Receipt no.', value: receiptNo),
              _ReceiptRow(label: 'Paid on', value: paidAt != null ? '${paidAt.day}/${paidAt.month}/${paidAt.year}' : '—'),
              _ReceiptRow(label: 'Payment mode', value: paymentMode),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: PulseButton(
                label: 'Save PDF',
                icon: Icons.download_outlined,
                variant: PulseBtnVariant.ghost,
                onTap: () async {
                  final bytes = await renderReceiptPdf(receipt, periodLabel: periodLabel, formatInr: inr);
                  await Printing.layoutPdf(onLayout: (_) async => bytes, name: '$receiptNo.pdf');
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PulseButton(
                label: 'Share',
                icon: Icons.ios_share_rounded,
                variant: PulseBtnVariant.ghost,
                onTap: () async {
                  final bytes = await renderReceiptPdf(receipt, periodLabel: periodLabel, formatInr: inr);
                  await Printing.sharePdf(bytes: bytes, filename: '$receiptNo.pdf');
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReceiptRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: t.fg3)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.fg1)),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final num value;
  final Color color;
  const _SummaryChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.surface3, borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: t.fg4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(inr(value), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
