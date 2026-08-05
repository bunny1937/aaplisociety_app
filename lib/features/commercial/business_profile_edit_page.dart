import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_error.dart';
import 'data/commercial_api.dart';
import 'models/business_profile.dart';
import 'models/commercial_category.dart';

/// Owner self-service edit.
///
/// Client validation here exists for UX only - the server re-validates
/// everything and is the authority. The write is online-only and is never
/// queued in OfflineOutbox: a public listing must not be changed from a stale
/// device state.
class BusinessProfileEditPage extends StatefulWidget {
  const BusinessProfileEditPage({super.key});

  @override
  State<BusinessProfileEditPage> createState() => _BusinessProfileEditPageState();
}

class _BusinessProfileEditPageState extends State<BusinessProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _tradeName = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();
  final _gstin = TextEditingController();
  final _licence = TextEditingController();

  List<CommercialCategory> _cats = const [];
  String? _categoryId;
  final Set<String> _modes = {};
  String? _expectedUpdatedAt;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [_tradeName, _description, _phone, _whatsapp, _email, _gstin, _licence]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await CommercialApi(context.read<Dio>()).myBusiness();
      final raw = data['profile'];
      if (!mounted) return;
      if (raw == null) {
        setState(() {
          _loading = false;
          _error = 'There is no listing to edit yet.';
        });
        return;
      }
      final p = BusinessProfile.fromJson(Map.from(raw as Map));
      setState(() {
        _tradeName.text = p.tradeName;
        _description.text = p.description ?? '';
        _phone.text = p.phone ?? '';
        _whatsapp.text = p.whatsapp ?? '';
        _email.text = p.email ?? '';
        _gstin.text = p.gstin ?? '';
        _licence.text = p.licenseNumber ?? '';
        _categoryId = p.categoryId;
        _modes.addAll(p.fulfillmentModes);
        _expectedUpdatedAt = p.updatedAt;
        _cats = CommercialCategory.listFrom(data['categories']);
        _loading = false;
      });
    } on DioException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(err, 'Could not open the editor');
      });
    }
  }

  String? _orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await CommercialApi(context.read<Dio>()).updateMyBusiness(
        {
          'tradeName': _tradeName.text.trim(),
          if (_categoryId != null) 'categoryId': _categoryId,
          'description': _orNull(_description),
          'phone': _orNull(_phone),
          'whatsapp': _orNull(_whatsapp),
          'email': _orNull(_email),
          'gstin': _orNull(_gstin),
          'licenseNumber': _orNull(_licence),
          'fulfillmentModes': _modes.toList(),
        },
        expectedUpdatedAt: _expectedUpdatedAt,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (err) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = err.response?.statusCode == 409
            ? 'This listing changed while you were editing. Reopen the editor and try again.'
            : apiErrorMessage(err, 'Could not save your changes');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit business')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
                    ),
                  _field(_tradeName, 'Trade name', required: true),
                  DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final c in _cats.where((c) => c.isActive))
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                    validator: (v) => (v == null || v.isEmpty) ? 'Choose a category' : null,
                  ),
                  const SizedBox(height: 8),
                  _field(_description, 'Description', maxLines: 4),
                  _field(_phone, 'Phone', keyboard: TextInputType.phone),
                  _field(_whatsapp, 'WhatsApp', keyboard: TextInputType.phone),
                  _field(_email, 'Email', keyboard: TextInputType.emailAddress),
                  _field(_gstin, 'GSTIN', validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    return v.trim().length == 15 ? null : 'GSTIN must be 15 characters';
                  }),
                  _field(_licence, 'Licence number'),
                  const SizedBox(height: 12),
                  Text('How customers reach you', style: Theme.of(context).textTheme.titleSmall),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in const ['WalkIn', 'Pickup', 'ShopDelivery'])
                        FilterChip(
                          label: Text(switch (m) {
                            'WalkIn' => 'Walk-in',
                            'Pickup' => 'Pickup',
                            _ => 'Shop delivery',
                          }),
                          selected: _modes.contains(m),
                          onSelected: (on) => setState(() {
                            if (on) {
                              _modes.add(m);
                            } else {
                              _modes.remove(m);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Save changes'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
        validator: validator ??
            (required
                ? (v) => (v == null || v.trim().length < 2) ? '$label is required' : null
                : null),
      ),
    );
  }
}
