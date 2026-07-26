import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/api_error.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/image_compress.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/pulse_field.dart';
import '../../core/widgets/pulse_scaffold.dart';
import '../member/pulse/pulse.dart';
import 'tenant_api.dart';
import 'tenant_detail_sheet.dart';
import 'tenant_ui.dart';

/// Ported from the mockup `ScreensManageTenants.jsx > ManageTenantsScreen`.
///
/// Two explicit jobs behind one segmented control:
///   1. **Add tenant** — full approval workflow, documents required, tenant
///      gets a login after the admin approves.
///   2. **Past tenant history** — record-keeping only, saved immediately, no
///      approval and no login.
///
/// The audit (3.6/3.8) found these two flows split across three routes
/// (`/manage-tenants`, `/add-tenant`, `/tenant-history`) with a stock navy
/// `TabBar`, so users could not tell which one created a login. The banner on
/// each tab now states the consequence up front.
class ManageTenantsPage extends StatefulWidget {
  /// `'add'` or `'past'` — My Tenant's "Past tenants" row deep-links here.
  final String initialTab;
  const ManageTenantsPage({super.key, this.initialTab = 'add'});
  @override
  State<ManageTenantsPage> createState() => _ManageTenantsPageState();
}

class _ManageTenantsPageState extends State<ManageTenantsPage> {
  late String _tab = widget.initialTab == 'past' ? 'past' : 'add';

  @override
  Widget build(BuildContext context) {
    return PulseScaffold(
      title: 'Manage Tenants',
      subtitle: 'Onboard or record tenant history',
      trailing: [
        PulseIconButton(
          icon: Icons.people_alt_outlined,
          onTap: () => context.push('/my-tenant'),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: PulseSegmented<String>(
              value: _tab,
              onChanged: (v) => setState(() => _tab = v),
              options: const [
                PulseSegmentedOption(value: 'add', label: 'Add tenant'),
                PulseSegmentedOption(
                    value: 'past', label: 'Past tenant history'),
              ],
            ),
          ),
          Expanded(
            child: _tab == 'add'
                ? const _AddTenantTab()
                : const _PastTenantsTab(),
          ),
        ],
      ),
    );
  }
}

/* ==========================================================================
   ADD TENANT TAB
   ========================================================================== */

class _AddTenantTab extends StatefulWidget {
  const _AddTenantTab();
  @override
  State<_AddTenantTab> createState() => _AddTenantTabState();
}

class _AddTenantTabState extends State<_AddTenantTab> {
  final _viewKey = GlobalKey<AsyncViewState<List>>();

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return AsyncView<List>(
      key: _viewKey,
      fetch: () => fetchTenantRequests(context.read<Dio>()),
      builder: (context, requests) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            const TenantBanner(
              'This tenant goes through the full workflow: you submit details '
              'and documents, the society admin approves, and the tenant then '
              'receives login credentials by email.',
              icon: Icons.info_outline_rounded,
            ),
            const SizedBox(height: 18),
            PulseButton(
              label: 'New tenant request',
              icon: Icons.person_add_alt_rounded,
              full: true,
              onTap: () async {
                final created = await showNewTenantSheet(context);
                if (created == true) await _viewKey.currentState?.reload();
              },
            ),
            const SizedBox(height: 18),
            const TenantSectionTitle('Your requests'),
            if (requests.isEmpty)
              Text('No requests submitted yet.',
                  style: TextStyle(fontSize: 12.5, color: t.fg4))
            else
              ...requests.cast<Map>().map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PulseCard(
                        padding: const EdgeInsets.all(13),
                        onTap: () => showTenantDetailSheet(context,
                            tenancy: r, kind: TenantDetailKind.request),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    displayName(r['tenantName'],
                                        fallback: 'Tenant'),
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: t.fg1),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${inr(r['rentPerMonth'] as num?)}/mo '
                                    '\u00B7 from ${fmtDate(r['leaseStartDate'])}',
                                    style: TextStyle(
                                        fontSize: 11.5, color: t.fg4),
                                  ),
                                ],
                              ),
                            ),
                            PulsePill(
                                label: r['status']?.toString() ?? 'Pending',
                                tone: rentTone(r['status']?.toString()),
                                small: true),
                            const SizedBox(width: 6),
                            Icon(Icons.chevron_right_rounded,
                                size: 18, color: t.fg5),
                          ],
                        ),
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

