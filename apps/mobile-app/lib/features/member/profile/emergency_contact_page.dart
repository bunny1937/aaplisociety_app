import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_error.dart';
import '../pulse/pulse.dart';
import 'profile_edit_api.dart';
import 'profile_section_widgets.dart';

final _phoneRe = RegExp(r'^[0-9]{10}$');

class EmergencyContactPage extends StatefulWidget {
  final Map? member;
  final bool canEdit;
  const EmergencyContactPage({super.key, required this.member, required this.canEdit});

  @override
  State<EmergencyContactPage> createState() => _EmergencyContactPageState();
}

class _EmergencyContactPageState extends State<EmergencyContactPage> {
  List _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dio = context.read<Dio>();
    final requests = await fetchProfileEditRequests(dio);
    if (mounted) setState(() { _requests = requests; _loading = false; });
  }

  Map? get _pending {
    for (final r in _requests) {
      final m = r as Map;
      if (m['section'] == 'EmergencyContact' && m['status'] == 'Pending') return m;
    }
    return null;
  }

  Future<void> _edit() async {
    final current = widget.member?['emergencyContact'] as Map?;
    final name = TextEditingController(text: current?['name']?.toString() ?? '');
    final phoneNumber = TextEditingController(text: current?['phoneNumber']?.toString() ?? '');
    final relation = TextEditingController(text: current?['relation']?.toString() ?? '');
    final address = TextEditingController(text: current?['address']?.toString() ?? '');

    final submitted = await showPulseSheet<bool>(
      context,
      title: 'Edit emergency contact',
      builder: (sheetCtx) => _EmergencyContactForm(name: name, phoneNumber: phoneNumber, relation: relation, address: address),
    );
    if (submitted == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final pending = _pending;
    final current = widget.member?['emergencyContact'] as Map?;
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency contact')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ProfileInfoRow(label: 'Name', value: current?['name']?.toString()),
                ProfileInfoRow(label: 'Phone', value: current?['phoneNumber']?.toString()),
                ProfileInfoRow(label: 'Relation', value: current?['relation']?.toString()),
                ProfileInfoRow(label: 'Address', value: current?['address']?.toString()),
                if (pending != null)
                  PendingChangeNote(
                    text: 'Change to ${pending['payload']?['name']} (${pending['payload']?['relation']}, ${pending['payload']?['phoneNumber']}) — pending approval',
                  ),
                const SizedBox(height: 20),
                if (widget.canEdit)
                  pending != null
                      ? Text('An emergency contact change is awaiting admin approval', style: TextStyle(fontSize: 12.5, color: t.fg4, fontStyle: FontStyle.italic))
                      : PulseButton(label: 'Edit emergency contact', icon: Icons.edit_outlined, onTap: _edit),
              ],
            ),
    );
  }
}

class _EmergencyContactForm extends StatefulWidget {
  final TextEditingController name;
  final TextEditingController phoneNumber;
  final TextEditingController relation;
  final TextEditingController address;
  const _EmergencyContactForm({required this.name, required this.phoneNumber, required this.relation, required this.address});

  @override
  State<_EmergencyContactForm> createState() => _EmergencyContactFormState();
}

class _EmergencyContactFormState extends State<_EmergencyContactForm> {
  String? _error;
  bool _submitting = false;

  Future<void> _submit() async {
    if (widget.name.text.trim().length < 2) {
      setState(() => _error = 'Enter a name');
      return;
    }
    if (!_phoneRe.hasMatch(widget.phoneNumber.text.trim())) {
      setState(() => _error = 'Enter a valid 10-digit phone number');
      return;
    }
    if (widget.relation.text.trim().isEmpty) {
      setState(() => _error = 'Enter the relation (e.g. Spouse, Parent)');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      final dio = context.read<Dio>();
      await submitProfileEditRequest(dio, {
        'section': 'EmergencyContact',
        'action': 'Edit',
        'payload': {
          'name': widget.name.text.trim(),
          'phoneNumber': widget.phoneNumber.text.trim(),
          'relation': widget.relation.text.trim(),
          if (widget.address.text.trim().isNotEmpty) 'address': widget.address.text.trim(),
        },
      });
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (err) {
      setState(() => _error = apiErrorMessage(err));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(controller: widget.name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        TextField(controller: widget.phoneNumber, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (10 digits)')),
        const SizedBox(height: 12),
        TextField(controller: widget.relation, decoration: const InputDecoration(labelText: 'Relation (e.g. Spouse, Parent)')),
        const SizedBox(height: 12),
        TextField(controller: widget.address, decoration: const InputDecoration(labelText: 'Address (optional)')),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 20),
        PulseButton(label: 'Submit for approval', full: true, loading: _submitting, onTap: _submit),
      ],
    );
  }
}
