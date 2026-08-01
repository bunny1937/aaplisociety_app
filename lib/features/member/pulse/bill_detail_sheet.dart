import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:printing/printing.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bills_page.dart' show inr, effectiveStatus, billTitle;
import 'pulse.dart';
import 'bill_format_sheet.dart';
import 'bill_pdf.dart';
import 'member_display.dart';
import 'payment_sheet.dart';

/// Port of Primitives.jsx `BillDetailSheet` (member-v2 `ScreensBills.jsx`):
/// itemized breakdown, Paid/Balance summary, "View full bill" → Bill Format
/// sheet, "Pay" → Make Payment sheet chained on top, Save/Share row.
/// Returns `true` via Navigator.pop if a payment was made, so the bills list
/// knows to reload.
Future<bool?> showBillDetailSheet(BuildContext context, Map bill,
    {bool isLatestBill = true}) {
  return showPulseSheet<bool>(
    context,
    title: billTitle(bill),
    builder: (context) =>
        _BillDetailBody(bill: bill, isLatestBill: isLatestBill),
  );
}

class _BillDetailBody extends StatefulWidget {
  final Map bill;
  // A bill with money still owed is only payable if it's the member's newest
  // bill — every older bill's balance was already carried forward into a
  // later bill's `previousBalance` once that later bill was generated, so
  // paying it directly here would pay against a stale figure.
  final bool isLatestBill;
  const _BillDetailBody({required this.bill, required this.isLatestBill});
  @override
  State<_BillDetailBody> createState() => _BillDetailBodyState();
}

class _BillDetailBodyState extends State<_BillDetailBody> {
  bool _paid = false;
  String _tab = 'Bill';
  // This bill's OWN receipt — shown directly when this bill itself is Paid.
  Map? _ownReceipt;
  // A DIFFERENT, earlier-period receipt shown as a reference tab only when
  // viewing a bill that isn't itself paid yet (e.g. viewing June while May
  // is already settled) — was previously the only receipt lookup this sheet
  // did, which meant a bill could never show its OWN receipt: opening May's
  // (now paid) bill directly found nothing, since there was no later bill
  // to "reference" it from, and June hadn't been generated yet.
  Map? _priorReceipt;
  @override
  void initState() {
    super.initState();
    _loadReceipts();
  }

