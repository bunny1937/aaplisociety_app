import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_error.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/hold_to_confirm.dart';
import '../../core/widgets/pulse_scaffold.dart';
import '../member/pulse/pulse.dart';
import 'tenancy_thread_sheet.dart';
import 'tenant_api.dart';
import 'tenant_detail_sheet.dart';
import 'tenant_documents_sheet.dart';
import 'tenant_ui.dart';

/// Owner's "My Tenant" hub.
///
/// Ported from the approved mockup `ScreensTenant.jsx > MyTenantScreen`:
/// pending-rent confirmation queue on top, the active TenancyCard, a
/// rent-records summary row, an activity feed, then past tenants.
///
/// Replaces the previous screen, which was an `AppBar` + flat `ListView` of
/// `AlertDialog`-driven actions with no hierarchy (audit 3.7).
class MyTenantPage extends StatefulWidget {
  const MyTenantPage({super.key});
  @override
  State<MyTenantPage> createState() => _MyTenantPageState();
}

class _MyTenantPageState extends State<MyTenantPage> {
  final _viewKey = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  bool _busy = false;

  /// Optimistic value for the login switch.
  ///
  /// The old flow toasted "Tenant login enabled" and then refetched, and the
  /// refetch came back with the flag stripped, so the switch flicked straight
  /// back to grey/off. Holding the confirmed server value here means the switch
  /// agrees with the toast immediately and stays that way through the reload.
  bool? _loginOverride;

  /// Opens the real document review sheet.
  ///
  /// This is what "missing documents" should always have done. It used to push
  /// `/manage-tenants`, which is the ADD-a-tenant screen - nowhere near the
  /// documents, and a confusing place to land when all you wanted was to look
  /// at a lease your tenant already uploaded.
  Future<void> _openDocuments(Map tenancy) async {
    final changed = await showTenantDocumentsSheet(
      context,
      tenancy: tenancy,
      asOwner: true,
    );
    if (changed && mounted) await _viewKey.currentState?.reload();
  }

