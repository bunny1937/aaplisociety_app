import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_error.dart';
import '../../core/network/sos_api.dart';
import '../../core/theme/haptics.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/async_view.dart';
import '../../core/socket/socket_bus.dart';
import 'pulse/pulse.dart';
import 'pulse/visitor_pass_card.dart';

/// Visitors tab — port of ui_kits/member-v2 `ScreensVisitorsProfile.jsx`
/// `VisitorsScreen`: at-the-gate-now (approve/deny) / your gate passes /
/// today's log. The FAB only generates gate passes now — the old
/// member-initiated "walk-in guest" pre-register (POST /visitors, decided
/// via `_decide` above) was removed per user feedback: a walk-in shows up
/// unannounced, so the *guard* should be the one raising that request, not
/// the member pre-filing it for someone who hasn't arrived yet. The
/// approve/deny section above is left in place for whatever creates a
/// Pending visitor next (a future guard-side flow, or the web admin/security
/// portal against the same DB). The design's "offline confirm" tier has no
/// backing field on the real Visitor model (see MEMBER_V2_GAPS.md) so it's
/// omitted rather than faked.
class VisitorsPage extends StatefulWidget {
  const VisitorsPage({super.key});
  @override
  State<VisitorsPage> createState() => _VisitorsPageState();
}

class _VisitorsPageState extends State<VisitorsPage> {
  final _listKey = GlobalKey<AsyncViewState<Map>>();
  @override
  void initState() {
    super.initState();
    SocketBus.visitorEvents.addListener(_reload);
  }

