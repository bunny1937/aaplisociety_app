import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_error.dart';
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
      await dio.post('/visitors/$id/$action');
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
      showAppToast(context, 'Resident notified again', kind: AppToastKind.success);
    } on DioException catch (err) {
      if (!mounted) return;
      Haptics.heavy();
      showAppToast(context, apiErrorMessage(err, 'Could not send reminder'), kind: AppToastKind.alert);
    }
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final launched = await launchUrl(Uri.parse('tel:$phone'));
    if (!launched && mounted) {
      showAppToast(context, 'Could not open the phone dialer', kind: AppToastKind.alert);
    }
  }

  Future<void> _raiseSos(Dio dio) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Raise SOS?'),
        content: const Text('This immediately alerts every admin and secretary in the society. Only use this for a genuine emergency at the gate.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Raise SOS', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
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
      showAppToast(context, 'SOS raised — admins have been alerted', kind: AppToastKind.success);
    } on DioException catch (err) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(err, 'Could not raise SOS'), kind: AppToastKind.alert);
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
              onTap: () async => Navigator.pop(sheetContext, await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () async => Navigator.pop(sheetContext, await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85)),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;

    Haptics.medium();
    try {
      final form = FormData.fromMap({'file': await MultipartFile.fromFile(picked.path)});
      await dio.post('/visitors/$visitorId/upload-photo', data: form);
      if (!mounted) return;
      Haptics.success();
      showAppToast(context, 'Photo attached', kind: AppToastKind.success);
      await _listKey.currentState?.reload();
    } on DioException catch (err) {
      if (!mounted) return;
      Haptics.heavy();
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dio = context.read<Dio>();
    return AsyncView<List>(
      key: _listKey,
      fetch: () async => (await dio.get('/visitors')).data as List,
      cacheKey: '/visitors',
      loadingBuilder: (_) => const _GateSkeleton(),
      builder: (context, all) {
        final t = context.pulse;
        final pending = all.where((v) => v['status'] == 'Pending').toList();
        final approved = all.where((v) => v['status'] == 'Approved').toList();
        final inside = all.where((v) => v['status'] == 'Entered').toList();
        final enteredEver = all.where((v) => v['status'] == 'Entered' || v['status'] == 'Exited').toList();
        final now = DateTime.now();
        final todayCount = all.where((v) {
          final d = DateTime.tryParse('${v['createdAt']}');
          return d != null && d.year == now.year && d.month == now.month && d.day == now.day;
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
                      Text('Gate Dashboard', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.fg1, letterSpacing: -0.3)),
                      Text('Main Gate · live visitor activity', style: TextStyle(fontSize: 12.5, color: t.fg4)),
                    ],
                  ),
                ),
                PulseIconButton(icon: Icons.refresh_rounded, onTap: () => _listKey.currentState?.reload()),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PulseCard(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 15, color: t.fg3),
                        const SizedBox(width: 6),
                        Text(
                          OfflineOutbox.pendingCount > 0 ? '${OfflineOutbox.pendingCount} queued' : 'Offline entry',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.fg3),
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
                Expanded(child: _StatTile(label: 'Inside now', value: inside.length, colorOf: (t) => t.success)),
                const SizedBox(width: 8),
                Expanded(child: _StatTile(label: 'Pending', value: pending.length, colorOf: (t) => t.warning)),
                const SizedBox(width: 8),
                Expanded(child: _StatTile(label: 'Today', value: todayCount, colorOf: (t) => t.brand)),
                const SizedBox(width: 8),
                Expanded(child: _StatTile(label: 'Entered', value: enteredEver.length, colorOf: (t) => t.accent)),
              ],
            ),
            _pendingSection(context, dio, pending),
            _section(context, dio, 'Approved — let them in', approved, 'Admit', (id) => _act(dio, id, 'enter')),
            _section(context, dio, 'Currently inside', inside, 'Check out', (id) => _act(dio, id, 'exit')),
            if (all.isEmpty)
              const PulseEmptyState(illo: PulseIllo.allClear, title: 'All clear — nobody waiting.'),
          ],
        );
      },
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
              Text('Awaiting resident approval', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: t.fg1)),
              const SizedBox(width: 8),
              PulsePill(label: '${items.length}', tone: PulseTone.pending, dot: false, small: true),
            ],
          ),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((e) {
            final v = e.value as Map;
            final id = v['_id'] as String;
            final phone = '${v['phone'] ?? ''}';
            final hasPhoto = v['photoUrl'] != null;
            final createdAt = DateTime.tryParse('${v['createdAt']}') ?? DateTime.now();
            final waitMins = DateTime.now().difference(createdAt).inMinutes;
            final expired = waitMins >= 45;
            final warning = waitMins >= 20;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LedgerVisitorCard(
                index: e.key,
                name: '${v['name']}',
                subtitle: '${v['purpose'] ?? ''} · ${phone.isNotEmpty ? phone : 'No phone'} · ${timeAgo(createdAt)}',
                tint: expired ? t.dangerSoft : (warning ? t.warningSoft : null),
                status: expired ? 'Expired' : (warning ? '⚠ ${waitMins}m' : 'Pending'),
                statusColor: expired ? t.danger : (warning ? t.warning : t.fg3),
                actions: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: PulseButton(label: 'Remind', size: PulseBtnSize.sm, onTap: () => _remind(dio, id))),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          PulseIconButton(icon: Icons.call_rounded, onTap: () => _call(phone)),
                        ],
                        const SizedBox(width: 8),
                        PulseIconButton(
                          icon: hasPhoto ? Icons.photo_rounded : Icons.camera_alt_outlined,
                          onTap: () => _attachPhoto(dio, id),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: PulseButton(
                            label: 'Allow in',
                            size: PulseBtnSize.sm,
                            variant: PulseBtnVariant.success,
                            onTap: () => _act(dio, id, 'enter'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PulseButton(
                            label: 'Deny',
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

  Widget _section(BuildContext context, Dio dio, String title, List items, String actionLabel, void Function(String id) onAction) {
    if (items.isEmpty) return const SizedBox.shrink();
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: t.fg1)),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((e) {
            final v = e.value as Map;
            final id = v['_id'] as String;
            final entryTime = DateTime.tryParse('${v['entryTime'] ?? v['createdAt']}') ?? DateTime.now();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LedgerVisitorCard(
                index: e.key,
                name: '${v['name']}',
                subtitle: '${v['purpose'] ?? ''} · ${timeAgo(entryTime)}',
                actions: SizedBox(
                  width: double.infinity,
                  child: PulseButton(label: actionLabel, full: true, size: PulseBtnSize.sm, variant: PulseBtnVariant.success, onTap: () => onAction(id)),
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
  const _StatTile({required this.label, required this.value, required this.colorOf});

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
            builder: (context, v, _) => Text('$v', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10.5, color: t.fg4, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
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
