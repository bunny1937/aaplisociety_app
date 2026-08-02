import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_toast.dart';
import '../member/pulse/pulse.dart';
import 'tenancy_thread_sheet.dart';
import 'tenant_documents_sheet.dart';
import 'tenant_ui.dart';

enum TenantDetailKind { active, request, past }

/// One detail surface for every tenant record.
///
/// Audit fix 3.7 flaw 3 / 3.8 flaw 3: tenant details were shown in two
/// different `AlertDialog`s (one on My Tenant, one on Tenant History) with
/// different field orders, different labels for the same data, and no way to
/// call the person. Both are replaced by this sheet, which matches the
/// mockup's `Row2` detail layout.
Future<void> showTenantDetailSheet(
  BuildContext context, {
  required Map tenancy,
  required TenantDetailKind kind,
}) {
  return showPulseSheet<void>(
    context,
    title: displayName(tenancy['tenantName'], fallback: 'Tenant'),
    builder: (ctx) => _TenantDetailBody(tenancy: tenancy, kind: kind),
  );
}

class _TenantDetailBody extends StatelessWidget {
  final Map tenancy;
  final TenantDetailKind kind;
  const _TenantDetailBody({required this.tenancy, required this.kind});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final phone = tenancy['tenantPhone']?.toString();
    final email = tenancy['tenantEmail']?.toString();
    final notes = (tenancy['notes'] as List?)?.cast<Map>() ?? const <Map>[];
    final missing = missingDocs(tenancy);
    final status = tenancy['status']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            PulseAvatar(
                name: displayName(tenancy['tenantName'], fallback: 'T'),
                size: 44,
                ring: kind == TenantDetailKind.active),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName(tenancy['tenantName'], fallback: 'Tenant'),
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: t.fg1),
                  ),
                  const SizedBox(height: 3),
                  PulsePill(
                    label: switch (kind) {
                      TenantDetailKind.active => 'ACTIVE TENANCY',
                      TenantDetailKind.request =>
                        (status ?? 'PENDING').toUpperCase(),
                      TenantDetailKind.past => 'PAST TENANCY',
                    },
                    tone: switch (kind) {
                      TenantDetailKind.active => PulseTone.approved,
                      TenantDetailKind.request => rentTone(status),
                      TenantDetailKind.past => PulseTone.neutral,
                    },
                    small: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Contacting the tenant is the most common reason to open this sheet,
        // so Call/Email are primary actions here rather than buried text.
        if ((phone != null && phone.isNotEmpty) ||
            (email != null && email.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                if (phone != null && phone.isNotEmpty)
                  Expanded(
                    child: PulseButton(
                      label: 'Call',
                      icon: Icons.call_rounded,
                      variant: PulseBtnVariant.secondary,
                      size: PulseBtnSize.sm,
                      full: true,
                      onTap: () => _launch(context, 'tel:$phone',
                          'Could not open the phone dialer'),
                    ),
                  ),
                if (phone != null &&
                    phone.isNotEmpty &&
                    email != null &&
                    email.isNotEmpty)
                  const SizedBox(width: 8),
                if (email != null && email.isNotEmpty)
                  Expanded(
                    child: PulseButton(
                      label: 'Email',
                      icon: Icons.mail_outline_rounded,
                      variant: PulseBtnVariant.secondary,
                      size: PulseBtnSize.sm,
                      full: true,
                      onTap: () => _launch(context, 'mailto:$email',
                          'Could not open your mail app'),
                    ),
                  ),
              ],
            ),
          ),

        TenantKv('Phone', phone),
        TenantKv('Email', email),
        TenantKv('Rent / month', inr(tenancy['rentPerMonth'] as num?)),
        TenantKv('Deposit', inr(tenancy['depositAmount'] as num?)),
        TenantKv(
            'Lease',
            fmtLeaseRange(
                tenancy['leaseStartDate'], tenancy['leaseEndDate'])),
        if (kind == TenantDetailKind.active)
          // Was `loginEnabled == true`, which reported "Disabled" for every
          // tenancy whose flag the API never sent. See resolveLoginEnabled().
          TenantKv('App login',
              resolveLoginEnabled(tenancy) ? 'Enabled' : 'Disabled'),
        if (kind == TenantDetailKind.past)
          TenantKv('Move-out reason', tenancy['moveOutReason']?.toString()),
        // This row used to be a dead pill: it announced "3 missing" and that
        // was the end of the conversation. No way to see the one document that
        // WAS uploaded, no way to open it, accept it, or send it back. Now it
        // is a door into the real review sheet.
        TenantKv(
          'Documents',
          null,
          valueWidget: Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PulsePill(
                  label: missing.isEmpty
                      ? 'All ${kTenantDocFields.length} on file'
                      : '${missing.length} missing',
                  tone:
                      missing.isEmpty ? PulseTone.approved : PulseTone.pending,
                  small: true,
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: t.fg4),
              ],
            ),
          ),
          onTap: kind == TenantDetailKind.request
              ? null
              : () => showTenantDocumentsSheet(context,
                  tenancy: tenancy, asOwner: true),
        ),

        // The owner received a push saying their tenant had written to them and
        // then had nowhere to read it. The thread lives here now.
        if (kind == TenantDetailKind.active &&
            '${tenancy['_id'] ?? ''}'.isNotEmpty)
          TenantKv(
            'Messages',
            null,
            last: notes.isEmpty,
            valueWidget: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Open chat',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: t.brand)),
                  Icon(Icons.chevron_right_rounded, size: 18, color: t.brand),
                ],
              ),
            ),
            onTap: () => showTenancyThreadSheet(
              context,
              requestId: '${tenancy['_id']}',
              title:
                  'Messages with ${displayName(tenancy['tenantName'], fallback: 'your tenant')}',
              mineIsTenant: false,
            ),
          ),

        if (notes.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('NOTES',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: t.fg4,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          ...notes.map(
            (n) => Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: t.hairline, width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n['text']?.toString() ?? n['note']?.toString() ?? '',
                      style: TextStyle(fontSize: 13, color: t.fg1)),
                  const SizedBox(height: 3),
                  Text(fmtDate(n['date'] ?? n['createdAt']),
                      style: TextStyle(fontSize: 11, color: t.fg4)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _launch(
      BuildContext context, String uri, String failureMessage) async {
    final ok = await launchUrl(Uri.parse(uri));
    if (!ok && context.mounted) {
      showAppToast(context, failureMessage, kind: AppToastKind.alert);
    }
  }
}
