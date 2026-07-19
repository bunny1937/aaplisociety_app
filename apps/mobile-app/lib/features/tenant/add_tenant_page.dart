import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_error.dart';
import 'document_upload_field.dart';
import 'tenant_api.dart';

class AddTenantPage extends StatefulWidget {
  const AddTenantPage({super.key});
  @override
  State<AddTenantPage> createState() => _AddTenantPageState();
}

class _AddTenantPageState extends State<AddTenantPage> {
  List _requests = [];
  bool _loading = true;

  final _tenantName = TextEditingController();
  final _tenantPhone = TextEditingController();
  final _tenantEmail = TextEditingController();
  final _rentPerMonth = TextEditingController();
  final _depositAmount = TextEditingController();
  DateTime? _leaseStart;
  DateTime? _leaseEnd;
  final Map<String, String> _documentKeys = {};
  String? _formError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dio = context.read<Dio>();
    final requests = await fetchTenantRequests(dio);
    if (mounted) setState(() { _requests = requests; _loading = false; });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() { if (isStart) {
      _leaseStart = picked;
    } else {
      _leaseEnd = picked;
    } });
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
    if (!_tenantEmail.text.trim().contains('@')) {
      setState(() => _formError = 'Enter a valid email address');
      return;
    }
    if (_leaseStart == null || _leaseEnd == null) {
      setState(() => _formError = 'Select the lease start and end dates');
      return;
    }
    if (rent == null || rent <= 0) {
      setState(() => _formError = 'Enter a valid monthly rent amount');
      return;
    }
    for (final config in tenantDocumentFields) {
      if (_documentKeys[config.field] == null) {
        setState(() => _formError = 'Upload the ${config.label}');
        return;
      }
    }

    setState(() { _submitting = true; _formError = null; });
    try {
      final dio = context.read<Dio>();
      await submitTenantRequest(dio, {
        'tenantName': _tenantName.text.trim(),
        'tenantPhone': _tenantPhone.text.trim(),
        'tenantEmail': _tenantEmail.text.trim(),
        'leaseStartDate': DateTime.utc(_leaseStart!.year, _leaseStart!.month, _leaseStart!.day).toIso8601String(),
        'leaseEndDate': DateTime.utc(_leaseEnd!.year, _leaseEnd!.month, _leaseEnd!.day).toIso8601String(),
        'rentPerMonth': rent,
        'depositAmount': num.tryParse(_depositAmount.text.trim()) ?? 0,
        'documents': {
          'contractKey': _documentKeys['contract'],
          'signatureKey': _documentKeys['signature'],
          'aadhaarKey': _documentKeys['aadhaar'],
          'policeVerificationKey': _documentKeys['policeVerification'],
        },
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tenant request submitted for admin approval')),
        );
      }
      await _load();
    } on DioException catch (err) {
      setState(() => _formError = apiErrorMessage(err));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _uploadDocument(String field, String filePath) async {
    final dio = context.read<Dio>();
    try {
      final key = await uploadTenantDocument(dio, field, filePath);
      setState(() => _documentKeys[field] = key);
    } on DioException catch (err) {
      setState(() => _formError = apiErrorMessage(err));
    }
  }

  @override
  void dispose() {
    _tenantName.dispose();
    _tenantPhone.dispose();
    _tenantEmail.dispose();
    _rentPerMonth.dispose();
    _depositAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Tenant')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_requests.isNotEmpty) ...[
                  const Text('Your requests', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  ..._requests.map((raw) {
                    final r = raw as Map;
                    return Card(
                      child: ListTile(
                        title: Text('${r['tenantName']}'),
                        subtitle: Text('${r['status']}'),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                ],
                const Text('Add a new tenant', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                TextField(controller: _tenantName, decoration: const InputDecoration(labelText: 'Tenant name')),
                const SizedBox(height: 12),
                TextField(controller: _tenantPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Tenant phone (10 digits)')),
                const SizedBox(height: 12),
                TextField(controller: _tenantEmail, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Tenant email')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: true),
                        child: Text(_leaseStart == null ? 'Lease start date' : _leaseStart!.toIso8601String().split('T').first),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: false),
                        child: Text(_leaseEnd == null ? 'Lease end date' : _leaseEnd!.toIso8601String().split('T').first),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: _rentPerMonth, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rent per month (Rs)')),
                const SizedBox(height: 12),
                TextField(controller: _depositAmount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Deposit amount (Rs, optional)')),
                const SizedBox(height: 16),
                const Text('Documents', style: TextStyle(fontWeight: FontWeight.w700)),
                ...tenantDocumentFields.map((config) => DocumentUploadField(
                      config: config,
                      onPicked: (path) => _uploadDocument(config.field, path),
                    )),
                if (_formError != null) ...[
                  const SizedBox(height: 8),
                  Text(_formError!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Submit request'),
                ),
              ],
            ),
    );
  }
}
