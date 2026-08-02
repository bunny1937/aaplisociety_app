import 'package:flutter/material.dart';
import '../../core/theme/haptics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/hold_to_confirm.dart';
import '../../core/widgets/pulse_field.dart';
import '../member/pulse/pulse.dart';

/// Shared building blocks for the Tenancy suite, ported 1:1 from the approved
/// mockup (`ScreensTenant.jsx` / `ScreensManageTenants.jsx`).
///
/// Mapping of mockup CSS vars to app tokens:
///   --m-surface -> t.surface     --m-border   -> t.border
///   --m-hairline -> t.hairline   --m-fg-1..5  -> t.fg1..fg5
///   --m-brand(-soft) -> t.brand/t.brandSoft   (same #1E3A8A)
///   --m-success(-soft) / --m-warning(-soft) / --m-danger(-soft) -> ditto
/// The mockup's numbers (radius 11/13, font 10.5/11.5/12.5/13/15, gap 8/10/12)
/// are preserved exactly rather than rounded to Material defaults.

/// Mockup `Switch` — 40x24 track, 20px knob, success when on.
class TenantSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String labelOn;
  final String labelOff;
  final bool busy;
  const TenantSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.labelOn = 'Enabled',
    this.labelOff = 'Disabled',
    this.busy = false,
  });
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Semantics(
      toggled: value,
      label: 'Tenant app login',
      child: GestureDetector(
        onTap: busy
            ? null
            : () {
                Haptics.select();
                onChanged(!value);
              },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 24,
              decoration: BoxDecoration(
                color: value ? t.success : t.fg5,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    alignment:
                        value ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Color(0x40000000),
                                blurRadius: 3,
                                offset: Offset(0, 1))
                          ],
                        ),
                        child: busy
                            ? Padding(
                                padding: const EdgeInsets.all(4),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: value ? t.success : t.fg4),
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value ? labelOn : labelOff,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: value ? t.success : t.fg4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mockup `Row2` — key/value row inside a detail sheet.
class TenantKv extends StatelessWidget {
  final String label;
  final String? value;
  final bool last;
  final Widget? valueWidget;
  const TenantKv(this.label, this.value,
      {super.key, this.last = false, this.valueWidget});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: t.hairline, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Flexible, not a fixed 118px label column — the old `_Kv` truncated
          // labels at 1.3x text scale (audit 3.5 flaw 6 / X-9).
          Expanded(
            flex: 4,
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: t.fg4)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: valueWidget ??
                Text(
                  (value == null || value!.isEmpty) ? kEmDash : value!,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.fg1),
                ),
          ),
        ],
      ),
    );
  }
}

/// Mockup stat cell used in the TenancyCard 2x2 grid.
class TenantStat extends StatelessWidget {
  final String label;
  final String value;
  final bool money;
  const TenantStat(
      {super.key,
      required this.label,
      required this.value,
      this.money = false});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: t.fg4,
              letterSpacing: 0.3),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: money ? 15 : 13,
            fontWeight: money ? FontWeight.w800 : FontWeight.w600,
            color: t.fg1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Tone mapping for a rent-payment status string.
PulseTone rentTone(String? status) => switch (status?.toLowerCase()) {
      'pending' => PulseTone.pending,
      'rejected' => PulseTone.rejected,
      'confirmed' || 'approved' => PulseTone.approved,
      _ => PulseTone.neutral,
    };

