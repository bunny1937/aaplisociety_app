import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_error.dart';
import 'tenant_api.dart';

/// Owner-only, direct-write record of a past tenancy (e.g. one that pre-dates
/// this system) — deliberately no approval step, unlike AddTenantPage's
/// TenantRequest flow. Saved immediately and already visible to admin on the
/// existing web app "View Members" page, which renders Member.tenantHistory.
class TenantHistoryPage extends StatefulWidget {
  const TenantHistoryPage({super.key});
  @override
  State<TenantHistoryPage> createState() => _TenantHistoryPageState();
}

class _TenantHistoryPageState extends State<TenantHistoryPage> {
  List _history = [];
  bool _loading = true;
  final _tenantName = TextEditingController();
  final _tenantPhone = TextEditingController();
  final _tenantEmail = TextEditingController();
  final _rentPerMonth = TextEditingController();
  final _depositAmount = TextEditingController();
  final _moveOutReason = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String? _formError;
  bool _submitting = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dio = context.read<Dio>();
    try {
      final history = await fetchTenantHistory(dio);
      if (mounted) {
        setState(() {
          _history = history;
          _loading = false;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _loading = false;
          _formError = apiErrorMessage(err);
        });
      }
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    final rent = num.tryParse(_rentPerMonth.text.trim());
    if (_tenantName.text.trim().length < 2) {
      setState(() => _formError = 'Tenant name is required');
      return;
    }
    if (!RegExp(r'^[0-9]{10}$').hasMatch(_tenantPhone.text.trim())) {
      setState(() => _formError = 'Enter a valid 10-digit phone number');
      return;
    }
    if (_startDate == null || _endDate == null) {
      setState(() => _formError = 'Select the tenancy start and end dates');
      return;
    }
    if (!_endDate!.isAfter(_startDate!)) {
      setState(() => _formError = 'End date must be after the start date');
      return;
    }
    if (rent == null || rent <= 0) {
      setState(() => _formError = 'Enter a valid monthly rent amount');
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      final dio = context.read<Dio>();
      await submitTenantHistory(dio, {
        'tenantName': _tenantName.text.trim(),
        'tenantPhone': _tenantPhone.text.trim(),
        if (_tenantEmail.text.trim().isNotEmpty)
          'tenantEmail': _tenantEmail.text.trim(),
        'startDate':
            DateTime.utc(_startDate!.year, _startDate!.month, _startDate!.day)
                .toIso8601String(),
        'endDate': DateTime.utc(_endDate!.year, _endDate!.month, _endDate!.day)
            .toIso8601String(),
        'rentPerMonth': rent,
        'depositAmount': num.tryParse(_depositAmount.text.trim()) ?? 0,
        if (_moveOutReason.text.trim().isNotEmpty)
          'moveOutReason': _moveOutReason.text.trim(),
      });
      _tenantName.clear();
      _tenantPhone.clear();
      _tenantEmail.clear();
      _rentPerMonth.clear();
      _depositAmount.clear();
      _moveOutReason.clear();
      setState(() {
        _startDate = null;
        _endDate = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tenant history saved')));
      }
      await _load();
    } on DioException catch (err) {
      setState(() => _formError = apiErrorMessage(err));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _tenantName.dispose();
    _tenantPhone.dispose();
    _tenantEmail.dispose();
    _rentPerMonth.dispose();
    _depositAmount.dispose();
    _moveOutReason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('My tenants')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_history.isNotEmpty) ...[
                  const Text('Past tenants',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  ..._history.map((raw) {
                    final h = raw as Map;
                    final start = DateTime.tryParse('${h['leaseStartDate']}');
                    final end = DateTime.tryParse('${h['leaseEndDate']}');
                    return Card(
                      child: ListTile(
                        title: Text('${h['tenantName']}'),
                        subtitle: Text(
                          '${start != null ? dateFmt.format(start) : '—'} — ${end != null ? dateFmt.format(end) : '—'}'
                          '${h['rentPerMonth'] != null ? ' · Rs ${h['rentPerMonth']}/mo' : ''}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => showDialog(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text('${h['tenantName']}'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Phone: ${h['tenantPhone'] ?? '—'}'),
                                if (h['tenantEmail'] != null)
                                  Text('Email: ${h['tenantEmail']}'),
                                Text(
                                    'Lease: ${start != null ? dateFmt.format(start) : '—'} — ${end != null ? dateFmt.format(end) : '—'}'),
                                Text(
                                    'Rent/month: Rs ${h['rentPerMonth'] ?? '—'}'),
                                if ((h['depositAmount'] as num?) != null &&
                                    (h['depositAmount'] as num) > 0)
                                  Text('Deposit: Rs ${h['depositAmount']}'),
                                if (h['moveOutReason'] != null)
                                  Text(
                                      'Move-out reason: ${h['moveOutReason']}'),
                              ],
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('Close'))
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                ],
                const Text('Add a past tenant',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  'For record-keeping only — this is saved immediately with no admin approval needed.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: _tenantName,
                    decoration:
                        const InputDecoration(labelText: 'Tenant name')),
                const SizedBox(height: 12),
                TextField(
                    controller: _tenantPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Tenant phone (10 digits)')),
                const SizedBox(height: 12),
                TextField(
                    controller: _tenantEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Tenant email (optional)')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: true),
                        child: Text(_startDate == null
                            ? 'Start date'
                            : dateFmt.format(_startDate!)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: false),
                        child: Text(_endDate == null
                            ? 'End date'
                            : dateFmt.format(_endDate!)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: _rentPerMonth,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Rent per month (Rs)')),
                const SizedBox(height: 12),
                TextField(
                    controller: _depositAmount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Deposit amount (Rs, optional)')),
                const SizedBox(height: 12),
                TextField(
                    controller: _moveOutReason,
                    decoration: const InputDecoration(
                        labelText: 'Move-out reason (optional)')),
                if (_formError != null) ...[
                  const SizedBox(height: 8),
                  Text(_formError!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save tenant history'),
                ),
              ],
            ),
    );
  }
}