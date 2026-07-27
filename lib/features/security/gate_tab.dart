import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_error.dart';
import '../../core/network/sos_api.dart';
import '../../core/socket/socket_bus.dart';
import '../../core/storage/offline_outbox.dart';
import '../../core/theme/haptics.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/visitor_card.dart';
import '../member/pulse/pulse.dart';

class GateTab extends StatefulWidget {
  const GateTab({super.key});
  @override
  State<GateTab> createState() => _GateTabState();
}

class _GateTabState extends State<GateTab> {
  final _listKey = GlobalKey<AsyncViewState<List>>();
  @override
  void initState() {
    super.initState();
    SocketBus.visitorEvents.addListener(_onEvent);
  }

  @override
  void dispose() {
    SocketBus.visitorEvents.removeListener(_onEvent);
    super.dispose();
  }

  void _onEvent() => _listKey.currentState?.reload();
  Future<void> _act(Dio dio, String id, String action) async {
    Haptics.medium();
    try {
      final isEnter = action == 'enter';
      final isExit = action == 'exit';
      // Checking a guest OUT is not an approval decision — it must never be
      // labelled "Deny after call". Only enter/deny are phone-confirmed.
      final String title = isExit
          ? 'Check out this visitor?'
          : (isEnter ? 'Allow after call?' : 'Deny after call?');
      final String body = isExit
          ? 'Confirm the visitor has physically left. This records the exit time.'
          : 'Confirm that you called the resident and received this decision verbally.';
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: Text(title),
                  content: Text(body),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: Text(isExit ? 'Check out' : 'Confirm')),
                  ]));
      if (confirmed != true) return;
      await dio.post('/visitors/$id/$action', data: isExit
          ? {'decisionSource': 'GuardExit', 'note': 'Visitor exited the premises'}
          : {'decisionSource':'GuardPhoneConfirmation','note':isEnter?'Resident verbally approved by phone':'Resident verbally denied by phone'});
      if (!mounted) return;
      Haptics.success();
      await _listKey.currentState?.reload();
    } on DioException catch (err) {
      if (!mounted) return;
      Haptics.heavy();
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    }
  }

  Future<void> _remind(Dio dio, String id) async {
    Haptics.medium();
    try {
      await dio.patch('/visitors/$id/remind');
      if (!mounted) return;
      Haptics.success();
      showAppToast(context, 'Resident notified again',
          kind: AppToastKind.success);
    } on DioException catch (err) {
      if (!mounted) return;
      Haptics.heavy();
      showAppToast(context, apiErrorMessage(err, 'Could not send reminder'),
          kind: AppToastKind.alert);
    }
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final launched = await launchUrl(Uri.parse('tel:$phone'));
    if (!launched && mounted) {
      showAppToast(context, 'Could not open the phone dialer',
          kind: AppToastKind.alert);
    }
  }

  Future<void> _raiseSos(Dio dio) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Raise SOS?'),
        content: const Text(
            'This immediately alerts every admin and secretary in the society. Only use this for a genuine emergency at the gate.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Raise SOS',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    Haptics.heavy();
    try {
      await dio.post('/visitors/guard-sos', data: {});
      if (!mounted) return;
      Haptics.success();
      showAppToast(context, 'SOS raised — admins have been alerted',
          kind: AppToastKind.success);
    } on DioException catch (err) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(err, 'Could not raise SOS'),
          kind: AppToastKind.alert);
    }
  }

  Future<void> _attachPhoto(Dio dio, String visitorId) async {
    final picked = await showModalBottomSheet<XFile?>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () async {
                final file = await ImagePicker().pickImage(
                    source: ImageSource.camera,
                    maxWidth: 1600,
                    imageQuality: 85);
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext, file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () async {
                final file = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 1600,
                    imageQuality: 85);
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext, file);
              },
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    Haptics.medium();
    try {
      final form =
          FormData.fromMap({'file': await MultipartFile.fromFile(picked.path)});
      await dio.post('/visitors/$visitorId/upload-photo', data: form);
      if (!mounted) return;
      Haptics.success();
      showAppToast(context, 'Photo attached', kind: AppToastKind.success);
      await _listKey.currentState?.reload();
    } on DioException catch (err) {
      if (!mounted) return;
      Haptics.heavy();
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    } finally {
      try {
        await File(picked.path).delete();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final dio = context.read<Dio>();
    return AsyncView<List>(
      key: _listKey,
      fetch: () async => (await dio.get('/visitors')).data['visitors'] as List,
      cacheKey: '/visitors',
      loadingBuilder: (_) => const _GateSkeleton(),
      builder: (context, all) {
        final t = context.pulse;
        // SOS must NOT flow through the visitor pipeline. It was landing in
        // "Awaiting resident approval" as a card titled "SOS Alert" with
        // purpose "Other", phone 0000000000, and Allow/Deny buttons - as if a
        // guard should approve a resident's emergency. Split it out entirely.
        final sos = all
            .where((v) =>
                v['entryMethod'] == 'SOS' &&
                v['status'] != 'Exited' &&
                v['status'] != 'Rejected')
            .toList();
        final pending = all
            .where(
                (v) => v['status'] == 'Pending' && v['entryMethod'] != 'SOS')
            .toList();
        final approved = all.where((v) => v['status'] == 'Approved').toList();
        final inside = all.where((v) => v['status'] == 'Entered').toList();
        final enteredEver = all
            .where((v) => v['status'] == 'Entered' || v['status'] == 'Exited')
            .toList();
        final now = DateTime.now();
        final todayCount = all.where((v) {
          final d = DateTime.tryParse('${v['createdAt']}');
          return d != null &&
              d.year == now.year &&
              d.month == now.month &&
              d.day == now.day;
        }).length;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                const PulseAvatar(name: 'Security Guard', size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gate Dashboard',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: t.fg1,
                              letterSpacing: -0.3)),
                      Text('Main Gate · live visitor activity',
                          style: TextStyle(fontSize: 12.5, color: t.fg4)),
                    ],
                  ),
                ),
                PulseIconButton(
                    icon: Icons.refresh_rounded,
                    onTap: () => _listKey.currentState?.reload()),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PulseCard(
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 15, color: t.fg3),
                        const SizedBox(width: 6),
                        Text(
                          OfflineOutbox.pendingCount > 0
                              ? '${OfflineOutbox.pendingCount} queued'
                              : 'Offline entry',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: t.fg3),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PulseButton(
                    label: 'SOS',
                    icon: Icons.emergency_rounded,
                    variant: PulseBtnVariant.danger,
                    full: true,
                    onTap: () => _raiseSos(dio),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: _StatTile(
                        label: 'Inside now',
                        value: inside.length,
                        colorOf: (t) => t.success)),
                const SizedBox(width: 8),
                Expanded(
                    child: _StatTile(
                        label: 'Pending',
                        value: pending.length,
                        colorOf: (t) => t.warning)),
                const SizedBox(width: 8),
                Expanded(
                    child: _StatTile(
                        label: 'Today',
                        value: todayCount,
                        colorOf: (t) => t.brand)),
                const SizedBox(width: 8),
                Expanded(
                    child: _StatTile(
                        label: 'Entered',
                        value: enteredEver.length,
                        colorOf: (t) => t.accent)),
              ],
            ),
            _sosSection(context, dio, sos),
            _pendingSection(context, dio, pending),
            _section(context, dio, 'Approved — let them in', approved, 'Admit',
                (id) => _act(dio, id, 'enter')),
            _section(context, dio, 'Currently inside', inside, 'Check out (exit)',
                (id) => _act(dio, id, 'exit')),
            if (all.isEmpty)
              const PulseEmptyState(
                  illo: PulseIllo.allClear,
                  title: 'All clear — nobody waiting.'),
          ],
        );
      },
    );
  }

  /// Emergency card. Deliberately shares nothing with [LedgerVisitorCard]:
  /// no avatar, no purpose line, no Allow/Deny, no "call the visitor" (there is
  /// no visitor - the resident IS the caller). What a guard needs here is which
  /// flat, what happened, and a one-tap call to that flat.
  Widget _sosSection(BuildContext context, Dio dio, List items) {
    if (items.isEmpty) return const SizedBox.shrink();
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.asMap().entries.map((entry) {
          final v = entry.value as Map;
          // The flat is the single most important field and was never shown.
          final wing = '${v['wing'] ?? ''}';
          final flatNo = '${v['flatNo'] ?? v['flat'] ?? ''}';
          final flatLabel = flatNo.isEmpty
              ? 'Flat not recorded'
              : (wing.isEmpty ? flatNo : '$wing-$flatNo');
          // purposeNote carries the reason the resident picked when raising it.
          final reason = '${v['purposeNote'] ?? v['note'] ?? ''}'.trim();
          // The resident's own number - NOT the 0000000000 placeholder stored on
          // the SOS row itself.
          final residentPhone = '${v['contactNumber'] ?? v['memberPhone'] ?? v['residentPhone'] ?? ''}'.trim();
          final raisedAt =
              DateTime.tryParse('${v['createdAt']}') ?? DateTime.now();
          return Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: entry.key == items.length - 1 ? 0 : 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.dangerSoft,
              borderRadius: BorderRadius.circular(PulseTokens.radius),
              border: Border.all(color: t.danger, width: 1.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.emergency_rounded, color: t.danger, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'EMERGENCY \u00b7 $flatLabel',
                        style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: t.danger,
                            letterSpacing: -0.2),
                      ),
                    ),
                    Text(timeAgo(raisedAt),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.danger)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  reason.isEmpty
                      ? 'No reason given \u2014 call the flat immediately.'
                      : reason,
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700, color: t.fg1),
                ),
                const SizedBox(height: 4),
                Text('Raised by the resident from inside the flat',
                    style: TextStyle(fontSize: 12, color: t.fg3)),
                const SizedBox(height: 12),
                if (residentPhone.isNotEmpty)
                  PulseButton(
                    label: 'Call $flatLabel now',
                    icon: Icons.phone_in_talk_rounded,
                    variant: PulseBtnVariant.danger,
                    full: true,
                    onTap: () => _call(residentPhone),
                  )
                else
                  Text('No contact number on file for this flat \u2014 go there.',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: t.danger)),
                const SizedBox(height: 8),
                _SosAckButton(
                  dio: dio,
                  visitorId: '${v['_id']}',
                  ack: v['sosAck'] as Map?,
                  onDone: () => _listKey.currentState?.reload(),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _pendingSection(BuildContext context, Dio dio, List items) {
    if (items.isEmpty) return const SizedBox.shrink();
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Awaiting resident approval',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16, color: t.fg1)),
              const SizedBox(width: 8),
              PulsePill(
                  label: '${items.length}',
                  tone: PulseTone.pending,
                  dot: false,
                  small: true),
            ],
          ),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((e) {
            final v = e.value as Map;
            final id = v['_id'] as String;
            final phone = '${v['phone'] ?? ''}';
            // Note left on the request + the resident's phone, so the guard can
            // read the note and call the flat directly. contactNumber is the
            // flat contact the entry was raised against (see new_entry_tab).
            final note = '${v['note'] ?? ''}';
            final residentPhone =
                '${v['contactNumber'] ?? v['memberPhone'] ?? v['residentPhone'] ?? ''}';
            final hasPhoto = v['photoUrl'] != null;
            final createdAt =
                DateTime.tryParse('${v['createdAt']}') ?? DateTime.now();
            final waitMins = DateTime.now().difference(createdAt).inMinutes;
            final expired = waitMins >= 45;
            final warning = waitMins >= 20;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LedgerVisitorCard(
                index: e.key,
                name: '${v['name']}',
                subtitle:
                    '${v['purpose'] ?? ''} · ${phone.isNotEmpty ? phone : 'No phone'} · ${timeAgo(createdAt)}',
                tint: expired ? t.dangerSoft : (warning ? t.warningSoft : null),
                status: expired
                    ? 'Expired'
                    : (warning ? '⚠ ${waitMins}m' : 'Pending'),
                statusColor: expired ? t.danger : (warning ? t.warning : t.fg3),
                actions: Column(
                  children: [
                    // Note attached to this request (by the resident on their
                    // decision, or whoever raised it) — the guard previously
                    // had no way to see it.
                    if (note.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                            color: t.surface2,
                            borderRadius:
                                BorderRadius.circular(PulseTokens.radiusSm)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.sticky_note_2_outlined,
                                size: 14, color: t.fg3),
                            const SizedBox(width: 7),
                            Expanded(
                                child: Text('Note: $note',
                                    style:
                                        TextStyle(fontSize: 12, color: t.fg2))),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                            child: PulseButton(
                                label: 'Remind',
                                size: PulseBtnSize.sm,
                                onTap: () => _remind(dio, id))),
                        // The only number a guard ever needs to dial here is
                        // the FLAT's. The visitor is standing at the gate in
                        // front of them - calling the guest's own mobile is
                        // pointless, and it was previously the more prominent
                        // of the two buttons (plain phone icon, last position),
                        // which is why guards kept dialling the guest.
                        // The guest's number stays visible in the subtitle for
                        // reference; it is just no longer a one-tap action.
                        if (residentPhone.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: PulseButton(
                                label: 'Call flat',
                                icon: Icons.phone_in_talk_rounded,
                                size: PulseBtnSize.sm,
                                onTap: () => _call(residentPhone)),
                          ),
                        ],
                        const SizedBox(width: 8),
                        PulseIconButton(
                          icon: hasPhoto
                              ? Icons.photo_rounded
                              : Icons.camera_alt_outlined,
                          onTap: () => _attachPhoto(dio, id),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: PulseButton(
                            label: 'Allow after call',
                            size: PulseBtnSize.sm,
                            variant: PulseBtnVariant.success,
                            onTap: () => _act(dio, id, 'enter'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PulseButton(
                            label: 'Deny after call',
                            size: PulseBtnSize.sm,
                            variant: PulseBtnVariant.danger,
                            onTap: () => _act(dio, id, 'deny'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, Dio dio, String title, List items,
      String actionLabel, void Function(String id) onAction) {
    if (items.isEmpty) return const SizedBox.shrink();
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16, color: t.fg1)),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((e) {
            final v = e.value as Map;
            final id = v['_id'] as String;
            final entryTime =
                DateTime.tryParse('${v['entryTime'] ?? v['createdAt']}') ??
                    DateTime.now();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LedgerVisitorCard(
                index: e.key,
                name: '${v['name']}',
                subtitle: '${v['purpose'] ?? ''} · ${timeAgo(entryTime)}',
                actions: SizedBox(
                  width: double.infinity,
                  child: PulseButton(
                      label: actionLabel,
                      full: true,
                      size: PulseBtnSize.sm,
                      variant: PulseBtnVariant.success,
                      onTap: () => onAction(id)),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  final Color Function(PulseTokens) colorOf;
  const _StatTile(
      {required this.label, required this.value, required this.colorOf});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final color = colorOf(t);
    return PulseCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Column(
        children: [
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: value),
            duration: const Duration(milliseconds: 250),
            builder: (context, v, _) => Text('$v',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5, color: t.fg4, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _GateSkeleton extends StatelessWidget {
  const _GateSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: const [
        PulseSkeleton(height: 44, radius: 22),
        SizedBox(height: 16),
        PulseSkeleton(height: 64),
        SizedBox(height: 22),
        PulseSkeleton(height: 96),
        SizedBox(height: 12),
        PulseSkeleton(height: 96),
      ],
    );
  }
}

/// Acknowledge control on a guard's SOS card.
///
/// "Acknowledge" is not the same as STOP. STOP on a ringing phone silences that
/// phone. Acknowledge tells the backend a human is responding, which pushes
/// `VISITOR_SOS_ACK` to every device on the affected flat and silences all of
/// them -- and it is the only reassurance the resident gets that their alert was
/// actually seen by the gate rather than screaming into the void.
///
/// Kept as its own StatefulWidget because the SOS card is built inside a
/// `.map()` over the list: there is nowhere in that closure to hold per-row
/// busy state, and a shared flag would spin every card at once.
class _SosAckButton extends StatefulWidget {
  const _SosAckButton({
    required this.dio,
    required this.visitorId,
    required this.ack,
    required this.onDone,
  });

  final Dio dio;
  final String visitorId;

  /// `sosAck` from the visitor row: null or missing `at` means not yet handled.
  final Map? ack;
  final VoidCallback onDone;

  @override
  State<_SosAckButton> createState() => _SosAckButtonState();
}

class _SosAckButtonState extends State<_SosAckButton> {
  bool _busy = false;

  Future<void> _ack() async {
    Haptics.medium();
    setState(() => _busy = true);
    try {
      await acknowledgeSos(widget.dio, widget.visitorId);
      if (!mounted) return;
      showAppToast(context, 'Acknowledged \u2014 the flat knows help is coming.',
          kind: AppToastKind.success);
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(e), kind: AppToastKind.alert);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final at = widget.ack?['at'];
    if (at != null) {
      final who = '${widget.ack?['byName'] ?? widget.ack?['byRole'] ?? ''}'.trim();
      return Row(
        children: [
          Icon(Icons.verified_rounded, size: 16, color: t.success),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              who.isEmpty
                  ? 'Acknowledged \u2014 someone is responding.'
                  : 'Acknowledged by $who.',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: t.success),
            ),
          ),
        ],
      );
    }
    return PulseButton(
      label: 'Acknowledge \u2014 on our way',
      icon: Icons.shield_rounded,
      variant: PulseBtnVariant.secondary,
      full: true,
      loading: _busy,
      disabled: _busy,
      onTap: _ack,
    );
  }
}
