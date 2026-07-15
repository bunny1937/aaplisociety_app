import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_error.dart';
import '../../../core/theme/haptics.dart';
import '../bills_page.dart' show inr;
import 'pulse.dart';

/// Port of Primitives.jsx `MakePaymentSheet` (member-v2 `ScreensBills.jsx`)
/// — per user decision, this replaces the old standalone `/payment` route:
/// now a 3-stage bottom sheet (select → processing → success) chained off
/// the Bill Detail sheet, same real `POST /bills/:id/pay` + error handling
/// the routed page used to do. Returns `true` if payment succeeded.
Future<bool?> showMakePaymentSheet(BuildContext context, {required Map bill, required num amount}) {
  return showPulseSheet<bool>(
    context,
    title: 'Make Payment',
    isDismissible: false,
    builder: (context) => _PaymentBody(bill: bill, amount: amount),
  );
}

enum _Stage { select, processing, success }

class _PaymentBody extends StatefulWidget {
  final Map bill;
  final num amount;
  const _PaymentBody({required this.bill, required this.amount});
  @override
  State<_PaymentBody> createState() => _PaymentBodyState();
}

class _PaymentBodyState extends State<_PaymentBody> {
  static const _methods = [
    ('UPI', 'UPI', Icons.qr_code_rounded),
    ('Card', 'Card', Icons.credit_card_rounded),
    ('Net banking', 'NetBanking', Icons.account_balance_rounded),
  ];
  String _method = 'UPI';
  _Stage _stage = _Stage.select;
  String? _error;
  String? _receiptNo;

  Future<void> _pay() async {
    final billId = widget.bill['_id'];
    if (billId == null) return;
    Haptics.medium();
    setState(() { _stage = _Stage.processing; _error = null; });
    try {
      final modeCode = _methods.firstWhere((m) => m.$1 == _method).$2;
      final res = await context.read<Dio>().post('/bills/$billId/pay', data: {
        'amount': widget.amount,
        'paymentMode': modeCode,
      });
      if (!mounted) return;
      Haptics.success();
      final data = res.data is Map ? res.data as Map : const {};
      setState(() {
        _stage = _Stage.success;
        _receiptNo = '${data['receiptNo'] ?? data['_id'] ?? ''}';
      });
    } on DioException catch (err) {
      if (!mounted) return;
      Haptics.heavy();
      setState(() { _stage = _Stage.select; _error = apiErrorMessage(err, 'Payment failed'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _Stage.select => _SelectStage(bill: widget.bill, amount: widget.amount, method: _method, error: _error, onSelect: (m) { Haptics.select(); setState(() => _method = m); }, onPay: _pay),
      _Stage.processing => const _ProcessingStage(),
      _Stage.success => _SuccessStage(
          amount: widget.amount,
          receiptNo: _receiptNo,
          period: '${widget.bill['title'] ?? widget.bill['period'] ?? ''}',
          onDone: () => Navigator.of(context).pop(true),
        ),
    };
  }
}

class _SelectStage extends StatelessWidget {
  final Map bill;
  final num amount;
  final String method;
  final String? error;
  final ValueChanged<String> onSelect;
  final VoidCallback onPay;
  const _SelectStage({required this.bill, required this.amount, required this.method, required this.error, required this.onSelect, required this.onPay});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: t.brandSoft, borderRadius: BorderRadius.circular(PulseTokens.radius)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Amount to pay', style: TextStyle(fontSize: 12, color: t.brand.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(inr(amount), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: t.brand)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text('Payment method', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.fg1)),
        const SizedBox(height: 10),
        ..._PaymentBodyState._methods.map((m) {
          final sel = m.$1 == method;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => onSelect(m.$1),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: sel ? t.brandSoft : t.surface,
                  border: Border.all(color: sel ? t.brand : t.border, width: sel ? 1.6 : 1),
                  borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(color: t.surface3, borderRadius: BorderRadius.circular(10)),
                      child: Icon(m.$3, size: 17, color: sel ? t.brand : t.fg3),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(m.$1, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: t.fg1))),
                    Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: sel ? t.brand : t.border, width: 1.6)),
                      alignment: Alignment.center,
                      child: sel ? Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: t.brand)) : null,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error!, style: TextStyle(color: t.danger, fontSize: 12.5)),
        ],
        const SizedBox(height: 16),
        PulseButton(label: 'Pay ${inr(amount)}', full: true, onTap: onPay),
      ],
    );
  }
}

class _ProcessingStage extends StatelessWidget {
  const _ProcessingStage();
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const PulseSpinner(size: 36),
          const SizedBox(height: 18),
          Text('Processing payment…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.fg1)),
          const SizedBox(height: 4),
          Text("Please don't close this screen", style: TextStyle(fontSize: 12, color: t.fg4)),
        ],
      ),
    );
  }
}

class _SuccessStage extends StatelessWidget {
  final num amount;
  final String? receiptNo;
  final String period;
  final VoidCallback onDone;
  const _SuccessStage({required this.amount, required this.receiptNo, required this.period, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const PulseIllustration(kind: PulseIllo.celebrate, size: 110),
          const SizedBox(height: 14),
          Text('Payment successful!', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: t.fg1)),
          const SizedBox(height: 8),
          Text(inr(amount), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: t.success)),
          const SizedBox(height: 4),
          Text(
            receiptNo != null && receiptNo!.isNotEmpty ? 'Receipt ${receiptNo!.length > 10 ? receiptNo!.substring(0, 10) : receiptNo} · $period' : period,
            style: TextStyle(fontSize: 12.5, color: t.fg4),
          ),
          const SizedBox(height: 22),
          PulseButton(label: 'Done', full: true, variant: PulseBtnVariant.success, onTap: onDone),
        ],
      ),
    );
  }
}