  Future<void> _loadReceipts() async {
    try {
      final dio = context.read<Dio>();
      final res = await dio.get('/receipts');
      final receipts = (res.data['receipts'] as List).cast<Map>();
      final billPeriod = '${widget.bill['billPeriodId'] ?? ''}';
      Map? own;
      if (billPeriod.isNotEmpty) {
        final ownMatches = receipts
            .where((r) => '${r['billPeriodId'] ?? ''}' == billPeriod)
            .toList()
          ..sort((a, b) =>
              '${b['paidAt'] ?? ''}'.compareTo('${a['paidAt'] ?? ''}'));
        if (ownMatches.isNotEmpty) own = ownMatches.first;
      }
      List<Map> priorCandidates;
      if (billPeriod.isNotEmpty) {
        priorCandidates = receipts
            .where(
                (r) => '${r['billPeriodId'] ?? ''}'.compareTo(billPeriod) < 0)
            .toList()
          ..sort((a, b) => '${b['billPeriodId'] ?? ''}'
              .compareTo('${a['billPeriodId'] ?? ''}'));
      } else {
        priorCandidates = receipts
            .where(
                (r) => '${r['billId'] ?? ''}' != '${widget.bill['_id'] ?? ''}')
            .toList();
      }
      if (mounted) {
        setState(() {
          _ownReceipt = own;
          _priorReceipt =
              priorCandidates.isNotEmpty ? priorCandidates.first : null;
        });
      }
    } catch (_) {
      // No receipts endpoint reachable / none exist yet — falls back to the
      // plain "fully settled" message with no receipt details.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final bill = widget.bill;
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthed ? auth.user : const <String, dynamic>{};
    final societyName = resolveSocietyName(user, null);
    final status = effectiveStatus(bill);
    final amount = (bill['totalAmount'] as num?) ?? 0;
    final paidAmt = (bill['amountPaid'] as num?) ?? 0;
    final balance = amount - paidAmt;
    final settled = _paid || status == 'Paid';
    // Payable only when this is the member's newest bill — an older bill's
    // balance was already carried forward into a later bill once that later
    // bill was generated, so there's nothing to pay here anymore even though
    // this bill's own stored balance is still > 0.
    final payable = !settled && widget.isLatestBill;
    final closed = !settled && !widget.isLatestBill;
    final charges = (bill['charges'] as Map?)?.cast<String, dynamic>();
    final previousBalance = (bill['previousBalance'] as num?) ?? 0;
    final interest = (bill['currentInterest'] as num?) ??
        (bill['interestAmount'] as num?) ??
        (bill['billInterestBalance'] as num?) ??
        0;
    // ---- Full breakdown pieces --------------------------------------------
    // All of the split fields below are optional on the payload; when the
    // backend hasn't projected them we degrade to what we do have, so the
    // sheet never renders "null".
    // Current charges = sum of THIS month's itemized heads only (excludes any
    // carried-forward balance and interest).
    final currentCharges =
        charges?.values.fold<num>(0, (s, v) => s + ((v as num?) ?? 0)) ?? 0;
    // Previous balance splits into its principal (P) + interest (I) parts.
    final openingPrincipal = bill['openingPrincipal'] as num?;
    final openingInterest = bill['openingInterest'] as num?;
    // Interest owed = new (charged this month) + old (already sitting inside
    // the previous balance above). `interest` is this month's NEW interest.
    final newInterest = interest;
    final oldInterest = openingInterest ?? 0;
    final tone = switch (status) {
      'Paid' => PulseTone.paid,
      // A closed (superseded) Partial bill has nothing actionable left — soften
      // it to a neutral tone instead of the same warning-yellow an actually
      // payable Partial bill gets.
      'Partial' => closed ? PulseTone.neutral : PulseTone.partial,
      'Overdue' => closed ? PulseTone.neutral : PulseTone.overdue,
      _ => PulseTone.unpaid
    };
    final statusLabel = settled
        ? 'Paid'
        : (status == 'Partial' ? 'Paid (Partial)' : status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
                'Bill #${bill['_id'] != null ? '${bill['_id']}'.substring(0, 8).toUpperCase() : '—'}',
                style: TextStyle(
                    fontSize: 12, color: t.fg4, fontWeight: FontWeight.w600)),
            PulsePill(
                label: statusLabel,
                tone: settled ? PulseTone.paid : tone),
          ],
        ),
        if (!settled && _priorReceipt != null) ...[
          const SizedBox(height: 14),
          PulseSegmented<String>(
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
            options: [
              PulseSegmentedOption(value: 'Bill', label: billTitle(bill)),
              PulseSegmentedOption(
                  value: 'Receipt',
                  label: 'Last paid · ${_priorReceipt!['periodLabel'] ?? ''}',
                  icon: Icons.receipt_long_rounded),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (!settled && _tab == 'Receipt' && _priorReceipt != null)
          _ReceiptView(receipt: _priorReceipt!)
        else ...[
          if (charges != null && charges.isNotEmpty)
            PulseCard(
              padding: const EdgeInsets.all(4),
              color: t.surface2,
              child: Column(
                children: [
                  ...charges.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                                child: Text(e.key,
                                    style:
                                        TextStyle(fontSize: 13, color: t.fg3))),
                            Text(inr((e.value as num?) ?? 0),
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: t.fg2)),
                          ],
                        ),
                      )),
                  // ---- Detailed breakdown --------------------------------
                  // A member could previously never tell why Total exceeded
                  // the sum of the itemized heads. Now every component is
                  // spelled out: current charges, previous balance (P + I),
                  // interest (new + old), and the explicit final equation.
                  _breakdownDivider(t),
                  _extraChargeRow(t, 'Current charges', currentCharges),
                  if (previousBalance > 0) ...[
                    _extraChargeRow(
                        t, 'Previous balance (P + I)', previousBalance),
                    if (openingPrincipal != null)
                      _breakdownSubRow(t, 'Principal (P)', openingPrincipal),
                    if (openingInterest != null)
                      _breakdownSubRow(t, 'Interest (I)', openingInterest),
                  ],
                  if (newInterest > 0 || oldInterest > 0) ...[
                    _extraChargeRow(
                        t, 'Interest (new + old)', newInterest + oldInterest,
                        warn: true),
                    _breakdownSubRow(t, 'New · this month', newInterest),
                    _breakdownSubRow(
                        t, 'Old · carried in prev balance', oldInterest),
                  ],
                  // Explicit equation so the Total is never a mystery. Note it
                  // adds NEW interest only — the old/carried interest is already
                  // inside "Previous balance" above, so adding it again would
                  // double-count.
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                        '${inr(currentCharges)} current  +  ${inr(previousBalance)} prev balance  +  ${inr(newInterest)} interest  =  ${inr(amount)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: t.fg4,
                            fontWeight: FontWeight.w600)),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        color: t.brandSoft,
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(PulseTokens.radiusSm))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Due',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: t.brand)),
                        Text(inr(amount),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: t.brand)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _SummaryChip(
                      label: 'Paid', value: paidAmt, color: t.success)),
              const SizedBox(width: 10),
              Expanded(
                  child: _SummaryChip(
                      label: 'Balance',
                      value: settled ? 0 : balance,
                      color: settled
                          ? t.success
                          : (closed ? t.fg3 : t.danger))),
            ],
          ),
          const SizedBox(height: 18),
          if (payable)
            PulseButton(
              label: 'Pay ${inr(balance)}',
              full: true,
              onTap: () async {
                final ok = await showMakePaymentSheet(context,
                    bill: bill, amount: balance);
                if (ok == true && context.mounted) {
                  setState(() => _paid = true);
                  Navigator.of(context).pop(true);
                }
              },
            )
          else if (closed)
            // This bill's own balance already rolled into a later bill's
            // carried-forward figure — nothing to pay from here anymore.
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: t.surface3,
                  borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  Text('This bill is closed',
                      style: TextStyle(
                          color: t.fg2,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5)),
                  const SizedBox(height: 4),
                  Text(
                      'Its remaining balance was carried into a later bill — pay from your latest bill instead',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.fg4, fontSize: 11.5)),
                ],
              ),
            )
          else if (_ownReceipt != null)
            // The bill itself is Paid AND has a real receipt on file - show it
            // directly here instead of a bare "fully settled" message. This is
            // the fix for bills that are their own most-recent period (no
            // later bill exists yet to reference them from via _priorReceipt).
            _ReceiptView(receipt: _ownReceipt!)
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: t.successSoft,
                  borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  Text('This bill is fully settled',
                      style: TextStyle(
                          color: t.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5)),
                  const SizedBox(height: 4),
                  Text('No receipt on file for this payment',
                      style: TextStyle(
                          color: t.success.withValues(alpha: 0.75),
                          fontSize: 11.5)),
                ],
              ),
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
                    final bytes =
                        await renderBillPdf(bill, societyName: societyName);
                    await Printing.layoutPdf(
                        onLayout: (_) async => bytes,
                        name: '${billTitle(bill)}.pdf');
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
                    final bytes =
                        await renderBillPdf(bill, societyName: societyName);
                    await Printing.sharePdf(
                        bytes: bytes, filename: '${billTitle(bill)}.pdf');
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