/// Mockup `RentTile` — one rent record, with optional owner actions.
class RentTile extends StatelessWidget {
  final Map rent;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool busy;
  const RentTile({
    super.key,
    required this.rent,
    this.onConfirm,
    this.onReject,
    this.onEdit,
    this.onDelete,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final status = rent['status']?.toString() ?? 'Pending';
    final amount = rent['amount'] as num?;
    final mode = rent['paymentMode']?.toString();
    final byTenant = rent['submittedByRole']?.toString() == 'Tenant';
    final reason = rent['rejectionReason']?.toString();
    final hasActions = onConfirm != null ||
        onReject != null ||
        onEdit != null ||
        onDelete != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PulseCard(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ₹32,000 · Jul 2026 — amount leads, period is secondary.
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: inr(amount),
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: t.fg1,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            TextSpan(
                              text: '  \u00B7 ${fmtPeriodId(rent['month'])}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: t.fg4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (mode != null && mode.isNotEmpty) mode,
                          fmtDate(rent['paidAt']),
                          byTenant ? 'submitted by tenant' : 'recorded by you',
                        ].join(' \u00B7 '),
                        style: TextStyle(fontSize: 11.5, color: t.fg4),
                      ),
                      if (status.toLowerCase() == 'rejected' &&
                          reason != null &&
                          reason.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(reason,
                              style:
                                  TextStyle(fontSize: 11.5, color: t.danger)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                PulsePill(
                    label: status, tone: rentTone(status), small: true),
              ],
            ),
            if (hasActions) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border:
                      Border(top: BorderSide(color: t.hairline, width: 1)),
                ),
                child: Row(
                  children: [
                    if (onConfirm != null)
                      Expanded(
                        child: PulseButton(
                          label: 'Confirm',
                          icon: Icons.check_circle_outline_rounded,
                          variant: PulseBtnVariant.success,
                          size: PulseBtnSize.sm,
                          full: true,
                          loading: busy,
                          onTap: onConfirm,
                        ),
                      ),
                    if (onConfirm != null && onReject != null)
                      const SizedBox(width: 6),
                    if (onReject != null)
                      Expanded(
                        child: PulseButton(
                          label: 'Reject',
                          icon: Icons.cancel_outlined,
                          // Secondary, not a second filled button: rejecting
                          // is the destructive path and must not mirror
                          // Confirm's visual weight (audit X-8).
                          variant: PulseBtnVariant.secondary,
                          size: PulseBtnSize.sm,
                          full: true,
                          onTap: onReject,
                        ),
                      ),
                    if (onEdit != null) ...[
                      const SizedBox(width: 6),
                      PulseIconButton(
                          icon: Icons.edit_outlined,
                          size: 32,
                          onTap: onEdit),
                    ],
                    if (onDelete != null) ...[
                      const SizedBox(width: 6),
                      PulseIconButton(
                          icon: Icons.delete_outline_rounded,
                          size: 32,
                          onTap: onDelete),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The four documents a tenancy requires. Mirrors `window.TenantDocFields`
/// and the backend's `documents.<field>Key` shape.
class TenantDocField {
  final String field;
  final String label;
  const TenantDocField(this.field, this.label);
}

const List<TenantDocField> kTenantDocFields = [
  TenantDocField('contract', 'Lease Contract'),
  TenantDocField('signature', 'Tenant Signature'),
  TenantDocField('aadhaar', 'Aadhaar Card'),
  TenantDocField('policeVerification', 'Police Verification'),
];

/// Which required documents are missing from a tenancy record.
List<TenantDocField> missingDocs(Map? tenancy) {
  final docs = (tenancy?['documents'] as Map?) ?? const {};
  return kTenantDocFields.where((f) {
    final v = docs['${f.field}Key'] ?? docs[f.field];
    return v == null || v.toString().isEmpty || v.toString() == 'null';
  }).toList();
}

/// Is the tenant's app login switched on?
///
/// This used to be a bare `tenancy['loginEnabled'] == true`, which is wrong in
/// two separate ways and is why the switch sat grey and "disabled" for a tenant
/// who had been logging in for weeks:
///
///  1. The field simply was not in the payload (the tenant-history DTO dropped
///     it), so `== true` was false and the switch rendered OFF.
///  2. Even with the DTO fixed, ABSENT is not the same as DISABLED. A tenancy
///     approved before the login flag existed has a perfectly working login and
///     no flag to prove it. Defaulting those to OFF tells the owner a lie and
///     invites them to "enable" something that was never off.
///
/// So: an explicit boolean always wins; otherwise an approved/active tenancy is
/// treated as enabled, which is what the backend actually does.
bool resolveLoginEnabled(Map? tenancy) {
  if (tenancy == null) return false;
  for (final key in const [
    'loginEnabled',
    'tenantLoginEnabled',
    'appLoginEnabled',
    'isActive',
  ]) {
    final v = tenancy[key];
    if (v is bool) return v;
    if (v is String && (v == 'true' || v == 'false')) return v == 'true';
  }
  final status = '${tenancy['status'] ?? ''}'.toLowerCase();
  return status == 'approved' || status == 'active';
}

/// Mockup `TenancyCard` — the hero of My Tenant.
class TenancyCard extends StatelessWidget {
  final Map tenancy;
  final bool active;
  final VoidCallback? onEndLease;
  final VoidCallback? onEditDates;
  final VoidCallback? onNote;
  final VoidCallback? onRemind;
  final ValueChanged<bool>? onToggleLogin;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onFixDocs;
  final bool loginBusy;
  final bool? loginOverride;
  const TenancyCard({
    super.key,
    required this.tenancy,
    this.active = false,
    this.onEndLease,
    this.onEditDates,
    this.onNote,
    this.onRemind,
    this.onToggleLogin,
    this.onOpenDetail,
    this.onFixDocs,
    this.loginBusy = false,
    this.loginOverride,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final name = displayName(tenancy['tenantName'], fallback: 'Tenant');
    final missing = missingDocs(tenancy);
    // `loginOverride` is the optimistic value the parent applies the instant a
    // toggle succeeds, so the switch never disagrees with the toast that just
    // said "Tenant login enabled".
    final loginEnabled = loginOverride ?? resolveLoginEnabled(tenancy);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PulseCard(
        padding: const EdgeInsets.all(16),
        onTap: active ? onOpenDetail : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PulseAvatar(name: name, size: 46, ring: active),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: t.fg1),
                            ),
                          ),
                          const SizedBox(width: 8),
                          PulsePill(
                            label: active ? 'ACTIVE' : 'ENDED',
                            tone: active
                                ? PulseTone.approved
                                : PulseTone.neutral,
                            small: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tenancy['tenantPhone']?.toString() ?? kEmDash,
                        style: TextStyle(fontSize: 12, color: t.fg4),
                      ),
                    ],
                  ),
                ),
                if (active && onOpenDetail != null)
                  Icon(Icons.chevron_right_rounded, size: 22, color: t.fg5),
              ],
            ),
            const SizedBox(height: 12),
            // 2x2 stat grid, exactly as the mockup.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TenantStat(
                      label: 'Rent / month',
                      value: inr(tenancy['rentPerMonth'] as num?),
                      money: true),
                ),
                Expanded(
                  child: TenantStat(
                      label: 'Deposit',
                      value: inr(tenancy['depositAmount'] as num?),
                      money: true),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TenantStat(
                      label: 'Lease start',
                      value: fmtDate(tenancy['leaseStartDate'])),
                ),
                Expanded(
                  child: TenantStat(
                      label: 'Lease end',
                      value: fmtLeaseEnd(tenancy['leaseEndDate'])),
                ),
              ],
            ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 12),
              // Actionable, not just a warning strip (audit 3.7 flaw 5).
              InkWell(
                onTap: onFixDocs,
                borderRadius: BorderRadius.circular(11),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.warningSoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined,
                          size: 15, color: t.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Missing documents: '
                          '${missing.map((m) => m.label).join(', ')}',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: t.warning),
                        ),
                      ),
                      if (onFixDocs != null)
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: t.warning),
                    ],
                  ),
                ),
              ),
            ],
            if (active) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border:
                      Border(top: BorderSide(color: t.hairline, width: 1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('Tenant app login',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: t.fg2)),
                    ),
                    TenantSwitch(
                      value: loginEnabled,
                      busy: loginBusy,
                      onChanged: onToggleLogin ?? (_) {},
                    ),
                  ],
                ),
              ),
              // Mockup renders four ghost/danger chips in a flex-wrap.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onRemind != null)
                    PulseButton(
                        label: 'Rent reminder',
                        icon: Icons.notifications_none_rounded,
                        variant: PulseBtnVariant.ghost,
                        size: PulseBtnSize.sm,
                        onTap: onRemind),
                  if (onEditDates != null)
                    PulseButton(
                        label: 'Lease dates',
                        icon: Icons.calendar_today_rounded,
                        variant: PulseBtnVariant.ghost,
                        size: PulseBtnSize.sm,
                        onTap: onEditDates),
                  if (onNote != null)
                    PulseButton(
                        label: 'Add note',
                        icon: Icons.sticky_note_2_outlined,
                        variant: PulseBtnVariant.ghost,
                        size: PulseBtnSize.sm,
                        onTap: onNote),
                  if (onEndLease != null)
                    PulseButton(
                        label: 'End lease',
                        icon: Icons.logout_rounded,
                        // Outlined danger, not filled: it sits in a row of
                        // ghost chips and must not read as the page's CTA.
                        variant: PulseBtnVariant.secondary,
                        size: PulseBtnSize.sm,
                        onTap: onEndLease),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mockup `DocRow` — one required document with its upload state.
