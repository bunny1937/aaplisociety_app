import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_error.dart';
import '../../../core/theme/haptics.dart';
import '../pulse/pulse.dart';
import 'profile_edit_api.dart';
import 'profile_section_widgets.dart';

final _phoneRe = RegExp(r'^[0-9]{10}$');

/// Tenant's own details page.
///
/// Previously a tenant tapping "Basic details" was routed straight into the
/// owner's record: they saw the owner's PAN, contacts and family members and
/// nothing at all about their own tenancy. That was both useless and a privacy
/// leak. This page shows the tenant THEIR data - identity, lease, rent,
/// deposit and who their owner is - laid out exactly like the owner's version,
/// and keeps the shared flat information one tap away in read-only form.
class TenantDetailsPage extends StatefulWidget {
  const TenantDetailsPage({
    super.key,
    required this.user,
    required this.member,
    required this.flatNo,
    required this.wing,
    required this.email,
    required this.societyName,
    required this.parkingSlots,
    required this.familyMembers,
  });

  final Map user;
  final Map? member;
  final String? flatNo;
  final String? wing;
  final String? email;
  final String? societyName;
  final List<Map> parkingSlots;
  final List<Map> familyMembers;

  @override
  State<TenantDetailsPage> createState() => _TenantDetailsPageState();
}

