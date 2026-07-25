import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_error.dart';
import '../../core/widgets/app_toast.dart';
import '../member/bills_page.dart' show inr;
import 'tenant_api.dart';

/// The owner's single place to actually MANAGE a tenancy — not a read-only
/// details dialog. Active / ended tenancies, lease actions (end, abort, date
/// change), missing documents, notes, rent records and reminders all live here.
class MyTenantPage extends StatefulWidget {
  const MyTenantPage({super.key});
  @override
  State<MyTenantPage> createState() => _MyTenantPageState();
}

class _MyTenantPageState extends State<MyTenantPage> {
  bool _loading = true;
  String? _error;
  List _tenancies = const [];
  List _rent = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dio = context.read<Dio>();
    setState(() { _loading = true; _error = null; });
    try {
      final tenancies = await fetchTenantHistory(dio);
      final rent = await fetchRentPayments(dio);
      if (!mounted) return;
      setState(() { _tenancies = tenancies; _rent = rent; _loading = false; });
    } catch (err) {
      if (!mounted) return;
      setState(() { _error = apiErrorMessage(err); _loading = false; });
    }
  }

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    try {
      await action();
      if (!mounted) return;
      showAppToast(context, okMsg);
      await _load();
    } catch (err) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    }
  }

  Future<String?> _prompt(String title, {String? hint, String? initial}) async {
    final c = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dio = context.read<Dio>();
    final active = _tenancies.where((t) => t['_section'] == 'current').toList();
    final past = _tenancies.where((t) => t['_section'] != 'current').toList();
    final pendingRent = _rent.where((r) => (r['status'] ?? 'Confirmed') == 'Pending').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tenant'),
        actions: [
          IconButton(
              tooltip: 'Manage tenants',
              icon: const Icon(Icons.manage_accounts_rounded),
              onPressed: () => context.push('/manage-tenants')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      if (pendingRent.isNotEmpty) ...[
                        const _SectionTitle('Awaiting your confirmation'),
                        ...pendingRent.map((r) => _RentTile(
                              rent: r,
                              onConfirm: () => _run(
                                  () => confirmRentPayment(dio, '${r['_id']}', true).then((_) {}),
                                  'Rent payment confirmed'),
                              onReject: () async {
                                final reason = await _prompt('Reject rent payment', hint: 'Reason shown to the tenant');
                                if (reason == null) return;
                                await _run(
                                    () => confirmRentPayment(dio, '${r['_id']}', false, reason: reason).then((_) {}),
                                    'Rent payment rejected');
                              },
                            )),
                        const SizedBox(height: 8),
                      ],
                      const _SectionTitle('Active tenancy'),
                      if (active.isEmpty)
                        const _Empty('No active tenant. Add one from Manage Tenants.')
                      else
                        ...active.map((t) => _TenancyCard(
                              tenancy: t,
                              active: true,
                              onEndLease: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (d) => AlertDialog(
                                    title: const Text('End this lease?'),
                                    content: const Text(
                                        'This marks the tenancy as ended, disables the tenant login after admin confirmation, and moves the record to Past tenants.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('End lease')),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                await _run(() => endLease(dio, '${t['_id']}').then((_) {}), 'Lease ended — sent for admin confirmation');
                              },
                              onEditDates: () async {
                                final v = await _prompt('New lease end date (YYYY-MM-DD)', hint: '2026-12-31');
                                if (v == null || v.isEmpty) return;
                                await _run(
                                    () => requestLeaseDateChange(dio, '${t['_id']}', {'leaseEndDate': v}).then((_) {}),
                                    'Lease date change sent for approval');
                              },
                              onNote: () async {
                                final v = await _prompt('Add a note', hint: 'Visible to you and the admin');
                                if (v == null || v.isEmpty) return;
                                await _run(() => addTenantNote(dio, '${t['_id']}', v).then((_) {}), 'Note added');
                              },
                              onRemind: () async {
                                final rentAmt = (t['rentPerMonth'] as num?) ?? 0;
                                final now = DateTime.now();
                                final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
                                await _run(() => sendRentReminder(dio, month: month, amount: rentAmt), 'Rent reminder sent to your tenant');
                              },
                              onAbort: null,
                            )),
                      const SizedBox(height: 14),
                      const _SectionTitle('Rent records'),
                      if (_rent.isEmpty)
                        const _Empty('No rent payments recorded yet.')
                      else
                        ..._rent.map((r) => _RentTile(
                              rent: r,
                              onDelete: () => _run(() => deleteRentPayment(dio, '${r['_id']}'), 'Rent record deleted'),
                              onEdit: () async {
                                final v = await _prompt('Edit amount', initial: '${r['amount']}');
                                final amt = num.tryParse(v ?? '');
                                if (amt == null) return;
                                await _run(
                                    () => updateRentPayment(dio, '${r['_id']}', {'amount': amt}).then((_) {}),
                                    'Rent record updated');
                              },
                            )),
                      const SizedBox(height: 14),
                      const _SectionTitle('Past tenants'),
                      if (past.isEmpty)
                        const _Empty('No past tenancies.')
                      else
                        ...past.map((t) => _TenancyCard(tenancy: t, active: false)),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text, style: TextStyle(color: Theme.of(context).hintColor)),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 34, color: Colors.red),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}

/// Full tenancy card with an Active / Ended badge and real management actions.
class _TenancyCard extends StatelessWidget {
  final Map tenancy;
  final bool active;
  final VoidCallback? onEndLease;
  final VoidCallback? onEditDates;
  final VoidCallback? onNote;
  final VoidCallback? onRemind;
  final VoidCallback? onAbort;
  const _TenancyCard({
    required this.tenancy,
    required this.active,
    this.onEndLease,
    this.onEditDates,
    this.onNote,
    this.onRemind,
    this.onAbort,
  });

  @override
  Widget build(BuildContext context) {
    final status = '${tenancy['status'] ?? (active ? 'Active' : 'Ended')}';
    final docs = (tenancy['documents'] as Map?) ?? const {};
    final missing = <String>[
      if (docs['contractKey'] == null) 'Lease contract',
      if (docs['signatureKey'] == null) 'Signature',
      if (docs['aadhaarKey'] == null) 'Aadhaar',
      if (docs['policeVerificationKey'] == null) 'Police verification',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('${tenancy['tenantName'] ?? tenancy['name'] ?? 'Tenant'}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: active ? Colors.green.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(active ? 'ACTIVE' : status.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: active ? Colors.green.shade800 : Colors.grey.shade700)),
              ),
            ]),
            const SizedBox(height: 6),
            _kv('Phone', '${tenancy['tenantPhone'] ?? tenancy['phone'] ?? '—'}'),
            _kv('Email', '${tenancy['tenantEmail'] ?? tenancy['email'] ?? '—'}'),
            _kv('Rent', inr((tenancy['rentPerMonth'] as num?) ?? 0)),
            _kv('Deposit', inr((tenancy['depositAmount'] as num?) ?? 0)),
            _kv('Lease', '${_d(tenancy['leaseStartDate'])} → ${_d(tenancy['leaseEndDate']) == '—' ? 'ongoing' : _d(tenancy['leaseEndDate'])}'),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('Missing documents: ${missing.join(', ')}',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
              ),
            ],
            if (active) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (onRemind != null)
                  OutlinedButton.icon(
                      onPressed: onRemind, icon: const Icon(Icons.notifications_active_outlined, size: 16), label: const Text('Rent reminder')),
                if (onEditDates != null)
                  OutlinedButton.icon(
                      onPressed: onEditDates, icon: const Icon(Icons.edit_calendar_outlined, size: 16), label: const Text('Lease dates')),
                if (onNote != null)
                  OutlinedButton.icon(onPressed: onNote, icon: const Icon(Icons.note_add_outlined, size: 16), label: const Text('Add note')),
                if (onEndLease != null)
                  FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                      onPressed: onEndLease,
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: const Text('End lease')),
                if (onAbort != null)
                  TextButton(onPressed: onAbort, child: const Text('Abort request')),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  static String _d(dynamic v) {
    if (v == null) return '—';
    final p = DateTime.tryParse('$v');
    if (p == null) return '$v';
    return '${p.day}/${p.month}/${p.year}';
  }

  static Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 82, child: Text(k, style: const TextStyle(fontSize: 12.5, color: Colors.grey))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
        ]),
      );
}

class _RentTile extends StatelessWidget {
  final Map rent;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _RentTile({required this.rent, this.onConfirm, this.onReject, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final status = '${rent['status'] ?? 'Confirmed'}';
    final pending = status == 'Pending';
    final rejected = status == 'Rejected';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('${inr((rent['amount'] as num?) ?? 0)} · ${rent['month'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(
            '${rent['paymentMode'] ?? ''} · $status${rent['submittedByRole'] == 'Tenant' ? ' · submitted by tenant' : ''}',
            style: TextStyle(
                fontSize: 12,
                color: pending ? Colors.orange.shade800 : (rejected ? Colors.red : Colors.green.shade700),
                fontWeight: FontWeight.w600)),
        trailing: Wrap(spacing: 2, children: [
          if (onConfirm != null)
            IconButton(tooltip: 'Confirm', icon: const Icon(Icons.check_circle_outline, color: Colors.green), onPressed: onConfirm),
          if (onReject != null)
            IconButton(tooltip: 'Reject', icon: const Icon(Icons.cancel_outlined, color: Colors.red), onPressed: onReject),
          if (onEdit != null) IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
          if (onDelete != null) IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
        ]),
      ),
    );
  }
}
