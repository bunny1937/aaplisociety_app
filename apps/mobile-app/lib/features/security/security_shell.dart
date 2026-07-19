import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_x.dart';
import '../../core/theme/haptics.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ledger_shimmer.dart';
import '../../core/widgets/visitor_card.dart';
import '../../core/widgets/press_effect.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/socket/socket_bus.dart';
import '../../core/storage/offline_outbox.dart';
import '../auth/bloc/auth_bloc.dart';
import 'pass_verify_sheet.dart';

class SecurityShell extends StatefulWidget {
  const SecurityShell({super.key});
  @override
  State<SecurityShell> createState() => _SecurityShellState();
}

class _SecurityShellState extends State<SecurityShell> {
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
    Haptics.light();
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

  Future<void> _logEntry(Dio dio) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final purpose = ValueNotifier<String>('Guest');
    const purposes = ['Guest', 'Delivery', 'Domestic Help', 'Vendor', 'Cab', 'Other'];

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Log visitor entry', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Works offline — syncs automatically once you\'re back online.', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            const SizedBox(height: 16),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Visitor name')),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (10 digits)')),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: purpose,
              builder: (_, value, __) => DropdownButtonFormField<String>(
                initialValue: value,
                items: purposes.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) => purpose.value = v ?? value,
                decoration: const InputDecoration(labelText: 'Purpose'),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('Log entry'),
              ),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) return;
    if (name.text.trim().length < 2 || !RegExp(r'^[0-9]{10}$').hasMatch(phone.text.trim())) {
      showAppToast(context, 'Enter a valid name and 10-digit phone number', kind: AppToastKind.alert);
      return;
    }

    final payload = {
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'purpose': purpose.value,
      'clientRef': OfflineOutbox.generateClientRef(),
      'queuedAt': DateTime.now().toUtc().toIso8601String(),
    };
    Haptics.medium();
    try {
      await dio.post('/visitors/offline-entry', data: payload);
      if (!mounted) return;
      Haptics.success();
      showAppToast(context, 'Visitor entry logged', kind: AppToastKind.success);
      await _listKey.currentState?.reload();
    } on DioException catch (_) {
      // No connectivity (or a transient failure) — queue for automatic retry
      // rather than losing the entry; the clientRef generated above travels
      // with it so a later successful retry can't double-log this visit.
      OfflineOutbox.enqueue(payload);
      if (!mounted) return;
      Haptics.light();
      showAppToast(context, 'No connection — saved offline, will sync automatically', kind: AppToastKind.info);
      setState(() {}); // refresh the pending-sync badge
    }
  }

  Future<void> _verifyPass(Dio dio) async {
    await showPassVerifySheet(context);
    if (!mounted) return;
    await _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final dio = context.read<Dio>();
    return Scaffold(
      backgroundColor: context.isDark ? AppColors.ink : AppColors.paper,
      body: SafeArea(
        child: AsyncView<List>(
          key: _listKey,
          fetch: () async => (await dio.get('/visitors')).data as List,
          cacheKey: '/visitors',
          loadingBuilder: (_) => const LedgerListSkeleton(),
          builder: (context, all) {
            final pending = all.where((v) => v['status'] == 'Pending').toList();
            final approved = all.where((v) => v['status'] == 'Approved').toList();
            final inside = all.where((v) => v['status'] == 'Entered').toList();
            final now = DateTime.now();
            final todayCount = all.where((v) {
              final d = DateTime.tryParse('${v['createdAt']}');
              return d != null && d.year == now.year && d.month == now.month && d.day == now.day;
            }).length;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.brass.withValues(alpha: 0.5), width: 1.2),
                      ),
                      child: const Icon(Icons.shield_rounded, color: AppColors.brass),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Gate security', style: GoogleFonts.fraunces(fontSize: 20, fontWeight: FontWeight.w600, color: context.headline)),
                          Text('Visitor gate log', style: GoogleFonts.manrope(color: AppColors.inkMuted)),
                        ],
                      ),
                    ),
                    if (OfflineOutbox.pendingCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
                          child: Text('${OfflineOutbox.pendingCount} pending sync', style: GoogleFonts.manrope(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Raise SOS',
                      icon: const Icon(Icons.emergency_rounded, color: Colors.redAccent),
                      onPressed: () => _raiseSos(dio),
                    ),
                    IconButton(
                      tooltip: 'Log out',
                      icon: const Icon(Icons.logout_rounded, color: AppColors.inkMuted),
                      onPressed: () { Haptics.heavy(); context.read<AuthBloc>().add(LogoutRequested()); context.go('/login'); },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _StatCard(label: 'Inside now', value: inside.length, color: AppColors.stampGreen)),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard(label: 'Pending', value: pending.length, color: Colors.orange)),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard(label: "Today's total", value: todayCount, color: AppColors.brass)),
                  ],
                ),
                const SizedBox(height: 22),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: PressEffect(
                      onTap: () { Haptics.light(); _verifyPass(dio); },
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: context.surface.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.inkMuted.withValues(alpha: 0.3), width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.qr_code_scanner_rounded, color: AppColors.inkMuted, size: 26),
                            const SizedBox(width: 14),
                            Expanded(child: Text('Verify visitor gate pass', style: GoogleFonts.manrope(color: context.headline, fontSize: 15, fontWeight: FontWeight.w600))),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.15),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: PressEffect(
                      onTap: () { Haptics.light(); _logEntry(dio); },
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: context.surface.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.inkMuted.withValues(alpha: 0.3), width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.edit_note_rounded, color: AppColors.inkMuted, size: 26),
                            const SizedBox(width: 14),
                            Expanded(child: Text('Log visitor entry (works offline)', style: GoogleFonts.manrope(color: context.headline, fontSize: 15, fontWeight: FontWeight.w600))),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 160.ms).slideY(begin: 0.15),
                _pendingSection(context, dio, pending),
                _section(context, dio, 'Approved — let them in', null, approved, 'Admit', (id) => _act(dio, id, 'enter')),
                _section(context, dio, 'Inside now', null, inside, 'Exit', (id) => _act(dio, id, 'exit')),
                if (all.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 50),
                    child: Center(child: Text('All clear — nobody waiting.', style: GoogleFonts.manrope(color: AppColors.inkMuted))),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pendingSection(BuildContext context, Dio dio, List items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Awaiting member approval', style: GoogleFonts.fraunces(fontWeight: FontWeight.w600, fontSize: 17, color: context.headline)),
          const SizedBox(height: 4),
          Text("The resident hasn't responded yet — remind them, or call the flat directly.", style: GoogleFonts.manrope(color: AppColors.inkMuted, fontSize: 13)),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((e) {
            final v = e.value as Map;
            final id = v['_id'] as String;
            final phone = '${v['phone'] ?? ''}';
            final hasPhoto = v['photoUrl'] != null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LedgerVisitorCard(
                index: e.key,
                name: '${v['name']}',
                subtitle: '${v['purpose'] ?? ''} · $phone',
                actions: Row(
                  children: [
                    Expanded(
                      child: PressEffect(
                        onTap: () => _remind(dio, id),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(color: AppColors.brass.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                          child: Text('🔔 Remind', style: GoogleFonts.manrope(color: AppColors.brass, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      PressEffect(
                        onTap: () => _call(phone),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: AppColors.stampGreen.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.call_rounded, size: 18, color: AppColors.stampGreen),
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    PressEffect(
                      onTap: () => _attachPhoto(dio, id),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: hasPhoto ? AppColors.brass.withValues(alpha: 0.14) : AppColors.inkMuted.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(hasPhoto ? Icons.photo_rounded : Icons.camera_alt_outlined, size: 18, color: hasPhoto ? AppColors.brass : AppColors.inkMuted),
                      ),
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

  Widget _section(BuildContext context, Dio dio, String title, String? subtitle, List items, String? actionLabel, void Function(String id)? onAction) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.fraunces(fontWeight: FontWeight.w600, fontSize: 17, color: context.headline)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.manrope(color: AppColors.inkMuted, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          ...items.asMap().entries.map((e) {
            final v = e.value as Map;
            final id = v['_id'] as String;
            final hasPhoto = v['photoUrl'] != null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LedgerVisitorCard(
                index: e.key,
                name: '${v['name']}',
                subtitle: '${v['purpose'] ?? ''} · ${v['phone'] ?? ''}',
                actions: Row(
                  children: [
                    if (actionLabel != null && onAction != null)
                      Expanded(
                        child: PressEffect(
                          onTap: () => onAction(id),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(color: AppColors.stampGreen.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                            child: Text(actionLabel, style: GoogleFonts.manrope(color: AppColors.stampGreen, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    if (actionLabel != null && onAction != null) const SizedBox(width: 10),
                    PressEffect(
                      onTap: () => _attachPhoto(dio, id),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: hasPhoto ? AppColors.brass.withValues(alpha: 0.14) : AppColors.inkMuted.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(hasPhoto ? Icons.photo_rounded : Icons.camera_alt_outlined, size: 18, color: hasPhoto ? AppColors.brass : AppColors.inkMuted),
                      ),
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
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: context.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Column(
        children: [
          Text('$value', style: GoogleFonts.fraunces(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.manrope(fontSize: 11, color: AppColors.inkMuted, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