class _TenantDetailsPageState extends State<TenantDetailsPage> {
  List _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    final dio = context.read<Dio>();
    try {
      final requests = await fetchProfileEditRequests(dio);
      if (mounted) setState(() => _requests = requests);
    } catch (_) {
      // Non-fatal — page still shows current values without pending-change notes.
    }
  }

  Map? get _pending {
    for (final r in _requests) {
      final m = r as Map;
      if (m['section'] == 'TenantContact' && m['status'] == 'Pending') return m;
    }
    return null;
  }

  Future<void> _editContact(Map tenant) async {
    final contactNumber = TextEditingController(
        text: (tenant['contactNumber'] ?? '').toString());
    final email = TextEditingController(text: (tenant['email'] ?? '').toString());
    final submitted = await showPulseSheet<bool>(
      context,
      title: 'Request contact change',
      builder: (sheetCtx) => _TenantContactForm(
        contactNumber: contactNumber,
        email: email,
      ),
    );
    if (submitted == true && mounted) await _loadRequests();
  }

  static String _d(dynamic raw) {
    final d = DateTime.tryParse('$raw');
    if (d == null) return '\u2014';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static String _v(dynamic raw) {
    final s = '${raw ?? ''}'.trim();
    return s.isEmpty || s == 'null' ? '\u2014' : s;
  }

  static String _money(dynamic raw) {
    final n = raw is num ? raw : num.tryParse('${raw ?? ''}');
    if (n == null) return '\u2014';
    return 'Rs ${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final member = widget.member;
    final user = widget.user;
    final flatNo = widget.flatNo;
    final wing = widget.wing;
    final email = widget.email;
    final societyName = widget.societyName;
    final pending = _pending;
    final tenant = (member?['currentTenant'] as Map?) ?? const {};
    final name = _v(tenant['name'] ?? user['name'] ?? user['username']);
    // API (TenantHistorySchema) field names: contactNumber, panCard, aadhaar,
    // startDate, endDate, rentPerMonth — NOT the phoneNumber/panNumber/
    // leaseStartDate/leaseEndDate/rentAmount names this page used to read,
    // which is why every field below rendered as "—" despite the backend
    // actually having the data.
    final leaseEnd = tenant['endDate'];
    final expired = () {
      final d = DateTime.tryParse('$leaseEnd');
      return d != null && d.isBefore(DateTime.now());
    }();

    return Scaffold(
      backgroundColor: t.canvas,
      appBar: AppBar(
        title: const Text('My details'),
        backgroundColor: t.canvas,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // Identity banner, same shape as the owner header.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.brand, t.brand2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(PulseTokens.radius),
            ),
            child: Row(
              children: [
                PulseAvatar(name: name, size: 46, ring: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tenant \u00b7 ${wing != null && wing!.isNotEmpty ? '$wing-' : ''}${_v(flatNo)}'
                        '${societyName != null ? ' \u00b7 $societyName' : ''}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (expired)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.warningSoft,
                borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
              ),
              child: Text(
                'Your lease end date has passed. Ask your owner to extend it or '
                'confirm move-out.',
                style: TextStyle(
                    fontSize: 12.5,
                    color: t.warning,
                    fontWeight: FontWeight.w700),
              ),
            ),

          _Section(title: 'My tenancy', rows: [
            ('Name', name),
            ('Phone', _v(tenant['contactNumber'] ?? tenant['phoneNumber'] ?? tenant['phone'] ?? user['phone'])),
            ('Email', _v(tenant['email'] ?? email)),
            ('PAN', _v(tenant['panCard'] ?? tenant['panNumber'] ?? tenant['pan'])),
            ('Aadhaar', _v(tenant['aadhaar'] ?? tenant['aadhaarNumber'])),
          ]),
          if (pending?['payload']?['contactNumber'] != null ||
              pending?['payload']?['email'] != null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: PendingChangeNote(
                  text: 'Contact change awaiting owner/admin approval'),
            ),
          if (tenant.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: pending != null
                  ? Text('A contact change is awaiting admin approval',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: t.fg4,
                          fontStyle: FontStyle.italic))
                  : PulseButton(
                      label: 'Request contact change',
                      icon: Icons.edit_outlined,
                      onTap: () => _editContact(tenant),
                    ),
            ),

          _Section(title: 'Lease', rows: [
            ('Start date', _d(tenant['startDate'] ?? tenant['leaseStartDate'])),
            ('End date', leaseEnd == null ? 'Open ended' : _d(leaseEnd)),
            ('Monthly rent', _money(tenant['rentPerMonth'] ?? tenant['rentAmount'])),
            ('Security deposit', _money(tenant['depositAmount'])),
            ('Status', expired ? 'Lease ended' : 'Active'),
          ]),

          _Section(title: 'Flat & owner', rows: [
            ('Flat', '${wing != null && wing!.isNotEmpty ? '$wing-' : ''}${_v(flatNo)}'),
            ('Floor', _v(member?['floor'])),
            ('Carpet area', member?['areaSqFt'] == null
                ? '\u2014'
                : '${member?['areaSqFt']} sq ft'),
            ('Society', _v(societyName)),
            ('Owner', _v(member?['ownerName'])),
            ('Owner phone', _v(member?['contactNumber'] ?? member?['ownerPhone'] ?? member?['phoneNumber'])),
          ]),

          const SizedBox(height: 8),
          // Shared, flat-level information stays viewable but read-only: a
          // tenant may need the parking slot or emergency contact, but must
          // never be able to edit the owner's record.
          InkWell(
            borderRadius: BorderRadius.circular(PulseTokens.radius),
            onTap: () {
              Haptics.light();
              context.push('/profile/basic-details', extra: {
                'member': member,
                'flatNo': flatNo,
                'wing': wing,
                'email': email,
                'canEdit': false,
                'parkingSlots': widget.parkingSlots,
                'familyMembers': widget.familyMembers,
              });
            },
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(PulseTokens.radius),
                border: Border.all(color: t.hairline),
              ),
              child: Row(
                children: [
                  Icon(Icons.apartment_rounded, size: 20, color: t.fg3),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Flat, parking & emergency info',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: t.fg1)),
                        const SizedBox(height: 2),
                        Text('Read only',
                            style: TextStyle(fontSize: 11.5, color: t.fg4)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: t.fg4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TenantContactForm extends StatefulWidget {
  final TextEditingController contactNumber;
  final TextEditingController email;
  const _TenantContactForm({required this.contactNumber, required this.email});
  @override
  State<_TenantContactForm> createState() => _TenantContactFormState();
}

class _TenantContactFormState extends State<_TenantContactForm> {
  String? _error;
  bool _submitting = false;

  Future<void> _submit() async {
    final payload = <String, dynamic>{};
    final phone = widget.contactNumber.text.trim();
    final email = widget.email.text.trim();
    if (phone.isNotEmpty) {
      if (!_phoneRe.hasMatch(phone)) {
        setState(() => _error = 'Enter a valid 10-digit phone number');
        return;
      }
      payload['contactNumber'] = phone;
    }
    if (email.isNotEmpty) payload['email'] = email;
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
      await submitProfileEditRequest(dio,
          {'section': 'TenantContact', 'action': 'Edit', 'payload': payload});
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
            controller: widget.email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email')),
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(PulseTokens.radius),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: t.fg1,
                  letterSpacing: -0.2)),
          const SizedBox(height: 10),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 128,
                    child: Text(r.$1,
                        style: TextStyle(fontSize: 12.5, color: t.fg4)),
                  ),
                  Expanded(
                    child: Text(
                      r.$2,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: t.fg2,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