class DocRow extends StatelessWidget {
  final String label;
  final bool uploaded;
  final bool uploading;
  final String? error;
  final VoidCallback onUpload;
  const DocRow({
    super.key,
    required this.label,
    required this.uploaded,
    required this.onUpload,
    this.uploading = false,
    this.error,
  });
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final failed = error != null && error!.isNotEmpty;
    final (Color bg, Color fg, IconData icon) = failed
        ? (t.dangerSoft, t.danger, Icons.error_outline_rounded)
        : uploaded
            ? (t.successSoft, t.success, Icons.check_circle_outline_rounded)
            : (t.surface3, t.fg4, Icons.description_outlined);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration:
                BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: uploading
                ? SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: t.brand),
                  )
                : Icon(icon, size: 16, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.fg1)),
                const SizedBox(height: 1),
                Text(
                  failed
                      ? error!
                      : uploading
                          ? 'Uploading\u2026'
                          : uploaded
                              ? 'Uploaded'
                              : 'Required',
                  style: TextStyle(
                    fontSize: 11,
                    color: failed
                        ? t.danger
                        : uploaded
                            ? t.success
                            : t.fg4,
                  ),
                ),
              ],
            ),
          ),
          PulseButton(
            label: failed
                ? 'Retry'
                : uploaded
                    ? 'Replace'
                    : 'Upload',
            variant: uploaded && !failed
                ? PulseBtnVariant.secondary
                : PulseBtnVariant.primary,
            size: PulseBtnSize.sm,
            disabled: uploading,
            onTap: onUpload,
          ),
        ],
      ),
    );
  }
}