// Thin divider that separates the itemized charge heads from the breakdown
// summary rows below them.
Widget _breakdownDivider(PulseTokens t) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    height: 1,
    color: t.border,
  );
}

// Indented, muted sub-line under a breakdown parent row (e.g. the principal
// and interest parts that make up the previous balance / interest total).
Widget _breakdownSubRow(PulseTokens t, String label, num value) {
  return Padding(
    padding: const EdgeInsets.only(left: 26, right: 12, top: 1, bottom: 1),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
            child: Text('· $label',
                style: TextStyle(fontSize: 11.5, color: t.fg4))),
        Text(inr(value), style: TextStyle(fontSize: 11.5, color: t.fg4)),
      ],
    ),
  );
}

Widget _extraChargeRow(PulseTokens t, String label, num value,
    {bool warn = false}) {
  final color = warn ? t.danger : t.fg2;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: warn ? t.danger : t.fg3,
                    fontWeight: warn ? FontWeight.w600 : FontWeight.normal))),
        Text(inr(value),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ],
    ),
  );
}

class _ReceiptView extends StatelessWidget {
  final Map receipt;
  const _ReceiptView({required this.receipt});
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
                  Text('Paid in full · $periodLabel',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: t.fg1)),
                ],
              ),
              const SizedBox(height: 14),
              Text(inr(amount),
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: t.success)),
              const SizedBox(height: 10),
              _ReceiptRow(label: 'Receipt no.', value: receiptNo),
              _ReceiptRow(
                  label: 'Paid on',
                  value: paidAt != null
                      ? '${paidAt.day}/${paidAt.month}/${paidAt.year}'
                      : '—'),
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
                  final bytes = await renderReceiptPdf(receipt,
                      periodLabel: periodLabel, formatInr: inr);
                  await Printing.layoutPdf(
                      onLayout: (_) async => bytes, name: '$receiptNo.pdf');
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
                  final bytes = await renderReceiptPdf(receipt,
                      periodLabel: periodLabel, formatInr: inr);
                  await Printing.sharePdf(
                      bytes: bytes, filename: '$receiptNo.pdf');
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
          Text(value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: t.fg1)),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final num value;
  final Color color;
  const _SummaryChip(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: t.surface3,
          borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: t.fg4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(inr(value),
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
