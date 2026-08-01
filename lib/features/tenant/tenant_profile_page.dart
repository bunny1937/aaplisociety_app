import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
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
import '../../core/theme/haptics.dart';
import '../../core/theme/theme_controller.dart';
import '../member/notices_page.dart';
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

  /// Pick, upload and attach one of the four required tenancy documents.
  ///
  /// The documents card previously listed all four as "Not received" with no way
  /// anywhere in the tenant surface to actually send them - a permanent list of
  /// complaints about the user. Uses the same two API calls the owner-side
  /// add-tenant flow uses: upload the bytes to get a storage key, then attach
  /// that key to the tenancy record.
  Future<void> _uploadDoc(String requestId, TenantDocField f) async {
    final dio = context.read<Dio>();
    try {
      // withData: true so we get bytes in memory - uploadTenantDocumentBytes
      // takes bytes, and on Android the path-based API is unreliable for files
      // picked from cloud providers.
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      );
      final file = picked?.files.single;
      final bytes = file?.bytes;
      // Null means the user backed out of the picker, which is not an error.
      if (bytes == null) return;
      final key = await uploadTenantDocumentBytes(dio, f.field, bytes,
          filename: file!.name);
      await attachTenantDocument(dio, requestId, f.field, key);
      if (!mounted) return;
      showAppToast(context, '${f.label} uploaded', kind: AppToastKind.success);
      await _viewKey.currentState?.reload();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(e), kind: AppToastKind.alert);
    }
  }

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
                        // Upload needs a tenancy record to attach to. Until the
                        // owner registers the tenancy there is nothing to attach
                        // a document to, so the action is omitted rather than
                        // failing on tap.
                        onUpload: tenancy?['_id'] == null
                            ? null
                            : () => _uploadDoc('${tenancy!['_id']}', f),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ---- Owner contact --------------------------------------------
              // This whole section used to be wrapped in `if (tenancy != null)`,
              // which is why the owner block vanished for exactly the tenants
              // who need it most: anyone whose tenancy record hasn't been
              // created by the owner yet saw nothing at all, and the only string
              // they ever got was "Contact via the society office".
              //
              // In an Indian housing society the tenant deals with the landlord
              // directly - rent, repairs, deposit, notice period. Hiding the
              // landlord behind the society office is not privacy, it is a
              // broken product. Always render it, fall back to the flat's
              // registered member, and give both a call and a message action.
              const TenantSectionTitle('Flat owner'),
              _OwnerCard(
                name: displayName(tenancy?['ownerName'] ?? member['name'],
                    fallback: 'Your flat owner'),
                phone: (tenancy?['ownerPhone'] ?? member['contactNumber'])
                        ?.toString() ??
                    '',
                flatLabel: flatLabel,
                // Needed for the shared message thread. Null on an older
                // backend that cannot resolve the tenancy: the card then falls
                // back to Call + SMS only rather than offering a dead button.
                requestId: tenancy?['_id']?.toString(),
              ),
              const SizedBox(height: 18),

              // ---- Society ---------------------------------------------------
              // A tenant lives in the society, so they get the society's notices
              // and can raise complaints. Neither was reachable from anywhere in
              // the tenant surface before this.
              const PulseSectionLabel('Society'),
              PulseGroup(
                children: [
                  PulseRow(
                    icon: Icons.campaign_outlined,
                    label: 'Notices',
                    onTap: () => showNoticesSheet(context, context.read<Dio>()),
                  ),
                  PulseRow(
                    icon: Icons.report_gmailerrorred_outlined,
                    label: 'Complaints',
                    onTap: () => context.push('/complaints'),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ---- Account --------------------------------------------------
              const PulseSectionLabel('Account'),
              PulseGroup(
                children: [
                  PulseRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Personal details',
                    // Tenants get their OWN details (currentTenant.*), not the
                    // flat owner's — `/profile/basic-details` always shows the
                    // owner's Member record regardless of who's logged in.
                    // TenantDetailsPage reads member['currentTenant'] instead.
                    onTap: () => context.push('/profile/tenant-details', extra: {
                      'user': user,
                      'member': member,
                      'flatNo': flatNo,
                      'wing': wing,
                      'email': user['email'],
                      'parkingSlots':
                          (member['parkingSlots'] as List?)?.cast<Map>() ??
                              const <Map>[],
                      'familyMembers':
                          (member['familyMembers'] as List?)?.cast<Map>() ??
                              const <Map>[],
                    }),
                  ),
                  // 'Contact details' row removed along with the
                  // /profile/contact route - it was a second screen showing the
                  // same phone and email as Personal details, and for most
                  // tenants it rendered empty.
                  PulseRow(
                    icon: Icons.lock_outline_rounded,
                    label: 'Change password',
                    onTap: () => context.push('/change-password'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  // Icon-only theme toggle. A full-width "Dark mode" row with a
                  // switch was spending a whole line of a scrolling page on a
                  // preference that is set once. The icon shows the mode you
                  // will get, which is the convention every other app uses.
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: themeModeNotifier,
                    builder: (context, mode, _) => PulseIconButton(
                      icon: mode == ThemeMode.dark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      onTap: () {
                        Haptics.select();
                        toggleTheme();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PulseButton(
                      label: 'Sign out',
                      icon: Icons.logout_rounded,
                      full: true,
                      // Destructive action, destructive colour.
                      variant: PulseBtnVariant.danger,
                      onTap: () {
                        Haptics.heavy();
                        context.read<AuthBloc>().add(LogoutRequested());
                        context.go('/login');
                      },
                    ),
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

class _DocStatusRow extends StatefulWidget {
  final String label;
  final bool onFile;
  final bool last;
  /// Null when there is no tenancy record to attach a document to yet.
  final Future<void> Function()? onUpload;
  const _DocStatusRow(
      {required this.label,
      required this.onFile,
      this.last = false,
      this.onUpload});
  @override
  State<_DocStatusRow> createState() => _DocStatusRowState();
}

class _DocStatusRowState extends State<_DocStatusRow> {
  bool _busy = false;

  Future<void> _run() async {
    final action = widget.onUpload;
    if (action == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      // The row can be disposed by the parent's reload() before the upload
      // resolves, so guard the setState.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final onFile = widget.onFile;
    final last = widget.last;
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
          if (widget.onUpload != null) ...[
            const SizedBox(width: 10),
            PulseButton(
              label: onFile ? 'Replace' : 'Upload',
              size: PulseBtnSize.sm,
              variant:
                  onFile ? PulseBtnVariant.ghost : PulseBtnVariant.secondary,
              loading: _busy,
              onTap: _run,
            ),
          ],
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
        // 2x2 grid, matching the owner-side rent form. The `.where(Online)`
        // filter is gone because 'Online' no longer exists in kPaymentModes at
        // all - it was a mode with no gateway behind it.
        Column(
          children: [
            for (var row = 0; row < kPaymentModes.length; row += 2)
              Padding(
                padding: EdgeInsets.only(
                    bottom: row + 2 < kPaymentModes.length ? 8 : 0),
                child: Row(
                  children: [
                    for (var i = row;
                        i < row + 2 && i < kPaymentModes.length;
                        i++) ...[
                      if (i > row) const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: SizedBox(
                            width: double.infinity,
                            child: Text(
                              kPaymentModeLabels[kPaymentModes[i]] ??
                                  kPaymentModes[i],
                              textAlign: TextAlign.center,
                            ),
                          ),
                          selected: _mode == kPaymentModes[i],
                          onSelected: (_) =>
                              setState(() => _mode = kPaymentModes[i]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
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

/// Landlord card for the tenant's profile.
///
/// Pulled out of the page build so the section can be rendered unconditionally
/// (it used to be inline inside an `if (tenancy != null)` spread) and so the
/// two contact actions have somewhere to live. Phone may be empty - in that case
/// the actions are disabled rather than hidden, so the card never changes shape.
class _OwnerCard extends StatelessWidget {
  final String name;
  final String phone;
  final String flatLabel;

  /// Tenancy id, used for the shared owner <-> tenant message thread.
  final String? requestId;
  const _OwnerCard({
    required this.name,
    required this.phone,
    required this.flatLabel,
    this.requestId,
  });

  Future<void> _launch(BuildContext context, Uri uri, String failure) async {
    try {
      final ok = await launchUrl(uri);
      if (!ok && context.mounted) {
        showAppToast(context, failure, kind: AppToastKind.alert);
      }
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, failure, kind: AppToastKind.alert);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final hasPhone = phone.isNotEmpty;
    return PulseCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulseAvatar(name: name, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: t.fg1)),
                    const SizedBox(height: 2),
                    Text(
                      hasPhone
                          ? phone
                          : 'No number on record \u2014 ask the society office',
                      // kTabularFigures is a whole TextStyle, not a
                      // List<FontFeature>, so it is composed with copyWith
                      // rather than passed to fontFeatures. Tabular digits only
                      // for the phone number - it keeps the number from
                      // shifting width, and means nothing for prose.
                      style: (hasPhone ? kTabularFigures : const TextStyle())
                          .copyWith(
                        fontSize: 12.5,
                        color: hasPhone ? t.fg2 : t.fg4,
                      ),
                    ),
                    if (flatLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('Owner of $flatLabel',
                          style: TextStyle(fontSize: 11.5, color: t.fg4)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PulseButton(
                  label: 'Call',
                  icon: Icons.call_rounded,
                  size: PulseBtnSize.sm,
                  disabled: !hasPhone,
                  onTap: () => _launch(context, Uri.parse('tel:$phone'),
                      'Could not open the phone dialer'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: requestId == null
                    // No tenancy id: fall back to plain SMS. Better a working
                    // text message than an in-app thread that 404s.
                    ? PulseButton(
                        label: 'Message',
                        icon: Icons.sms_outlined,
                        size: PulseBtnSize.sm,
                        variant: PulseBtnVariant.secondary,
                        disabled: !hasPhone,
                        onTap: () => _launch(context, Uri.parse('sms:$phone'),
                            'Could not open your messaging app'),
                      )
                    // In-app now that the notes route accepts a tenant and
                    // pushes the other party (it used to be owner-only, which is
                    // why this was an SMS shortcut). Notify and notes are the
                    // same thing: posting a message IS the notification.
                    : PulseButton(
                        label: 'Notify',
                        icon: Icons.forum_outlined,
                        size: PulseBtnSize.sm,
                        variant: PulseBtnVariant.secondary,
                        onTap: () =>
                            showOwnerThreadSheet(context, requestId!, name),
                      ),
              ),
            ],
          ),
          if (requestId != null) ...[
            const SizedBox(height: 6),
            Text(
              'Notify sends an in-app message your owner gets as a notification.',
              style: TextStyle(fontSize: 11, color: t.fg4),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared owner <-> tenant message thread.
///
/// The backing route used to be owner-only and wrote a bare string, so a tenant
/// had no way to reach their landlord from inside the app at all -- the card
/// offered an SMS shortcut as a stopgap. It now accepts either party, keeps an
/// ordered `noteThread[]`, and pushes whoever did not write the message. That
/// makes "notify" and "notes" one feature instead of two half-built ones: the
/// message IS the notification.
Future<void> showOwnerThreadSheet(
    BuildContext context, String requestId, String ownerName) {
  return showPulseSheet<void>(
    context,
    title: 'Messages with $ownerName',
    full: true,
    builder: (ctx) => _OwnerThreadBody(
      dio: context.read<Dio>(),
      requestId: requestId,
    ),
  );
}

class _OwnerThreadBody extends StatefulWidget {
  final Dio dio;
  final String requestId;
  const _OwnerThreadBody({required this.dio, required this.requestId});

  @override
  State<_OwnerThreadBody> createState() => _OwnerThreadBodyState();
}

class _OwnerThreadBodyState extends State<_OwnerThreadBody> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _notes = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notes = await fetchTenancyNotes(widget.dio, widget.requestId);
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      showAppToast(context, 'Type a message first.', kind: AppToastKind.alert);
      return;
    }
    Haptics.light();
    setState(() => _sending = true);
    try {
      final notes = await postTenancyNote(widget.dio, widget.requestId, text);
      if (!mounted) return;
      _controller.clear();
      setState(() {
        // The POST returns the full thread, so there is no need to re-GET.
        _notes = notes;
        _sending = false;
      });
      showAppToast(context, 'Sent \u2014 your owner has been notified.',
          kind: AppToastKind.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showAppToast(context, apiErrorMessage(e), kind: AppToastKind.alert);
    }
  }

  /// Deliberately terse: "14 Mar, 6:05 pm". No relative time here -- on a thread
  /// that may go weeks between messages "3 weeks ago" is less useful than a date.
  String _stamp(Object? raw) {
    final at = DateTime.tryParse('$raw')?.toLocal();
    if (at == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');
    final suffix = at.hour < 12 ? 'am' : 'pm';
    return '${at.day} ${months[at.month - 1]}, $hour12:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.danger)),
                const SizedBox(height: 10),
                PulseButton(
                    label: 'Try again',
                    size: PulseBtnSize.sm,
                    variant: PulseBtnVariant.secondary,
                    onTap: _load),
              ],
            ),
          )
        else if (_notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'No messages yet. Anything you send here reaches your owner as a\n'
              'notification \u2014 rent queries, repairs, notice of leaving.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: t.fg3, height: 1.45),
            ),
          )
        else
          ConstrainedBox(
            // Bounded so a long thread scrolls inside the sheet instead of
            // overflowing it.
            constraints: const BoxConstraints(maxHeight: 340),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 4),
              itemCount: _notes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final n = _notes[i];
                final fromTenant = '${n['by']}' == 'Tenant';
                return Align(
                  // Yours on the right, the owner's on the left: the oldest
                  // readable chat convention there is.
                  alignment:
                      fromTenant ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: fromTenant ? t.brand.withValues(alpha: 0.10) : t.surface3,
                      borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
                      border: Border.all(color: t.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${n['text'] ?? ''}',
                            style: TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                color: t.fg1,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          '${fromTenant ? 'You' : 'Owner'} \u00b7 ${_stamp(n['at'])}',
                          style: TextStyle(fontSize: 10.5, color: t.fg4),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        PulseField(
          label: 'Message',
          hint: 'e.g. The geyser in the bathroom has stopped working.',
          controller: _controller,
          maxLines: 3,
          enabled: !_sending,
        ),
        const SizedBox(height: 10),
        PulseButton(
          label: 'Send to owner',
          icon: Icons.send_rounded,
          full: true,
          loading: _sending,
          disabled: _sending,
          onTap: _send,
        ),
      ],
    );
  }
}