/// Mockup `PromptSheet` — single-input bottom sheet reused for notes, lease
/// dates, rejection reasons and amount edits.
Future<String?> showPromptSheet(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String? hint,
  String submitLabel = 'Save',
  bool danger = false,
  bool multiline = false,
  TextInputType? keyboardType,
}) {
  return showPulseSheet<String>(
    context,
    title: title,
    builder: (ctx) =>
        _PromptBody(
      label: label,
      initial: initial,
      hint: hint,
      submitLabel: submitLabel,
      danger: danger,
      multiline: multiline,
      keyboardType: keyboardType,
    ),
  );
}

class _PromptBody extends StatefulWidget {
  final String label;
  final String initial;
  final String? hint;
  final String submitLabel;
  final bool danger;
  final bool multiline;
  final TextInputType? keyboardType;
  const _PromptBody({
    required this.label,
    required this.initial,
    required this.hint,
    required this.submitLabel,
    required this.danger,
    required this.multiline,
    this.keyboardType,
  });
  @override
  State<_PromptBody> createState() => _PromptBodyState();
}

class _PromptBodyState extends State<_PromptBody> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);
  String? _error;
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    if (v.isEmpty) {
      setState(() => _error = 'This can\'t be empty');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseField(
          label: widget.label,
          controller: _c,
          hint: widget.hint,
          error: _error,
          maxLines: widget.multiline ? 4 : 1,
          keyboardType: widget.keyboardType,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 16),
        if (widget.danger)
          DestructiveConfirmActions(
            confirmLabel: widget.submitLabel,
            onConfirm: _submit,
            onCancel: () => Navigator.of(context).maybePop(),
          )
        else
          Row(
            children: [
              Expanded(
                child: PulseButton(
                    label: 'Cancel',
                    variant: PulseBtnVariant.secondary,
                    full: true,
                    onTap: () => Navigator.of(context).maybePop()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PulseButton(
                    label: widget.submitLabel, full: true, onTap: _submit),
              ),
            ],
          ),
      ],
    );
  }
}

/// Mockup activity feed row (28px brand-soft icon chip + text + date).
class ActivityRow extends StatelessWidget {
  final Map item;
  final bool last;
  const ActivityRow({super.key, required this.item, this.last = false});

  static const Map<String, IconData> _icons = {
    'bell': Icons.notifications_none_rounded,
    'check-circle': Icons.check_circle_outline_rounded,
    'x-circle': Icons.cancel_outlined,
    'file-text': Icons.sticky_note_2_outlined,
    'calendar': Icons.calendar_today_rounded,
    'log-out': Icons.logout_rounded,
    'user-plus': Icons.person_add_alt_rounded,
    'clipboard-list': Icons.assignment_outlined,
    'key-round': Icons.vpn_key_outlined,
    'indian-rupee': Icons.currency_rupee_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: t.hairline, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                color: t.brandSoft, borderRadius: BorderRadius.circular(9)),
            alignment: Alignment.center,
            child: Icon(
              _icons[item['icon']?.toString()] ?? Icons.info_outline_rounded,
              size: 13,
              color: t.brand,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item['text']?.toString() ?? '',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.fg1),
            ),
          ),
          const SizedBox(width: 8),
          Text(timeAgo(item['date']),
              style: TextStyle(fontSize: 11, color: t.fg4)),
        ],
      ),
    );
  }
}

/// Section heading inside the tenancy screens (mockup: 13px/750 fg-1).
class TenantSectionTitle extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const TenantSectionTitle(this.label,
      {super.key,
      this.trailing,
      this.padding = const EdgeInsets.only(bottom: 8)});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: t.fg1)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Mockup's brand-soft / neutral explainer banner.
class TenantBanner extends StatelessWidget {
  final String text;
  final bool neutral;
  final IconData? icon;
  const TenantBanner(this.text,
      {super.key, this.neutral = false, this.icon});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: neutral ? t.surface3 : t.brandSoft,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: neutral ? t.fg3 : t.brand),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.5,
                color: neutral ? t.fg2 : t.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
