import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_error.dart';
import '../pulse/pulse.dart';
import 'profile_edit_api.dart';
import 'profile_section_widgets.dart';

final _phoneRe = RegExp(r'^[0-9]{10}$');

class ContactPage extends StatefulWidget {
  final Map? member;
  final String? email;
  final bool canEdit;
  final bool embedded;
  const ContactPage(
      {super.key,
      required this.member,
      this.email,
      required this.canEdit,
      this.embedded = false});
  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  List _requests = [];
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dio = context.read<Dio>();
    try {
      final requests = await fetchProfileEditRequests(dio);
      if (mounted) {
        setState(() {
          _requests = requests;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map? get _pending {
    for (final r in _requests) {
      final m = r as Map;
      if (m['section'] == 'Contact' && m['status'] == 'Pending') return m;
    }
    return null;
  }

  Future<void> _editContact() async {
    final contactNumber = TextEditingController(
        text: widget.member?['contactNumber']?.toString() ?? '');
    final whatsappNumber = TextEditingController(
        text: widget.member?['whatsappNumber']?.toString() ?? '');
    final alternateContact = TextEditingController(
        text: widget.member?['alternateContact']?.toString() ?? '');
    final submitted = await showPulseSheet<bool>(
      context,
      title: 'Edit contact',
      builder: (sheetCtx) => _ContactForm(
        contactNumber: contactNumber,
        whatsappNumber: whatsappNumber,
        alternateContact: alternateContact,
      ),
    );
    if (submitted == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final pending = _pending;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final body = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ProfileInfoRow(label: 'Email', value: widget.email),
        ProfileInfoRow(
            label: 'Phone', value: widget.member?['contactNumber']?.toString()),
        if (pending?['payload']?['contactNumber'] != null)
          PendingChangeNote(
              text:
                  'Change to ${pending!['payload']['contactNumber']} — pending approval'),
        ProfileInfoRow(
            label: 'WhatsApp',
            value: widget.member?['whatsappNumber']?.toString()),
        if (pending?['payload']?['whatsappNumber'] != null)
          PendingChangeNote(
              text:
                  'Change to ${pending!['payload']['whatsappNumber']} — pending approval'),
        ProfileInfoRow(
            label: 'Alternate',
            value: widget.member?['alternateContact']?.toString()),
        if (pending?['payload']?['alternateContact'] != null)
          PendingChangeNote(
              text:
                  'Change to ${pending!['payload']['alternateContact']} — pending approval'),
        const SizedBox(height: 20),
        if (widget.canEdit)
          pending != null
              ? Text('A contact change is awaiting admin approval',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: t.fg4,
                      fontStyle: FontStyle.italic))
              : PulseButton(
                  label: 'Edit contact',
                  icon: Icons.edit_outlined,
                  onTap: _editContact),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Contact')), body: body);
  }
}

class _ContactForm extends StatefulWidget {
  final TextEditingController contactNumber;
  final TextEditingController whatsappNumber;
  final TextEditingController alternateContact;
  const _ContactForm(
      {required this.contactNumber,
      required this.whatsappNumber,
      required this.alternateContact});
  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  String? _error;
  bool _submitting = false;
  Future<void> _submit() async {
    final payload = <String, dynamic>{};
    for (final entry in {
      'contactNumber': widget.contactNumber.text.trim(),
      'whatsappNumber': widget.whatsappNumber.text.trim(),
      'alternateContact': widget.alternateContact.text.trim(),
    }.entries) {
      if (entry.value.isEmpty) continue;
      if (!_phoneRe.hasMatch(entry.value)) {
        setState(
            () => _error = 'Enter a valid 10-digit number for ${entry.key}');
        return;
      }
      payload[entry.key] = entry.value;
    }
    if (payload.isEmpty) {
      setState(() => _error = 'Change at least one field');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final dio = context.read<Dio>();
      await submitProfileEditRequest(
          dio, {'section': 'Contact', 'action': 'Edit', 'payload': payload});
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
        TextField(
            controller: widget.contactNumber,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (10 digits)')),
        const SizedBox(height: 12),
        TextField(
            controller: widget.whatsappNumber,
            keyboardType: TextInputType.phone,
            decoration:
                const InputDecoration(labelText: 'WhatsApp (10 digits)')),
        const SizedBox(height: 12),
        TextField(
            controller: widget.alternateContact,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Alternate contact (10 digits)')),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 20),
        PulseButton(
            label: 'Submit for approval',
            full: true,
            loading: _submitting,
            onTap: _submit),
      ],
    );
  }
}
