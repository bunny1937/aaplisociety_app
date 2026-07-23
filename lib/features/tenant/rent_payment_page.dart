import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_error.dart';
import '../member/bills_page.dart' show inr;
import 'tenant_api.dart';

const _paymentModes = ['Cash', 'UPI', 'BankTransfer', 'Cheque', 'Online'];

class RentPaymentPage extends StatefulWidget {
  const RentPaymentPage({super.key});
  @override
  State<RentPaymentPage> createState() => _RentPaymentPageState();
}

class _RentPaymentPageState extends State<RentPaymentPage> {
  List _payments = [];
  bool _loading = true;
  DateTime? _month;
  final _amount = TextEditingController();
  String _mode = _paymentModes.first;
  String? _error;
  bool _submitting = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dio = context.read<Dio>();
    try {
      final payments = await fetchRentPayments(dio);
      if (mounted) {
        setState(() {
          _payments = payments;
          _loading = false;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = apiErrorMessage(err);
        });
      }
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _month ?? DateTime(now.year, now.month),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month + 1),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select the rent month',
    );
    if (picked != null) setState(() => _month = picked);
  }

  Future<void> _record() async {
    final month = _month;
    if (month == null) {
      setState(() => _error = 'Select the rent month');
      return;
    }
    final amount = num.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final dio = context.read<Dio>();
      await recordRentPayment(dio, {
        'month': '${month.year}-${month.month.toString().padLeft(2, '0')}',
        'amount': amount,
        'paymentMode': _mode,
        'paidAt': DateTime.now().toUtc().toIso8601String(),
      });
      setState(() => _month = null);
      _amount.clear();
      await _load();
    } on DioException catch (err) {
      setState(() => _error = apiErrorMessage(err));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rent Payments')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Record a payment',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('rent_month_field'),
                  onPressed: _pickMonth,
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined, size: 18),
                      const SizedBox(width: 10),
                      Text(_month == null
                          ? 'Select rent month'
                          : DateFormat('MMMM yyyy').format(_month!)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('rent_amount_field'),
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount (Rs)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _mode,
                  items: _paymentModes
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setState(() => _mode = v ?? _mode),
                  decoration: const InputDecoration(labelText: 'Payment mode'),
                ),
                if (_mode == 'Online')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Online payments are recorded manually for now — gateway integration is coming later.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _submitting ? null : _record,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Record payment'),
                ),
                const SizedBox(height: 28),
                const Text('History',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                if (_payments.isEmpty)
                  const Text('No payments recorded yet',
                      style: TextStyle(color: Colors.grey)),
                ..._payments.map((raw) {
                  final p = raw as Map;
                  return Card(
                    child: ListTile(
                      title: Text(
                          '${p['month']} — ${inr((p['amount'] as num?) ?? 0)}'),
                      subtitle: Text('${p['paymentMode']}'),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