  Future<void> _toggleLogin(Map tenancy, bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await updateTenantLogin(
          context.read<Dio>(), '${tenancy['_id']}', on);
      if (!mounted) return;
      final confirmed = res['loginEnabled'];
      setState(() {
        // Trust the server's echo over our own optimism when it sends one.
        _loginOverride = confirmed is bool ? confirmed : on;
        _busy = false;
      });
      showAppToast(
        context,
        '${res['message'] ?? (on ? 'Tenant login enabled' : 'Tenant login disabled')}',
        kind: AppToastKind.success,
      );
      await _viewKey.currentState?.reload();
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _loginOverride = null;
      });
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    }
  }

  Future<Map<String, dynamic>> _load() async {
    final dio = context.read<Dio>();
    // Both calls in parallel — the old screen awaited them serially, which
    // doubled the perceived load time on a slow connection.
    final results = await Future.wait([
      fetchTenantHistory(dio),
      fetchRentPayments(dio),
    ]);
    final tenancies = results[0];
    final rents = results[1];
    final current = tenancies.cast<Map>().where((t) {
      final section = t['_section']?.toString();
      final status = t['status']?.toString().toLowerCase();
      return section == 'current' || status == 'active' || status == 'approved';
    }).toList();
    final past = tenancies
        .cast<Map>()
        .where((t) => t['_section'] == 'past')
        .toList();
    return {
      'tenancy': current.isEmpty ? null : current.first,
      'rents': rents.cast<Map>(),
      'past': past,
    };
  }

  /// Runs a mutation, then refetches so the UI can never drift from the
  /// server. Errors surface the real API message instead of failing silently.
  Future<void> _run(Future<void> Function() action, String okMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showAppToast(context, okMessage, kind: AppToastKind.success);
      await _viewKey.currentState?.reload();
    } catch (err) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return PulseScaffold(
      title: 'My Tenant',
      subtitle: 'Manage your current tenancy',
      trailing: [
        PulseIconButton(
          icon: Icons.settings_outlined,
          onTap: () => context.push('/manage-tenants'),
        ),
      ],
      child: AsyncView<Map<String, dynamic>>(
        key: _viewKey,
        fetch: _load,
        builder: (context, data) {
          final tenancy = data['tenancy'] as Map?;
          final rents = (data['rents'] as List).cast<Map>();
          final past = (data['past'] as List).cast<Map>();
          final pending = rents
              .where((r) => r['status']?.toString().toLowerCase() == 'pending')
              .toList();
          final active = tenancy != null &&
              (tenancy['status']?.toString().toLowerCase() != 'ended');
          final activity = (tenancy?['activity'] as List?)?.cast<Map>() ??
              _derivedActivity(rents);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              // ---- Pending rent queue -------------------------------------
              if (pending.isNotEmpty) ...[
                TenantSectionTitle(
                  'Awaiting your confirmation',
                  trailing: PulsePill(
                      label: '${pending.length}',
                      tone: PulseTone.pending,
                      dot: false,
                      small: true),
                ),
                ...pending.map(
                  (r) => RentTile(
                    rent: r,
                    busy: _busy,
                    onConfirm: () => _run(
                      () => confirmRentPayment(
                              context.read<Dio>(), '${r['_id']}', true)
                          .then((_) {}),
                      'Rent payment confirmed',
                    ),
                    onReject: () async {
                      final reason = await showPromptSheet(
                        context,
                        title: 'Reject rent payment',
                        label: 'Reason shown to the tenant',
                        hint: 'e.g. Amount doesn\'t match the rent due',
                        submitLabel: 'Reject payment',
                        danger: true,
                        multiline: true,
                      );
                      if (reason == null) return;
                      await _run(
                        () => confirmRentPayment(
                                context.read<Dio>(), '${r['_id']}', false,
                                reason: reason)
                            .then((_) {}),
                        'Rent payment rejected',
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
              ],

              // ---- Active tenancy -----------------------------------------
              const TenantSectionTitle('Active tenancy'),
              if (active)
                TenancyCard(
                  tenancy: tenancy,
                  active: true,
                  loginBusy: _busy,
                  loginOverride: _loginOverride,
                  onOpenDetail: () => showTenantDetailSheet(
                    context,
                    tenancy: tenancy,
                    kind: TenantDetailKind.active,
                  ),
                  onFixDocs: () => _openDocuments(tenancy),
                  onRemind: () => _run(
                    () => sendRentReminder(
                      context.read<Dio>(),
                      month:
                          DateTime.now().toIso8601String().substring(0, 7),
                      amount: (tenancy['rentPerMonth'] as num?) ?? 0,
                    ),
                    'Rent reminder sent to your tenant',
                  ),
                  onEditDates: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          parseDate(tenancy['leaseEndDate']) ?? DateTime.now(),
                      firstDate: parseDate(tenancy['leaseStartDate']) ??
                          DateTime(DateTime.now().year - 5),
                      lastDate: DateTime(DateTime.now().year + 10),
                      helpText: 'New lease end date',
                    );
                    if (picked == null) return;
                    final iso = picked.toIso8601String().substring(0, 10);
                    await _run(
                      () => requestLeaseDateChange(
                              context.read<Dio>(), '${tenancy['_id']}',
                              {'leaseEndDate': iso})
                          .then((_) {}),
                      'Lease date change sent for approval',
                    );
                  },
                  // Was a one-shot "Add a note" prompt that posted the text and
                  // discarded the response, so the owner could write but never
                  // READ - including the note their tenant sent them, which
                  // they got a push notification about. Now it opens the actual
                  // two-way thread.
                  onNote: () => showTenancyThreadSheet(
                    context,
                    requestId: '${tenancy['_id']}',
                    title:
                        'Messages with ${displayName(tenancy['tenantName'], fallback: 'your tenant')}',
                    mineIsTenant: false,
                  ),
                  onToggleLogin: (on) => _toggleLogin(tenancy, on),
                  onEndLease: () => _confirmEndLease(tenancy),
                )
              else
                _NoTenantCard(onAdd: () => context.push('/manage-tenants')),

              // ---- Rent records summary -----------------------------------
              PulseCard(
                padding: const EdgeInsets.all(14),
                onTap: () => context.push('/rent-payments'),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Rent records',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: t.fg1)),
                          const SizedBox(height: 2),
                          Text(
                            rents.isEmpty
                                ? 'No rent payments recorded yet'
                                : '${rents.length} record'
                                    '${rents.length > 1 ? 's' : ''}'
                                    '${pending.isEmpty ? '' : ' \u00B7 ${pending.length} pending'}',
                            style:
                                TextStyle(fontSize: 11.5, color: t.fg4),
                          ),
                        ],
                      ),
                    ),
                    Text('See all',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.brand)),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: t.brand),
                  ],
                ),
              ),

              // ---- Activity -----------------------------------------------
              if (activity.isNotEmpty) ...[
                const TenantSectionTitle('Activity',
                    padding: EdgeInsets.fromLTRB(0, 18, 0, 8)),
                PulseCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: Column(
                    children: [
                      for (var i = 0;
                          i < (activity.length > 5 ? 5 : activity.length);
                          i++)
                        ActivityRow(
                          item: activity[i],
                          last: i ==
                              (activity.length > 5 ? 5 : activity.length) - 1,
                        ),
                    ],
                  ),
                ),
              ],

              // ---- Past tenants -------------------------------------------
              const SizedBox(height: 14),
              PulseCard(
                padding: const EdgeInsets.all(14),
                onTap: () =>
                    context.push('/manage-tenants', extra: {'tab': 'past'}),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Past tenants',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: t.fg1)),
                          const SizedBox(height: 2),
                          Text(
                            past.isEmpty
                                ? 'No past tenancies'
                                : '${past.length} past '
                                    '${past.length == 1 ? 'tenancy' : 'tenancies'}',
                            style:
                                TextStyle(fontSize: 11.5, color: t.fg4),
                          ),
                        ],
                      ),
                    ),
                    Text('View all',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.brand)),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: t.brand),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Ending a lease is irreversible and disables another person's app access,
  /// so it gets an explicit consequences sheet with asymmetric buttons — not
  /// the old two-line `AlertDialog` (audit 3.7 flaw 8).
  Future<void> _confirmEndLease(Map tenancy) async {
    final ok = await showPulseSheet<bool>(
      context,
      title: 'End this lease?',
      builder: (ctx) {
        final t = ctx.pulse;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This marks the tenancy as ended, disables the tenant login '
              'after admin confirmation, and moves the record to Past '
              'tenants.',
              style: TextStyle(fontSize: 13.5, height: 1.6, color: t.fg2),
            ),
            const SizedBox(height: 14),
            TenantKv('Tenant',
                displayName(tenancy['tenantName'], fallback: 'Tenant')),
            TenantKv('Lease',
                fmtLeaseRange(
                    tenancy['leaseStartDate'], tenancy['leaseEndDate']),
                last: true),
            const SizedBox(height: 18),
            DestructiveConfirmActions(
              confirmLabel: 'End lease',
              onConfirm: () => Navigator.of(ctx).pop(true),
              onCancel: () => Navigator.of(ctx).pop(false),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await _run(
      () => endLease(context.read<Dio>(), '${tenancy['_id']}').then((_) {}),
      'Lease ended \u2014 sent for admin confirmation',
    );
  }

  /// The backend does not yet return an activity feed, so derive a truthful
  /// one from rent records rather than inventing entries.
  List<Map> _derivedActivity(List<Map> rents) {
    return rents.take(5).map((r) {
      final status = r['status']?.toString().toLowerCase();
      return {
        'text': switch (status) {
          'confirmed' =>
            'Rent confirmed for ${fmtPeriodId(r['month'])}',
          'rejected' => 'Rent rejected for ${fmtPeriodId(r['month'])}',
          _ => 'Rent submitted for ${fmtPeriodId(r['month'])}',
        },
        'date': r['paidAt'] ?? r['createdAt'],
        'icon': switch (status) {
          'confirmed' => 'check-circle',
          'rejected' => 'x-circle',
          _ => 'indian-rupee',
        },
      };
    }).toList();
  }
}

class _NoTenantCard extends StatelessWidget {
  final VoidCallback onAdd;
  const _NoTenantCard({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PulseCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const PulseIllustration(kind: PulseIllo.noData, size: 64),
            const SizedBox(height: 8),
            Text('No active tenant',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.fg1)),
            const SizedBox(height: 2),
            Text('Add one from Manage Tenants.',
                style: TextStyle(fontSize: 12, color: t.fg4)),
            const SizedBox(height: 12),
            PulseButton(
                label: 'Add a tenant',
                size: PulseBtnSize.sm,
                onTap: onAdd),
          ],
        ),
      ),
    );
  }
}