  @override
  void dispose() {
    SocketBus.visitorEvents.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _listKey.currentState?.reload();
  Future<void> _decide(BuildContext context, String id, String decision,
      {String? note}) async {
    Haptics.medium();
    try {
      await context.read<Dio>().post('/visitors/$id/decision', data: {
        'decision': decision,
        // Optional note the resident sends back to the guard with their
        // approve/deny so the guard has context at the gate.
        if (note != null && note.isNotEmpty) 'note': note,
      });
      Haptics.success();
      _reload();
    } on DioException catch (err) {
      Haptics.heavy();
      if (context.mounted) {
        showPulseToast(
            context, apiErrorMessage(err, 'Could not update visitor'),
            kind: PulseToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final dio = context.read<Dio>();
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          AsyncView<Map>(
            key: _listKey,
            fetch: () async {
              final results = await Future.wait(
                  [dio.get('/visitors'), dio.get('/visitors/passes')]);
              return {
                'visitors': results[0].data['visitors'] as List,
                'passes': results[1].data['passes'] as List
              };
            },
            cacheKey: '/visitors',
            builder: (context, data) {
              final all = data['visitors'] as List;
              final passes = data['passes'] as List;
              final pending =
                  all.where((v) => (v as Map)['status'] == 'Pending').toList();
              final today = all.where((v) {
                final d = DateTime.tryParse('${(v as Map)['createdAt']}')
                    ?.toLocal();
                final now = DateTime.now();
                return d != null &&
                    d.year == now.year &&
                    d.month == now.month &&
                    d.day == now.day;
              }).toList();
              final activePasses = passes
                  .where((p) => (p as Map)['effectiveStatus'] == 'Active')
                  .toList();
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(
                      child: PulseTopBar(
                          title: 'Visitors',
                          subtitle: 'Gate approvals & today\'s log')),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Text('At the gate now',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: t.fg1)),
                    ),
                  ),
                  if (pending.isEmpty)
                    const SliverToBoxAdapter(
                        child: PulseEmptyState(
                            illo: PulseIllo.allClear,
                            title: 'All clear',
                            subtitle: 'No one is waiting at the gate'))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      sliver: SliverList.separated(
                        itemCount: pending.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _GateCard(
                            visitor: pending[i] as Map,
                            onDecide: (d, note) => _decide(
                                context, '${(pending[i] as Map)['_id']}', d,
                                note: note)),
                      ),
                    ),
                  if (activePasses.isNotEmpty) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text('Your gate passes',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: t.fg1)),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      sliver: SliverList.separated(
                        itemCount: activePasses.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _PassRow(pass: activePasses[i] as Map),
                      ),
                    ),
                  ],
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Text("Today's visitors",
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: t.fg1)),
                    ),
                  ),
                  if (today.isEmpty)
                    const SliverToBoxAdapter(
                        child: PulseEmptyState(
                            illo: PulseIllo.noData,
                            title: 'No visitors logged today'))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      sliver: SliverList.separated(
                        itemCount: today.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _TodayRow(visitor: today[i] as Map),
                      ),
                    ),
                ],
              );
            },
          ),
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton(
              backgroundColor: t.brand,
              onPressed: () => _openGeneratePass(context),
              child: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openGeneratePass(BuildContext context) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    var type = 'Guest';
    var validity = const Duration(hours: 4);
    var submitting = false;
    await showPulseSheet<void>(
      context,
      title: 'Generate a gate pass',
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final t = sheetCtx.pulse;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _labeled(
                  t,
                  'Visitor name',
                  TextField(
                      controller: name,
                      style: TextStyle(color: t.fg1),
                      decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          prefixIcon: Icon(Icons.person_outline_rounded)))),
              const SizedBox(height: 12),
              _labeled(
                  t,
                  'Phone number',
                  TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      style: TextStyle(color: t.fg1),
                      decoration: const InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          prefixIcon: Icon(Icons.phone_outlined)))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['Guest', 'Delivery', 'Cab', 'Service'].map((ty) {
                  final sel = ty == type;
                  return GestureDetector(
                    onTap: () => setSheet(() => type = ty),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                          color: sel ? t.brandSoft : t.surface,
                          border: Border.all(color: sel ? t.brand : t.border),
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(ty,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: sel ? t.brand : t.fg3)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text('Valid for',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: t.fg3)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  (const Duration(hours: 4), '4 hours'),
                  (const Duration(hours: 12), '12 hours'),
                  (const Duration(days: 1), 'Today'),
                  (const Duration(days: 7), '7 days'),
                ].map((opt) {
                  final sel = opt.$1 == validity;
                  return GestureDetector(
                    onTap: () => setSheet(() => validity = opt.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                          color: sel ? t.brandSoft : t.surface,
                          border: Border.all(color: sel ? t.brand : t.border),
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(opt.$2,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: sel ? t.brand : t.fg3)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              PulseButton(
                label: 'Generate pass',
                icon: Icons.qr_code_2_rounded,
                full: true,
                loading: submitting,
                onTap: () async {
                  final n = name.text.trim(), p = phone.text.trim();
                  if (n.length < 2) {
                    Haptics.heavy();
                    showPulseToast(sheetCtx, "Enter the visitor's name",
                        kind: PulseToastKind.error);
                    return;
                  }
                  if (!RegExp(r'^[0-9]{10}$').hasMatch(p)) {
                    Haptics.heavy();
                    showPulseToast(
                        sheetCtx, 'Enter a valid 10-digit phone number',
                        kind: PulseToastKind.error);
                    return;
                  }
                  setSheet(() => submitting = true);
                  final now = DateTime.now();
                  final expires = now.add(validity);
                  try {
                    final res = await sheetCtx
                        .read<Dio>()
                        .post('/visitors/pass', data: {
                      'visitorName': n,
                      'visitorPhone': p,
                      'purpose': type,
                      'passType': 'OneTime',
                      'validFrom': now.toUtc().toIso8601String(),
                      'expiresAt': expires.toUtc().toIso8601String(),
                      'maxUses': 1,
                    });
                    Haptics.success();
                    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    _reload();
                    if (context.mounted) {
                      await showVisitorPassCard(
                        context,
                        visitorName: n,
                        visitorPhone: p,
                        otp: '${res.data['otp']}',
                        generatedAt: now,
                        expiresAt: expires,
                      );
                    }
                  } on DioException catch (err) {
                    Haptics.heavy();
                    setSheet(() => submitting = false);
                    if (sheetCtx.mounted) {
                      showPulseToast(sheetCtx,
                          apiErrorMessage(err, 'Could not generate pass'),
                          kind: PulseToastKind.error);
                    }
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _labeled(PulseTokens t, String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: t.fg3)),
        const SizedBox(height: 6),
        Container(
            decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
            child: field),
      ],
    );
  }
}

class _GateCard extends StatefulWidget {
  final Map visitor;
  // Now carries the resident's optional note alongside the decision.
  final void Function(String decision, String note) onDecide;
  const _GateCard({required this.visitor, required this.onDecide});
  @override
  State<_GateCard> createState() => _GateCardState();
}

class _GateCardState extends State<_GateCard> {
  final _note = TextEditingController();
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final ok = await launchUrl(Uri.parse('tel:$phone'));
    if (!ok && mounted) {
      showPulseToast(context, 'Could not open the phone dialer',
          kind: PulseToastKind.error);
    }
  }

  // Full-screen, pinch-to-zoom view of the guest photo the guard shared.
  void _openPhoto(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.network(url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Text('Image unavailable',
                            style: TextStyle(color: Colors.white)))),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final visitor = widget.visitor;
    final photoUrl = '${visitor['photoUrl'] ?? ''}';
    final guardNote = '${visitor['note'] ?? ''}';
    // Guard/gate phone the resident can call. Optional on the payload — the
    // call button is simply hidden when the backend hasn't supplied one.
    final guardPhone =
        '${visitor['guardPhone'] ?? visitor['gatePhone'] ?? visitor['guardContactNumber'] ?? ''}';
    final guardName = '${visitor['guardName'] ?? ''}';
    final gateLabel = '${visitor['gateLabel'] ?? 'Main Gate'}';
    // The guest's own number, kept strictly separate from the guard number so
    // "Call guard" can never dial the visitor by mistake.
    final guestPhone = '${visitor['phone'] ?? visitor['phoneNumber'] ?? ''}';
    // Resident-facing explanation of a missing photo. The previous strings
    // leaked internal detail to end users ("no signed URL returned — R2
    // read/signing failed", plus the raw storage key). Residents get plain
    // language; the diagnostics belong in logs, not on a visitor card.
    final photoKey = '${visitor['photoKey'] ?? ''}';
    final String? photoProblem = photoUrl.isNotEmpty
        ? null
        : (photoKey.isNotEmpty
            ? 'Photo is still processing \u2014 try again in a moment.'
            : 'No photo was taken at the gate for this visitor.');
    // An SOS raised from this flat is not a visitor and must never render as
    // one. It was showing up here with a photo slot, "Call guest", a note box
    // and Allow/Deny buttons - asking a resident to approve their own
    // household's emergency. Bail out to a purpose-built card before any of
    // the visitor chrome below is built.
    if ('${visitor['entryMethod'] ?? ''}' == 'SOS') {
      final reason =
          '${visitor['purposeNote'] ?? visitor['note'] ?? ''}'.trim();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.dangerSoft,
          borderRadius: BorderRadius.circular(PulseTokens.radius),
          border: Border.all(color: t.danger, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emergency_rounded, color: t.danger, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Emergency raised for your flat',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: t.danger)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              reason.isEmpty
                  ? 'No reason was recorded. Security has been alerted.'
                  : reason,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: t.fg1),
            ),
            const SizedBox(height: 2),
            Text('Security and the society admin were notified automatically.',
                style: TextStyle(fontSize: 11.5, color: t.fg3)),
            const SizedBox(height: 12),
            PulseButton(
              label: 'Call the gate now',
              icon: Icons.support_agent_rounded,
              variant: PulseBtnVariant.danger,
              full: true,
              onTap: () {
                if (guardPhone.isNotEmpty) {
                  _call(guardPhone);
                } else {
                  showAppToast(context,
                      'No guard number on this alert. Call the gate from the '
                      'society directory.',
                      kind: AppToastKind.alert);
                }
              },
            ),
            const SizedBox(height: 8),
            _SosSafeButton(
              visitorId: '${visitor['_id']}',
              acknowledged: sosAcknowledged(visitor),
            ),
          ],
        ),
      );
    }
    return PulseCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Guest photo shared by the guard (tap to enlarge); falls back to
              // a person glyph when no photo was attached.
              // 44px was avatar-sized: you could not tell who was at your gate
              // without tapping through to the full-screen view, which is the
              // one thing this card exists to answer. 72px shows a recognisable
              // face at a glance and still leaves room for the name and the
              // quick-call button on the same row.
              GestureDetector(
                onTap: photoUrl.isNotEmpty ? () => _openPhoto(photoUrl) : null,
                child: Container(
                  width: 72,
                  height: 72,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                      color: t.warningSoft,
                      borderRadius: BorderRadius.circular(14)),
                  child: photoUrl.isNotEmpty
                      ? Image.network(photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                              Icons.broken_image_outlined,
                              color: t.danger,
                              size: 26))
                      : Icon(Icons.no_photography_outlined,
                          color: t.danger, size: 26),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${visitor['name'] ?? 'Visitor'}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: t.fg1)),
                    Text('${visitor['purpose'] ?? '—'}',
                        style: TextStyle(fontSize: 12, color: t.fg4)),
                  ],
                ),
              ),
              // Call the GUARD (never the guest). When the backend hasn't sent
              // a guard number we say so instead of dialling whatever number
              // happens to be on the payload.
              PulseIconButton(
                icon: Icons.support_agent_rounded,
                onTap: () {
                  if (guardPhone.isNotEmpty) {
                    _call(guardPhone);
                  } else {
                    showAppToast(context,
                        'No guard number on this entry. Call the gate from '
                        'the society directory instead.',
                        kind: AppToastKind.alert);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
              guardName.isNotEmpty
                  ? 'Logged by $guardName · $gateLabel'
                  : gateLabel,
              style: TextStyle(
                  fontSize: 11.5, color: t.fg3, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          // The two calls sit side by side as equal halves instead of being
          // dropped into a Wrap with the "Logged by" caption. In the Wrap they
          // reflowed unpredictably - sometimes both on the caption's line,
          // sometimes stacked - and being ghost-styled they read as text, not
          // buttons. The gate is always the left/primary target.
          Row(
            children: [
              Expanded(
                child: PulseButton(
                  label: 'Call guard',
                  icon: Icons.support_agent_rounded,
                  size: PulseBtnSize.sm,
                  variant: PulseBtnVariant.secondary,
                  onTap: () {
                    if (guardPhone.isNotEmpty) {
                      _call(guardPhone);
                    } else {
                      showAppToast(context,
                          'No guard number on this entry. Call the gate from '
                          'the society directory instead.',
                          kind: AppToastKind.alert);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PulseButton(
                  label: 'Call guest',
                  icon: Icons.call_rounded,
                  size: PulseBtnSize.sm,
                  variant: PulseBtnVariant.ghost,
                  // Kept in place but disabled when there is no number, so the
                  // row never changes shape between visitors.
                  disabled: guestPhone.isEmpty,
                  onTap: () => _call(guestPhone),
                ),
              ),
            ],
          ),
          // Photo diagnostics — deliberately shown in the UI while in dev so
          // an R2 upload/signing failure is never mistaken for "no photo".
          if (photoProblem != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: t.dangerSoft,
                  borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, size: 15, color: t.danger),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(photoProblem,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: t.danger,
                              fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          ],
          // Note the guard attached when logging this visitor at the gate.
          if (guardNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_outlined, size: 15, color: t.fg3),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('Guard note: $guardNote',
                          style: TextStyle(fontSize: 12, color: t.fg2))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Optional note the resident sends back with their decision.
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 3,
            style: TextStyle(fontSize: 12.5, color: t.fg1),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Add a note for the guard (optional)',
              hintStyle: TextStyle(fontSize: 12.5, color: t.fg4),
              filled: true,
              fillColor: t.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
                  borderSide: BorderSide(color: t.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
                  borderSide: BorderSide(color: t.border)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PulseButton(
                    label: 'Deny',
                    variant: PulseBtnVariant.danger,
                    size: PulseBtnSize.sm,
                    onTap: () => widget.onDecide('deny', _note.text.trim())),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PulseButton(
                    label: 'Allow',
                    variant: PulseBtnVariant.success,
                    size: PulseBtnSize.sm,
                    onTap: () => widget.onDecide('approve', _note.text.trim())),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  final Map visitor;
  const _TodayRow({required this.visitor});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final status = '${visitor['status'] ?? ''}';
    final tone = switch (status) {
      'Entered' || 'Approved' => PulseTone.entered,
      'Exited' => PulseTone.exited,
      'Pending' => PulseTone.pending,
      _ => PulseTone.expired
    };
    final created = DateTime.tryParse('${visitor['createdAt']}');
    final when = created != null
        ? '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}'
        : '';
    return PulseCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${visitor['name'] ?? 'Visitor'}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: t.fg1)),
                Text('$when · ${visitor['purpose'] ?? ''}',
                    style: TextStyle(fontSize: 11.5, color: t.fg4)),
              ],
            ),
          ),
          PulsePill(label: status, tone: tone, small: true),
        ],
      ),
    );
  }
}