/* ==========================================================================
   NEW TENANT REQUEST SHEET
   ========================================================================== */

/// Full-height sheet, ported from the mockup's `NewTenantSheet`.
///
/// Audit fixes applied on top of the mockup: inline per-field errors instead
/// of one banner at the bottom (3.4 flaw 6), a real 5-state upload row per
/// document (3.4 flaw 4), and a sticky footer CTA that can never be clipped
/// (3.4 flaw 1).
Future<bool?> showNewTenantSheet(BuildContext context) {
  return showPulseSheet<bool>(
    context,
    title: 'New tenant request',
    full: true,
    builder: (ctx) => const _NewTenantForm(),
  );
}

class _NewTenantForm extends StatefulWidget {
  const _NewTenantForm();
  @override
  State<_NewTenantForm> createState() => _NewTenantFormState();
}

class _NewTenantFormState extends State<_NewTenantForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _rent = TextEditingController();
  final _deposit = TextEditingController();
  DateTime? _start;
  DateTime? _end;

  final Map<String, String> _docKeys = {};
  final Map<String, bool> _uploading = {};
  final Map<String, String> _docErrors = {};
  final Map<String, String?> _errors = {};
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _rent, _deposit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(String field) async {
    final picked = await showPulseSheet<XFile?>(
      context,
      title: 'Add document',
      builder: (ctx) => Column(
        children: [
          PulseRow(
            icon: Icons.photo_camera_outlined,
            label: 'Take a photo',
            onTap: () async {
              final f = await ImagePicker()
                  .pickImage(source: ImageSource.camera, imageQuality: 90);
              if (ctx.mounted) Navigator.of(ctx).pop(f);
            },
          ),
          PulseRow(
            icon: Icons.photo_library_outlined,
            label: 'Choose from gallery',
            onTap: () async {
              final f = await ImagePicker()
                  .pickImage(source: ImageSource.gallery, imageQuality: 90);
              if (ctx.mounted) Navigator.of(ctx).pop(f);
            },
          ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _uploading[field] = true;
      _docErrors.remove(field);
    });
    if (!mounted) return;
    // Resolve Dio BEFORE the compress/upload awaits. Reading it from context
    // afterwards is a use-after-async-gap: this sheet can be dismissed while a
    // large photo is still being re-encoded.
    final dio = context.read<Dio>();
    try {
      final compressed = await compressForUpload(File(picked.path));
      final key = await uploadTenantDocumentBytes(dio, field, compressed,
          filename: '$field.jpg');
      if (!mounted) return;
      setState(() {
        _docKeys[field] = key;
        _uploading[field] = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _uploading[field] = false;
        // Loud, specific, retryable — never a silent no-op.
        _docErrors[field] = apiErrorMessage(err);
      });
    }
  }

  bool _validate() {
    final e = <String, String?>{};
    if (_name.text.trim().length < 2) e['name'] = 'Tenant name is required';
    if (!RegExp(r'^\d{10}$').hasMatch(_phone.text.trim())) {
      e['phone'] = 'Enter a valid 10-digit phone number';
    }
    if (!_email.text.contains('@')) {
      e['email'] = 'Enter a valid email address';
    }
    if (_start == null) e['start'] = 'Select the lease start date';
    if (_end == null) e['end'] = 'Select the lease end date';
    if (_start != null && _end != null && !_end!.isAfter(_start!)) {
      e['end'] = 'End date must be after the start date';
    }
    final rent = num.tryParse(_rent.text.trim());
    if (rent == null || rent <= 0) {
      e['rent'] = 'Enter a valid monthly rent amount';
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(e);
    });
    if (e.isNotEmpty) return false;
    for (final f in kTenantDocFields) {
      if (_docKeys[f.field] == null) {
        showAppToast(context, 'Upload the ${f.label} to continue',
            kind: AppToastKind.alert);
        return false;
      }
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_validate() || _submitting) return;
    setState(() => _submitting = true);
    try {
      await submitTenantRequest(context.read<Dio>(), {
        'tenantName': _name.text.trim(),
        'tenantPhone': _phone.text.trim(),
        'tenantEmail': _email.text.trim(),
        'leaseStartDate': _start!.toIso8601String().substring(0, 10),
        'leaseEndDate': _end!.toIso8601String().substring(0, 10),
        'rentPerMonth': num.parse(_rent.text.trim()),
        'depositAmount': num.tryParse(_deposit.text.trim()) ?? 0,
        'documents': {
          for (final entry in _docKeys.entries) '${entry.key}Key': entry.value,
        },
      });
      if (!mounted) return;
      showAppToast(context, 'Tenant request submitted for admin approval',
          kind: AppToastKind.success);
      Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TenantBanner(
          'Submit details and documents \u2014 the society admin approves, then '
          'the tenant receives login credentials by email.',
          icon: Icons.verified_user_outlined,
        ),
        const SizedBox(height: 18),
        PulseField(
            label: 'Tenant name',
            controller: _name,
            required: true,
            error: _errors['name'],
            textInputAction: TextInputAction.next),
        const SizedBox(height: 12),
        PulseField.phone(
            label: 'Tenant phone',
            controller: _phone,
            error: _errors['phone']),
        const SizedBox(height: 12),
        PulseField(
          label: 'Tenant email',
          controller: _email,
          required: true,
          error: _errors['email'],
          keyboardType: TextInputType.emailAddress,
          helper: 'Login credentials are sent here after approval.',
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PulseDateField(
                label: 'Lease start',
                value: _start,
                required: true,
                error: _errors['start'],
                onChanged: (v) => setState(() => _start = v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PulseDateField(
                label: 'Lease end',
                value: _end,
                required: true,
                error: _errors['end'],
                firstDate: _start,
                onChanged: (v) => setState(() => _end = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PulseField.money(
            label: 'Rent per month',
            controller: _rent,
            error: _errors['rent']),
        const SizedBox(height: 12),
        PulseField.money(
            label: 'Deposit amount',
            controller: _deposit,
            required: false),
        const SizedBox(height: 18),
        const TenantSectionTitle('Documents'),
        ...kTenantDocFields.map(
          (f) => DocRow(
            label: f.label,
            uploaded: _docKeys[f.field] != null,
            uploading: _uploading[f.field] == true,
            error: _docErrors[f.field],
            onUpload: () => _pick(f.field),
          ),
        ),
        const SizedBox(height: 20),
        PulseButton(
          label: 'Submit request',
          full: true,
          size: PulseBtnSize.lg,
          loading: _submitting,
          onTap: _submit,
        ),
      ],
    );
  }
}

/* ==========================================================================
   PAST TENANTS TAB
   ========================================================================== */

class _PastTenantsTab extends StatefulWidget {
  const _PastTenantsTab();
  @override
  State<_PastTenantsTab> createState() => _PastTenantsTabState();
}

class _PastTenantsTabState extends State<_PastTenantsTab> {
  final _viewKey = GlobalKey<AsyncViewState<List>>();

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return AsyncView<List>(
      key: _viewKey,
      fetch: () async {
        final all = await fetchTenantHistory(context.read<Dio>());
        return all.cast<Map>().where((e) => e['_section'] == 'past').toList();
      },
      builder: (context, past) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            const TenantBanner(
              'Record a tenancy that already ended. This is history only \u2014 '
              'no approval and no login is created.',
              neutral: true,
              icon: Icons.history_rounded,
            ),
            const SizedBox(height: 18),
            PulseButton(
              label: 'Add past tenant',
              icon: Icons.add_rounded,
              variant: PulseBtnVariant.secondary,
              full: true,
              onTap: () async {
                final saved = await showPulseSheet<bool>(
                  context,
                  title: 'Add past tenant',
                  full: true,
                  builder: (ctx) => const _PastTenantForm(),
                );
                if (saved == true) await _viewKey.currentState?.reload();
              },
            ),
            const SizedBox(height: 18),
            const TenantSectionTitle('Past tenants'),
            if (past.isEmpty)
              Text('No past tenancies recorded.',
                  style: TextStyle(fontSize: 12.5, color: t.fg4))
            else
              ...past.cast<Map>().map(
                    (h) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PulseCard(
                        padding: const EdgeInsets.all(13),
                        onTap: () => showTenantDetailSheet(context,
                            tenancy: h, kind: TenantDetailKind.past),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    displayName(h['tenantName'],
                                        fallback: 'Tenant'),
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: t.fg1),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${fmtDate(h['leaseStartDate'])} \u2014 '
                                    '${fmtDate(h['leaseEndDate'])} \u00B7 '
                                    '${inr(h['rentPerMonth'] as num?)}/mo',
                                    style: TextStyle(
                                        fontSize: 11.5, color: t.fg4),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                size: 18, color: t.fg5),
                          ],
                        ),
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _PastTenantForm extends StatefulWidget {
  const _PastTenantForm();
  @override
  State<_PastTenantForm> createState() => _PastTenantFormState();
}

class _PastTenantFormState extends State<_PastTenantForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _rent = TextEditingController();
  final _deposit = TextEditingController();
  final _reason = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  final Map<String, String?> _errors = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _rent, _deposit, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final e = <String, String?>{};
    if (_name.text.trim().length < 2) e['name'] = 'Tenant name is required';
    if (!RegExp(r'^\d{10}$').hasMatch(_phone.text.trim())) {
      e['phone'] = 'Enter a valid 10-digit phone number';
    }
    if (_start == null) e['start'] = 'Select the tenancy start date';
    if (_end == null) e['end'] = 'Select the tenancy end date';
    if (_start != null && _end != null && !_end!.isAfter(_start!)) {
      e['end'] = 'End date must be after the start date';
    }
    final rent = num.tryParse(_rent.text.trim());
    if (rent == null || rent <= 0) {
      e['rent'] = 'Enter a valid monthly rent amount';
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(e);
    });
    if (e.isNotEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await submitTenantHistory(context.read<Dio>(), {
        'tenantName': _name.text.trim(),
        'tenantPhone': _phone.text.trim(),
        if (_email.text.trim().isNotEmpty) 'tenantEmail': _email.text.trim(),
        'leaseStartDate': _start!.toIso8601String().substring(0, 10),
        'leaseEndDate': _end!.toIso8601String().substring(0, 10),
        'rentPerMonth': rent,
        'depositAmount': num.tryParse(_deposit.text.trim()) ?? 0,
        if (_reason.text.trim().isNotEmpty)
          'moveOutReason': _reason.text.trim(),
      });
      if (!mounted) return;
      showAppToast(context, 'Tenant history saved',
          kind: AppToastKind.success);
      Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TenantBanner(
          'For record-keeping only \u2014 saved immediately, no admin approval '
          'needed.',
          neutral: true,
          icon: Icons.lock_outline_rounded,
        ),
        const SizedBox(height: 18),
        PulseField(
            label: 'Tenant name',
            controller: _name,
            required: true,
            error: _errors['name']),
        const SizedBox(height: 12),
        PulseField.phone(
            label: 'Tenant phone',
            controller: _phone,
            error: _errors['phone']),
        const SizedBox(height: 12),
        PulseField(
            label: 'Tenant email',
            controller: _email,
            required: false,
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PulseDateField(
                label: 'Tenancy start',
                value: _start,
                required: true,
                error: _errors['start'],
                onChanged: (v) => setState(() => _start = v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PulseDateField(
                label: 'Tenancy end',
                value: _end,
                required: true,
                error: _errors['end'],
                firstDate: _start,
                onChanged: (v) => setState(() => _end = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PulseField.money(
            label: 'Rent per month',
            controller: _rent,
            error: _errors['rent']),
        const SizedBox(height: 12),
        PulseField.money(
            label: 'Deposit amount',
            controller: _deposit,
            required: false),
        const SizedBox(height: 12),
        PulseField(
            label: 'Move-out reason',
            controller: _reason,
            required: false,
            maxLines: 3,
            hint: 'e.g. Relocated for work'),
        const SizedBox(height: 20),
        PulseButton(
          label: 'Save tenant history',
          full: true,
          size: PulseBtnSize.lg,
          loading: _saving,
          onTap: _save,
        ),
      ],
    );
  }
}
