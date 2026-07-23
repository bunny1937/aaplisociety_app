import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_error.dart';
import '../pulse/pulse.dart';
import 'profile_edit_api.dart';
import 'profile_section_widgets.dart';

class FamilyMembersPage extends StatefulWidget {
  final List<Map> members;
  final bool canEdit;
  final bool embedded;
  const FamilyMembersPage(
      {super.key,
      required this.members,
      required this.canEdit,
      this.embedded = false});
  @override
  State<FamilyMembersPage> createState() => _FamilyMembersPageState();
}

class _FamilyMembersPageState extends State<FamilyMembersPage> {
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

  List get _familyRequests => _requests
      .where((r) =>
          (r as Map)['section'] == 'FamilyMember' && r['status'] == 'Pending')
      .toList();
  Map? _pendingFor(String familyMemberId) {
    for (final r in _familyRequests) {
      final m = r as Map;
      if (m['action'] != 'Add' && '${m['familyMemberId']}' == familyMemberId) {
        return m;
      }
    }
    return null;
  }

  List get _pendingAdds =>
      _familyRequests.where((r) => (r as Map)['action'] == 'Add').toList();
  Future<void> _openForm(
      {Map? existing, required String action, String? familyMemberId}) async {
    final name =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final relation =
        TextEditingController(text: existing?['relation']?.toString() ?? '');
    final age = TextEditingController(text: existing?['age']?.toString() ?? '');
    final contactNumber = TextEditingController(
        text: existing?['contactNumber']?.toString() ?? '');
    final occupation =
        TextEditingController(text: existing?['occupation']?.toString() ?? '');
    final submitted = await showPulseSheet<bool>(
      context,
      title: action == 'Add' ? 'Add family member' : 'Edit family member',
      builder: (sheetCtx) => _FamilyMemberForm(
        action: action,
        familyMemberId: familyMemberId,
        name: name,
        relation: relation,
        age: age,
        contactNumber: contactNumber,
        occupation: occupation,
      ),
    );
    if (submitted == true && mounted) await _load();
  }

  Future<void> _remove(String familyMemberId, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove family member?'),
        content: Text(
            'This submits a request to remove $label — it takes effect once an admin approves it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final dio = context.read<Dio>();
      await submitProfileEditRequest(dio, {
        'section': 'FamilyMember',
        'action': 'Remove',
        'familyMemberId': familyMemberId
      });
      await _load();
    } on DioException catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(err))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final body = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.members.isEmpty && _pendingAdds.isEmpty)
          Text('Not available yet',
              style: TextStyle(
                  fontSize: 13.5, color: t.fg5, fontStyle: FontStyle.italic)),
        ...widget.members.map((m) {
          final familyMemberId = '${m['_id']}';
          final pending = _pendingFor(familyMemberId);
          final sub = [
            m['relation'],
            m['age'] != null ? '${m['age']} yrs' : null
          ].where((v) => v != null && '$v'.isNotEmpty).join(' · ');
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PulseCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${m['name'] ?? '—'}',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: t.fg1)),
                            if (sub.isNotEmpty)
                              Text(sub,
                                  style:
                                      TextStyle(fontSize: 11.5, color: t.fg4)),
                          ],
                        ),
                      ),
                      if (widget.canEdit && pending == null) ...[
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 19),
                          onPressed: () => _openForm(
                              existing: m,
                              action: 'Edit',
                              familyMemberId: familyMemberId),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 19, color: Colors.red),
                          onPressed: () =>
                              _remove(familyMemberId, '${m['name']}'),
                        ),
                      ],
                    ],
                  ),
                  if (pending != null)
                    PendingChangeNote(
                      text: pending['action'] == 'Remove'
                          ? 'Removal pending approval'
                          : 'Change to ${pending['payload']?['name']} — pending approval',
                    ),
                ],
              ),
            ),
          );
        }),
        ..._pendingAdds.map((r) {
          final m = r as Map;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PulseCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, size: 16, color: t.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${m['payload']?['name']} — pending approval',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: t.fg1),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        if (widget.canEdit) ...[
          const SizedBox(height: 10),
          PulseButton(
            label: 'Add family member',
            icon: Icons.person_add_alt_1_outlined,
            variant: PulseBtnVariant.secondary,
            full: true,
            onTap: () => _openForm(action: 'Add'),
          ),
        ],
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
        appBar: AppBar(title: const Text('Family members')), body: body);
  }
}

class _FamilyMemberForm extends StatefulWidget {
  final String action;
  final String? familyMemberId;
  final TextEditingController name;
  final TextEditingController relation;
  final TextEditingController age;
  final TextEditingController contactNumber;
  final TextEditingController occupation;
  const _FamilyMemberForm({
    required this.action,
    this.familyMemberId,
    required this.name,
    required this.relation,
    required this.age,
    required this.contactNumber,
    required this.occupation,
  });
  @override
  State<_FamilyMemberForm> createState() => _FamilyMemberFormState();
}

class _FamilyMemberFormState extends State<_FamilyMemberForm> {
  String? _error;
  bool _submitting = false;
  Future<void> _submit() async {
    if (widget.name.text.trim().length < 2) {
      setState(() => _error = 'Enter a name');
      return;
    }
    if (widget.relation.text.trim().isEmpty) {
      setState(() => _error = 'Enter the relation (e.g. Spouse, Child)');
      return;
    }
    final age = int.tryParse(widget.age.text.trim());
    final contactNumber = widget.contactNumber.text.trim();
    if (contactNumber.isNotEmpty &&
        !RegExp(r'^[0-9]{10}$').hasMatch(contactNumber)) {
      setState(() =>
          _error = 'Enter a valid 10-digit phone number, or leave it blank');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final dio = context.read<Dio>();
      final body = <String, dynamic>{
        'section': 'FamilyMember',
        'action': widget.action,
        'payload': {
          'name': widget.name.text.trim(),
          'relation': widget.relation.text.trim(),
          if (age != null && age > 0) 'age': age,
          if (contactNumber.isNotEmpty) 'contactNumber': contactNumber,
          if (widget.occupation.text.trim().isNotEmpty)
            'occupation': widget.occupation.text.trim(),
        },
      };
      if (widget.familyMemberId != null) {
        body['familyMemberId'] = widget.familyMemberId;
      }
      await submitProfileEditRequest(dio, body);
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
            controller: widget.name,
            decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        TextField(
            controller: widget.relation,
            decoration: const InputDecoration(
                labelText: 'Relation (e.g. Spouse, Child)')),
        const SizedBox(height: 12),
        TextField(
            controller: widget.age,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Age (optional)')),
        const SizedBox(height: 12),
        TextField(
            controller: widget.contactNumber,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Phone (optional, 10 digits)')),
        const SizedBox(height: 12),
        TextField(
            controller: widget.occupation,
            decoration:
                const InputDecoration(labelText: 'Occupation (optional)')),
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
