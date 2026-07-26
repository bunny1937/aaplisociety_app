import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_error.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/pulse_field.dart';
import '../../core/widgets/pulse_scaffold.dart';
import '../auth/bloc/auth_bloc.dart';
import '../member/pulse/member_display.dart';
import '../member/pulse/pulse.dart';
import 'rent_payment_page.dart';
import 'tenant_api.dart';
import 'tenant_ui.dart';

/// **Tenant profile environment.**
///
/// The owner has My Tenant / Manage Tenants / Rent Payments. The tenant had
/// nothing: their Profile tab showed the owner's screen with every action
/// disabled, and the audit found dead "Edit" affordances plus a `Bills` tab
/// that silently vanished (3.10 / RC-3).
///
/// This screen is the tenant's counterpart, built from the same ported
/// tenancy components so both roles share one visual language:
///   * Their own tenancy terms, read-only and clearly labelled as such.
///   * A rent submission flow that goes to the owner for confirmation.
///   * Their submitted rent history with live status.
///   * Their documents on file.
///   * Owner/landlord contact, one tap to call.
class TenantProfilePage extends StatefulWidget {
  const TenantProfilePage({super.key});
  @override
  State<TenantProfilePage> createState() => _TenantProfilePageState();
}

class _TenantProfilePageState extends State<TenantProfilePage> {
  final _viewKey = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  Future<Map<String, dynamic>> _load() async {
    final dio = context.read<Dio>();
    final results = await Future.wait([
      fetchMyTenancy(dio),
      fetchRentPayments(dio),
    ]);
    return {
      'tenancy': results[0] as Map<String, dynamic>?,
      'rents': (results[1] as List).cast<Map>(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final authState = context.watch<AuthBloc>().state;
    // Typed explicitly: AuthAuthed.user/claims come off JSON as
    // Map<dynamic, dynamic>, and member_display's helpers require
    // Map<String, dynamic>.
    final Map<String, dynamic> user = authState is AuthAuthed
        ? Map<String, dynamic>.from(authState.user as Map)
        : const <String, dynamic>{};
    final Map<String, dynamic> claims = authState is AuthAuthed
        ? Map<String, dynamic>.from(authState.claims as Map)
        : const <String, dynamic>{};
    final activeProfileId = claims['activeProfileId'];
    final profiles = (user['profiles'] as List?) ?? const [];
    final activeProfile = profiles.cast<Map?>().firstWhere(
          (p) => p?['_id']?.toString() == activeProfileId?.toString(),
          orElse: () => profiles.isEmpty ? null : profiles.first as Map?,
        );
    final member = user['member'] as Map? ?? const {};
    final flatNo = activeProfile?['flatNo'] ?? member['flatNo'];
    final wing = activeProfile?['wing'] ?? member['wing'];
    final flatLabel = [
      if (wing != null && '$wing'.isNotEmpty) 'Wing $wing',
      if (flatNo != null && '$flatNo'.isNotEmpty) 'Flat $flatNo',
    ].join(' \u00B7 ');

    return PulseScaffold(
      title: 'My Profile',
      subtitle: resolveSocietyName(user, activeProfile),
      child: AsyncView<Map<String, dynamic>>(
        key: _viewKey,
        fetch: _load,
        builder: (context, data) {
          final tenancy = data['tenancy'] as Map?;
          final rents = (data['rents'] as List).cast<Map>();
          final mine = rents;
          final pending = mine
              .where((r) => r['status']?.toString().toLowerCase() == 'pending')
              .toList();
          final docs = missingDocs(tenancy);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              // ---- Identity header ----------------------------------------
              PulseCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    PulseAvatar(
                        name: resolveDisplayName(user), size: 52, ring: true),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            resolveDisplayName(user),
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: t.fg1),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            flatLabel.isEmpty ? kEmDash : flatLabel,
                            style: TextStyle(fontSize: 12.5, color: t.fg3),
                          ),
                          const SizedBox(height: 6),
                          const PulsePill(
                              label: 'TENANT',
                              tone: PulseTone.info,
                              small: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ---- My tenancy ----------------------------------------------
              const TenantSectionTitle('My tenancy'),
              if (tenancy == null)
                const PulseEmptyState(
                  illo: PulseIllo.noData,
                  title: 'No tenancy on record',
                  subtitle:
                      'Your flat owner has not registered your tenancy yet. '
                      'Ask them to add you from Manage Tenants.',
                )
              else
                PulseCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TenantStat(
                                label: 'Rent / month',
                                value:
                                    inr(tenancy['rentPerMonth'] as num?),
                                money: true),
                          ),
                          Expanded(
                            child: TenantStat(
                                label: 'Deposit',
                                value:
                                    inr(tenancy['depositAmount'] as num?),
                                money: true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TenantStat(
                                label: 'Lease start',
                                value: fmtDate(tenancy['leaseStartDate'])),
                          ),
                          Expanded(
                            child: TenantStat(
                                label: 'Lease end',
                                value:
                                    fmtLeaseEnd(tenancy['leaseEndDate'])),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Says plainly who can change this, instead of showing a
                      // dead Edit button (audit 3.10 flaw 2).
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: t.surface3,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                size: 15, color: t.fg3),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Your lease terms are managed by your flat '
                                'owner and the society admin.',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.45,
                                    color: t.fg3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),

              // ---- Submit rent ---------------------------------------------
              const TenantSectionTitle('Rent'),
              PulseCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Submit a rent payment',
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: t.fg1)),
                              const SizedBox(height: 2),
                              Text(
                                pending.isEmpty
                                    ? 'Your owner confirms each payment.'
                                    : '${pending.length} awaiting your owner\'s '
                                        'confirmation',
                                style: TextStyle(
                                    fontSize: 11.5, color: t.fg4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    PulseButton(
                      label: 'Submit payment',
                      icon: Icons.currency_rupee_rounded,
                      full: true,
                      onTap: () async {
                        final saved = await showPulseSheet<bool>(
                          context,
                          title: 'Submit rent payment',
                          builder: (ctx) => const _TenantRentForm(),
                        );
                        if (saved == true) {
                          await _viewKey.currentState?.reload();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (mine.isEmpty)
                Text('No rent payments submitted yet.',
                    style: TextStyle(fontSize: 12.5, color: t.fg4))
              else
                ...mine.take(6).map((r) => RentTile(rent: r)),
              if (mine.length > 6)
                Align(
                  alignment: Alignment.centerLeft,
                  child: PulseButton(
                    label: 'See all ${mine.length} payments',
                    variant: PulseBtnVariant.link,
                    size: PulseBtnSize.sm,
                    onTap: () => context.push('/rent-payments'),
                  ),
                ),
              const SizedBox(height: 18),

              // ---- Documents ------------------------------------------------
              const TenantSectionTitle('My documents'),
              PulseCard(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: [
                    for (final f in kTenantDocFields)
                      _DocStatusRow(
                        label: f.label,
                        onFile: !docs.contains(f),
                        last: f == kTenantDocFields.last,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ---- Owner contact --------------------------------------------
              if (tenancy != null) ...[
                const TenantSectionTitle('Flat owner'),
                PulseCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      PulseAvatar(
                          name: displayName(
                              tenancy['ownerName'] ?? member['name'],
                              fallback: 'Owner'),
                          size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayName(
                                  tenancy['ownerName'] ?? member['name'],
                                  fallback: 'Your flat owner'),
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: t.fg1),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (tenancy['ownerPhone'] ?? member['phone'])
                                      ?.toString() ??
                                  'Contact via the society office',
                              style:
                                  TextStyle(fontSize: 11.5, color: t.fg4),
                            ),
                          ],
                        ),
                      ),
                      if ((tenancy['ownerPhone'] ?? member['phone']) != null)
                        PulseIconButton(
                          icon: Icons.call_rounded,
                          onTap: () async {
                            final phone =
                                (tenancy['ownerPhone'] ?? member['phone'])
                                    .toString();
                            final ok =
                                await launchUrl(Uri.parse('tel:$phone'));
                            if (!ok && context.mounted) {
                              showAppToast(context,
                                  'Could not open the phone dialer',
                                  kind: AppToastKind.alert);
                            }
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // ---- Account --------------------------------------------------
              const PulseSectionLabel('Account'),
              PulseGroup(
                children: [
                  PulseRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Personal details',
                    onTap: () => context.push('/profile/basic-details'),
                  ),
                  PulseRow(
                    icon: Icons.call_outlined,
                    label: 'Contact details',
                    onTap: () => context.push('/profile/contact'),
                  ),
                  PulseRow(
                    icon: Icons.lock_outline_rounded,
                    label: 'Change password',
                    onTap: () => context.push('/change-password'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DocStatusRow extends StatelessWidget {
  final String label;
  final bool onFile;
  final bool last;
  const _DocStatusRow(
      {required this.label, required this.onFile, this.last = false});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: t.hairline, width: 1)),
      ),
      child: Row(
        children: [
          Icon(
            onFile
                ? Icons.check_circle_outline_rounded
                : Icons.pending_outlined,
            size: 18,
            color: onFile ? t.success : t.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.fg1)),
          ),
          Text(
            onFile ? 'On file' : 'Not received',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: onFile ? t.success : t.warning,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tenant-side rent submission. Deliberately simpler than the owner form:
/// no status field, because a tenant submission is always `Pending` until the
/// owner confirms it.
class _TenantRentForm extends StatefulWidget {
  const _TenantRentForm();
  @override
  State<_TenantRentForm> createState() => _TenantRentFormState();
}

class _TenantRentFormState extends State<_TenantRentForm> {
  final _amount = TextEditingController();
  String? _month;
  String _mode = 'UPI';
  final Map<String, String?> _errors = {};
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final e = <String, String?>{};
    if (_month == null) e['month'] = 'Select the rent month';
    final amt = num.tryParse(_amount.text.trim());
    if (amt == null || amt <= 0) e['amount'] = 'Enter a valid amount';
    setState(() {
      _errors
        ..clear()
        ..addAll(e);
    });
    if (e.isNotEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await recordRentPayment(context.read<Dio>(), {
        'month': _month,
        'amount': amt,
        'paymentMode': _mode,
      });
      if (!mounted) return;
      showAppToast(context, 'Payment submitted to your owner',
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
    final t = context.pulse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseMonthField(
          label: 'Rent month',
          value: _month,
          required: true,
          error: _errors['month'],
          onChanged: (v) => setState(() => _month = v),
        ),
        const SizedBox(height: 12),
        PulseField.money(
            label: 'Amount paid',
            controller: _amount,
            error: _errors['amount']),
        const SizedBox(height: 12),
        Text('Payment mode',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: t.fg3)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kPaymentModes
              .where((m) => m != 'Online')
              .map((m) => ChoiceChip(
                    label: Text(kPaymentModeLabels[m] ?? m),
                    selected: _mode == m,
                    onSelected: (_) => setState(() => _mode = m),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        PulseButton(
          label: 'Submit for confirmation',
          full: true,
          size: PulseBtnSize.lg,
          loading: _saving,
          onTap: _submit,
        ),
      ],
    );
  }
}