class _PassRow extends StatelessWidget {
  final Map pass;
  const _PassRow({required this.pass});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final expiresAt = DateTime.tryParse('${pass['expiresAt']}');
    final generatedAt =
        DateTime.tryParse('${pass['createdAt']}') ?? DateTime.now();
    final expiresLabel = expiresAt != null
        ? 'Valid until ${expiresAt.day}/${expiresAt.month} · ${expiresAt.hour.toString().padLeft(2, '0')}:${expiresAt.minute.toString().padLeft(2, '0')}'
        : '';
    return PulseCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${pass['visitorName'] ?? 'Visitor'}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: t.fg1)),
                Text(expiresLabel,
                    style: TextStyle(fontSize: 11.5, color: t.fg4)),
              ],
            ),
          ),
          const PulsePill(
              label: 'Active', tone: PulseTone.entered, small: true),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Haptics.select();
              showVisitorPassCard(
                context,
                visitorName: '${pass['visitorName'] ?? ''}',
                visitorPhone: '${pass['visitorPhone'] ?? ''}',
                otp: '${pass['otp'] ?? ''}',
                generatedAt: generatedAt,
                expiresAt: expiresAt ?? generatedAt,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: t.brandSoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.qr_code_2_rounded, color: t.brand, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ids the resident has already marked safe on this device.
///
/// The "we are safe" state was read ONLY from `sosAck.at`. If the backend
/// resolved the alert any other way - the guard acknowledged it at the gate, a
/// `status` moved to Resolved, an older record wrote `sosAcknowledgedAt` - the
/// card came back armed on the next refresh. So an emergency the guard had
/// dealt with hours ago kept reappearing, and pressing "we are safe" again
/// changed nothing because the field the UI was watching was never the field
/// being written.
///
/// This set is the last line of defence: once you have acknowledged an alert,
/// it stays acknowledged for the rest of the session no matter what shape the
/// server response comes back in.
final Set<String> _locallyAckedSos = <String>{};

/// Tolerant "has this SOS been dealt with?" check.
bool sosAcknowledged(Map visitor) {
  final id = '${visitor['_id'] ?? ''}';
  if (id.isNotEmpty && _locallyAckedSos.contains(id)) return true;

  final ack = visitor['sosAck'];
  if (ack is Map && (ack['at'] != null || ack['by'] != null)) return true;
  if (visitor['sosAcknowledgedAt'] != null) return true;
  if (visitor['sosResolved'] == true) return true;
  if (visitor['resolvedAt'] != null) return true;

  // The guard closing it out at the gate counts. The resident does not need to
  // silence an alarm that is already over.
  const settled = {'resolved', 'handled', 'closed', 'acknowledged', 'safe'};
  if (settled.contains('${visitor['sosStatus'] ?? ''}'.toLowerCase())) {
    return true;
  }
  if (settled.contains('${visitor['status'] ?? ''}'.toLowerCase())) return true;

  return false;
}

/// "We are safe" on a resident's own SOS card.
///
/// Same endpoint the guard's Acknowledge uses. It matters here because the alarm
/// rings on EVERY handset in the flat: whoever gets to their phone first can
/// call off the other three, instead of each person hunting down their own STOP
/// button. Acknowledging also tells the gate the situation is handled, which is
/// what stops the escalation ladder.
class _SosSafeButton extends StatefulWidget {
  const _SosSafeButton({required this.visitorId, required this.acknowledged});

  final String visitorId;
  final bool acknowledged;

  @override
  State<_SosSafeButton> createState() => _SosSafeButtonState();
}

class _SosSafeButtonState extends State<_SosSafeButton> {
  bool _busy = false;
  bool _done = false;

  Future<void> _ack() async {
    Haptics.medium();
    setState(() => _busy = true);
    try {
      await acknowledgeSos(context.read<Dio>(), widget.visitorId);
      // Remember it here too, so a pull-to-refresh cannot re-arm the alert if
      // the server echoes the record back in a shape we do not recognise.
      _locallyAckedSos.add(widget.visitorId);
      if (!mounted) return;
      setState(() {
        _done = true;
        _busy = false;
      });
      showAppToast(context, 'Marked as handled \u2014 alarms silenced.',
          kind: AppToastKind.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, apiErrorMessage(e), kind: AppToastKind.alert);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    if (widget.acknowledged || _done) {
      return Row(
        children: [
          Icon(Icons.verified_rounded, size: 16, color: t.success),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Marked as handled \u2014 alarms have been silenced.',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: t.success)),
          ),
        ],
      );
    }
    return PulseButton(
      label: 'We are safe \u2014 silence the alarm',
      icon: Icons.volume_off_rounded,
      variant: PulseBtnVariant.secondary,
      full: true,
      size: PulseBtnSize.sm,
      loading: _busy,
      disabled: _busy,
      onTap: _ack,
    );
  }
}
