import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bills_page.dart' show inr, billTitle;
import 'bill_pdf.dart';
import 'member_display.dart';
import 'pulse.dart';

/// Port of Primitives.jsx `BillFormatSheet` (member-v2 `ScreensBills.jsx`) —
/// fully new screen, no current-app equivalent. Recreates a printable bill:
/// gradient header, meta grid, itemized table, total bar. No backend-
/// rendered bill PDF endpoint was found during implementation (see
/// MEMBER_V2_GAPS.md) so "Save PDF" here shares/toasts rather than
/// generating a real file — swap for a real download once that endpoint
/// exists.
Future<void> showBillFormatSheet(BuildContext context, Map bill) {
  return showPulseSheet(
    context,
    full: true,
    builder: (context) => _BillFormatBody(bill: bill),
  );
}

class _BillFormatBody extends StatelessWidget {
  final Map bill;
  const _BillFormatBody({required this.bill});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthed ? auth.user : const <String, dynamic>{};
    final societyName = resolveSocietyName(user, null);
    final amount = (bill['totalAmount'] as num?) ?? 0;
    final paid = (bill['amountPaid'] as num?) ?? 0;
    final prevBalance = (bill['previousBalance'] as num?) ?? 0;
    final due = DateTime.tryParse('${bill['dueDate']}');
    final charges =
        (bill['charges'] as Map?)?.cast<String, dynamic>() ?? const {};
    // ---- Full breakdown pieces (same model as the bill detail sheet) ------
    final currentCharges =
        charges.values.fold<num>(0, (s, v) => s + ((v as num?) ?? 0));
    final openingPrincipal = bill['openingPrincipal'] as num?;
    final openingInterest = bill['openingInterest'] as num?;
    final newInterest = (bill['currentInterest'] as num?) ??
        (bill['interestAmount'] as num?) ??
        (bill['billInterestBalance'] as num?) ??
        0;
    final oldInterest = openingInterest ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PulseTokens.radius),
            gradient: LinearGradient(colors: [t.brand2, t.brand]),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((societyName ?? 'YOUR SOCIETY').toUpperCase(),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              const Text('MAINTENANCE BILL',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              if (due != null)
                Text('Due ${due.day} ${_month(due.month)} ${due.year}',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5)),
            ],
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 3.2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            _Meta(label: 'Period', value: billTitle(bill)),
            _Meta(label: 'Flat', value: _flatLabel(bill)),
            _Meta(label: 'Owner', value: '${bill['ownerName'] ?? '—'}'),
            _Meta(
                label: 'Area',
                value: (bill['areaSqft'] ?? bill['carpetAreaSqft']) != null
                    ? '${bill['areaSqft'] ?? bill['carpetAreaSqft']} sqft'
                    : '—'),
          ],
        ),
        const SizedBox(height: 16),
        if (prevBalance > 0)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: t.warningSoft,
                borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: t.warning),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'Includes previous balance of ${inr(prevBalance)}',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: t.warning,
                            fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        PulseCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: t.brand,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(PulseTokens.radius))),
                child: Row(
                  children: [
                    Expanded(
                        child: Text('CHARGE',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4))),
                    Text('AMOUNT',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4)),
                  ],
                ),
              ),
              ...charges.entries.toList().asMap().entries.map((e) {
                final zebra = e.key.isOdd;
                final entry = e.value;
                return Container(
                  color: zebra ? t.surface2 : Colors.transparent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(entry.key,
                              style: TextStyle(fontSize: 12.5, color: t.fg3))),
                      Text(inr((entry.value as num?) ?? 0),
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: t.fg2)),
                    ],
                  ),
                );
              }),
              // ---- Detailed breakdown: current charges, previous balance
              // (P + I), interest (new + old), and the explicit equation, so
              // the printable bill matches the itemised detail sheet.
              _fmtDivider(t),
              _fmtRow(t, 'Current charges', inr(currentCharges), bold: true),
              if (prevBalance > 0) ...[
                _fmtRow(t, 'Previous balance (P + I)', inr(prevBalance)),
                if (openingPrincipal != null)
                  _fmtSubRow(t, 'Principal (P)', inr(openingPrincipal)),
                if (openingInterest != null)
                  _fmtSubRow(t, 'Interest (I)', inr(openingInterest)),
              ],
              if (newInterest > 0 || oldInterest > 0) ...[
                _fmtRow(
                    t, 'Interest (new + old)', inr(newInterest + oldInterest),
                    warn: true),
                _fmtSubRow(t, 'New · this month', inr(newInterest)),
                _fmtSubRow(
                    t, 'Old · carried in prev balance', inr(oldInterest)),
              ],
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                    '${inr(currentCharges)} current  +  ${inr(prevBalance)} prev balance  +  ${inr(newInterest)} interest  =  ${inr(amount)}',
                    style: TextStyle(
                        fontSize: 10.5,
                        color: t.fg4,
                        fontWeight: FontWeight.w600)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                        child: Text('Total',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: t.fg1))),
                    Text(inr(amount),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: t.fg1)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: [t.brand2, t.brand]),
              borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Payable',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              Text(inr(amount - paid),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Center(
            child: Text('Computer generated bill · No signature required',
                style: TextStyle(fontSize: 10.5, color: t.fg5))),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: PulseButton(
                label: 'Save PDF',
                icon: Icons.download_outlined,
                variant: PulseBtnVariant.secondary,
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
  String _flatLabel(Map bill) {
    final wing = bill['wing']?.toString();
    final flatNo = bill['flatNo']?.toString();
    if (flatNo == null || flatNo.isEmpty) return '—';
    return wing != null && wing.isNotEmpty ? '$wing-$flatNo' : flatNo;
  }
}

// Breakdown row helpers for the printable bill format sheet. Mirror the
// bill_detail_sheet.dart breakdown layout so "View full bill" matches it.
Widget _fmtDivider(PulseTokens t) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    height: 1,
    color: t.border);

Widget _fmtRow(PulseTokens t, String label, String value,
    {bool bold = false, bool warn = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    color: warn ? t.danger : t.fg3,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
        Text(value,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: warn ? t.danger : t.fg2)),
      ],
    ),
  );
}

Widget _fmtSubRow(PulseTokens t, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(left: 26, right: 12, top: 1, bottom: 1),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
            child:
                Text('· $label', style: TextStyle(fontSize: 11, color: t.fg4))),
        Text(value, style: TextStyle(fontSize: 11, color: t.fg4)),
      ],
    ),
  );
}

class _Meta extends StatelessWidget {
  final String label;
  final String value;
  const _Meta({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: t.surface3,
          borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9.5, color: t.fg4, fontWeight: FontWeight.w600)),
          Text(value,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: t.fg1),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}