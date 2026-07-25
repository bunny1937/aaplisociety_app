import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/socket/socket_bus.dart';
import '../../core/storage/offline_outbox.dart';
import '../../core/theme/haptics.dart';
import '../../core/utils/image_compress.dart';
import '../../core/widgets/app_toast.dart';
import '../member/pulse/pulse.dart';

class NewEntryTab extends StatefulWidget {
  final VoidCallback? onDone;
  const NewEntryTab({super.key, this.onDone});
  @override
  State<NewEntryTab> createState() => _NewEntryTabState();
}

class _NewEntryTabState extends State<NewEntryTab> {
  static const _purposes = <(String, IconData)>[
    ('Guest', Icons.person_rounded),
    ('Delivery', Icons.inventory_2_rounded),
    ('Domestic Help', Icons.cleaning_services_rounded),
    ('Vendor', Icons.build_rounded),
    ('Cab', Icons.local_taxi_rounded),
    ('Other', Icons.help_outline_rounded),
  ];
  final _flat = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _vehicle = TextEditingController();
  final _note = TextEditingController();
  String _purpose = 'Guest';
  XFile? _photo;
  bool _submitting = false;
  Timer? _debounce;
  bool _searchingFlats = false;
  List<Map> _flatResults = [];
  Map? _selectedFlat; // {memberId, flatNo, wing, ownerName, contactNumber}
  @override
  void initState() {
    super.initState();
    _flat.addListener(_onFlatQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _flat.removeListener(_onFlatQueryChanged);
    _flat.dispose();
    _name.dispose();
    _phone.dispose();
    _vehicle.dispose();
    _note.dispose();
    _deletePendingPhoto();
    super.dispose();
  }

  void _onFlatQueryChanged() {
    if (_selectedFlat != null) {
      return; // editing after a selection is handled by _clearFlat instead
    }
    _debounce?.cancel();
    final q = _flat.text.trim();
    if (q.isEmpty) {
      setState(() => _flatResults = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _searchFlats(q));
  }

  Future<void> _searchFlats(String q) async {
    final dio = context.read<Dio>();
    setState(() => _searchingFlats = true);
    try {
      final res =
          await dio.get('/visitors/flats/search', queryParameters: {'q': q});
      if (!mounted) return;
      setState(() => _flatResults = List<Map>.from(res.data['flats'] as List));
    } on DioException {
      if (!mounted) return;
      setState(() => _flatResults = []);
    } finally {
      if (mounted) setState(() => _searchingFlats = false);
    }
  }

  void _selectFlat(Map flat) {
    Haptics.select();
    setState(() {
      _selectedFlat = flat;
      _flatResults = [];
    });
  }

  void _clearFlat() {
    setState(() {
      _selectedFlat = null;
      _flat.clear();
      _flatResults = [];
    });
  }

  Future<void> _capturePhoto() async {
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
    Haptics.light();
    _deletePendingPhoto();
    setState(() => _photo = picked);
  }

  /// Returns null on success, or an error message if the upload failed.
  /// Never throws — a failed photo upload must not block the visitor entry
  /// itself, since the entry has already been created server-side by the
  /// time this runs.
  Future<String?> _uploadPhoto(Dio dio, String visitorId, XFile photo) async {
    try {
      final compressed = await compressForUpload(File(photo.path));
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(compressed, filename: '$visitorId.jpg'),
      });
      await dio.post('/visitors/$visitorId/upload-photo', data: form);
      return null;
    } on DioException catch (err) {
      return '${err.response?.data ?? err.message}';
    } catch (err) {
      return '$err';
    }
  }

  void _deletePendingPhoto() {
    final path = _photo?.path;
    if (path == null) return;
    unawaited(File(path).delete().catchError((_) => File(path)));
  }

  void _resetForm() {
    _name.clear();
    _phone.clear();
    _vehicle.clear();
    _note.clear();
    _deletePendingPhoto();
    setState(() {
      _purpose = 'Guest';
      _photo = null;
      _selectedFlat = null;
      _flat.clear();
      _flatResults = [];
    });
  }

  Future<void> _submit(Dio dio) async {
    final selectedFlat = _selectedFlat;
    if (selectedFlat == null) {
      Haptics.heavy();
      showAppToast(context, 'Select a flat first', kind: AppToastKind.alert);
      return;
    }
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.length < 2) {
      Haptics.heavy();
      showAppToast(context, 'Enter the visitor\'s name',
          kind: AppToastKind.alert);
      return;
    }
    if (phone.isNotEmpty && !RegExp(r'^[0-9]{10}$').hasMatch(phone)) {
      Haptics.heavy();
      showAppToast(context, 'Phone must be 10 digits, or left blank',
          kind: AppToastKind.alert);
      return;
    }
    final payload = {
      'memberId': selectedFlat['memberId'],
      'name': name,
      'phone': phone,
      'purpose': _purpose,
      if (_vehicle.text.trim().isNotEmpty)
        'vehicleNumber': _vehicle.text.trim(),
      'note': _note.text.trim(),
      'clientRef': OfflineOutbox.generateClientRef(),
      'queuedAt': DateTime.now().toUtc().toIso8601String(),
    };
    setState(() => _submitting = true);
    Haptics.medium();
    try {
      final res = await dio.post('/visitors/guard-request', data: payload);
      if (!mounted) return;
      final visitorId = (res.data as Map)['_id'] as String?;
      String? photoError;
      if (_photo != null && visitorId != null) {
        photoError = await _uploadPhoto(dio, visitorId, _photo!);
      }
      if (!mounted) return;
      Haptics.success();
      if (photoError != null) {
        showAppToast(context, 'Resident notified, but photo upload failed: $photoError',
            kind: AppToastKind.alert);
      } else {
        showAppToast(context, 'Resident notified — awaiting approval',
            kind: AppToastKind.success);
      }
      _resetForm();
      // Gate tab only refreshes off SocketBus events or its own 20s poll —
      // this device just created the entry, so bump it directly instead of
      // waiting on a round trip through the poller.
      SocketBus.visitorEvents.value++;
      widget.onDone?.call();
    } on DioException catch (_) {
      OfflineOutbox.enqueue(payload, endpoint: '/visitors/guard-request');
      if (!mounted) return;
      Haptics.light();
      showAppToast(
          context, 'No connection — saved offline, will sync automatically',
          kind: AppToastKind.info);
      _resetForm();
      widget.onDone?.call();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Offline Entry: a direct walk-in log that doesn't wait on resident
  // approval (no flat needs to be selected) — POSTs to /visitors/offline-entry
  // which marks the visitor Entered immediately. Same clientRef/queuedAt
  // pattern as the approval flow, so a connectivity drop mid-submit still
  // queues into OfflineOutbox and syncs automatically once back online.
  Future<void> _submitOffline(Dio dio) async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.length < 2) {
      Haptics.heavy();
      showAppToast(context, 'Enter the visitor\'s name',
          kind: AppToastKind.alert);
      return;
    }
    if (phone.isNotEmpty && !RegExp(r'^[0-9]{10}$').hasMatch(phone)) {
      Haptics.heavy();
      showAppToast(context, 'Phone must be 10 digits, or left blank',
          kind: AppToastKind.alert);
      return;
    }
    final payload = {
      'name': name,
      'phone': phone,
      'purpose': _purpose,
      if (_vehicle.text.trim().isNotEmpty)
        'vehicleNumber': _vehicle.text.trim(),
      'note': _note.text.trim(),
      'clientRef': OfflineOutbox.generateClientRef(),
      'queuedAt': DateTime.now().toUtc().toIso8601String(),
    };
    setState(() => _submitting = true);
    Haptics.medium();
    try {
      final res = await dio.post('/visitors/offline-entry', data: payload);
      if (!mounted) return;
      final visitorId = (res.data as Map)['visitor']?['_id'] as String? ??
          (res.data as Map)['_id'] as String?;
      String? photoError;
      if (_photo != null && visitorId != null) {
        photoError = await _uploadPhoto(dio, visitorId, _photo!);
      }
      if (!mounted) return;
      Haptics.success();
      if (photoError != null) {
        showAppToast(context, 'Entry logged, but photo upload failed: $photoError',
            kind: AppToastKind.alert);
      } else {
        showAppToast(context, 'Entry logged', kind: AppToastKind.success);
      }
      _resetForm();
      SocketBus.visitorEvents.value++;
      widget.onDone?.call();
    } on DioException catch (_) {
      OfflineOutbox.enqueue(payload, endpoint: '/visitors/offline-entry');
      if (!mounted) return;
      Haptics.light();
      showAppToast(context,
          'No connection — saved offline, will log automatically once back online',
          kind: AppToastKind.info);
      _resetForm();
      widget.onDone?.call();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dio = context.read<Dio>();
    final t = context.pulse;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('New Visitor Entry',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: t.fg1,
                letterSpacing: -0.3)),
        Text('Log a walk-in and notify the resident',
            style: TextStyle(fontSize: 12.5, color: t.fg4)),
        const SizedBox(height: 20),
        Text('1 · Select flat *',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: t.fg2)),
        const SizedBox(height: 8),
        if (_selectedFlat == null) ...[
          PulseSearchField(
              controller: _flat, hint: 'Search flat no, wing or resident...'),
          if (_searchingFlats)
            const Padding(
                padding: EdgeInsets.only(top: 10),
                child: PulseSpinner(size: 16)),
          if (_flatResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(PulseTokens.radius),
                border: Border.all(color: t.border),
              ),
              child: Column(
                children: _flatResults.map((f) {
                  final label =
                      '${f['wing'] ?? ''} ${f['flatNo'] ?? ''}'.trim();
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.home_rounded, color: t.brand, size: 18),
                    title: Text(label.isEmpty ? '${f['flatNo'] ?? ''}' : label,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: t.fg1)),
                    subtitle: Text('${f['ownerName'] ?? ''}',
                        style: TextStyle(color: t.fg3)),
                    onTap: () => _selectFlat(f),
                  );
                }).toList(),
              ),
            ),
        ] else
          PulseCard(
            child: Row(
              children: [
                Icon(Icons.home_rounded, color: t.brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_selectedFlat!['wing'] ?? ''} ${_selectedFlat!['flatNo'] ?? ''} · ${_selectedFlat!['ownerName'] ?? ''}'
                        .trim(),
                    style: TextStyle(fontWeight: FontWeight.w700, color: t.fg1),
                  ),
                ),
                TextButton(onPressed: _clearFlat, child: const Text('Change')),
              ],
            ),
          ),
        const SizedBox(height: 22),
        Text('2 · Visitor details',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: t.fg2)),
        const SizedBox(height: 10),
        Text('Visitor name *', style: TextStyle(fontSize: 12, color: t.fg3)),
        const SizedBox(height: 6),
        TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: 'Full name')),
        const SizedBox(height: 14),
        Text('Phone', style: TextStyle(fontSize: 12, color: t.fg3)),
        const SizedBox(height: 6),
        TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration:
                const InputDecoration(hintText: '10-digit mobile (optional)')),
        const SizedBox(height: 14),
        Text('Purpose *', style: TextStyle(fontSize: 12, color: t.fg3)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _purposes.map((p) {
            final (label, icon) = p;
            final active = _purpose == label;
            return GestureDetector(
              onTap: () {
                Haptics.select();
                setState(() => _purpose = label);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? t.brandSoft : t.surface,
                  border: Border.all(
                      color: active ? t.brand : t.border, width: 1.5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: active ? t.brand : t.fg3),
                    const SizedBox(width: 6),
                    Text(label,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: active ? t.brand : t.fg3)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        Text('Vehicle number', style: TextStyle(fontSize: 12, color: t.fg3)),
        const SizedBox(height: 6),
        TextField(
            controller: _vehicle,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'MH01AB1234')),
        const SizedBox(height: 14),
        Text('Visitor photo', style: TextStyle(fontSize: 12, color: t.fg3)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _capturePhoto,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(PulseTokens.radius),
              border: Border.all(color: t.border, width: 1.5),
            ),
            child: _photo == null
                ? Column(
                    children: [
                      Icon(Icons.camera_alt_outlined, color: t.fg3, size: 26),
                      const SizedBox(height: 8),
                      Text('Tap to capture with gate camera',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: t.fg2)),
                    ],
                  )
                : Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(_photo!.path),
                            height: 90, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                      Text('Tap to retake',
                          style: TextStyle(fontSize: 12, color: t.fg4)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Text('Note', style: TextStyle(fontSize: 12, color: t.fg3)),
        const SizedBox(height: 6),
        TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: 'Optional extra context for the resident')),
        const SizedBox(height: 22),
        PulseButton(
            label: 'Log entry — needs approval',
            full: true,
            loading: _submitting,
            onTap: () => _submit(dio)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: Divider(color: t.border, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('or, if the flat can\'t be reached',
                  style: TextStyle(fontSize: 11, color: t.fg4)),
            ),
            Expanded(child: Divider(color: t.border, height: 1)),
          ],
        ),
        const SizedBox(height: 10),
        PulseButton(
          label: 'Offline Entry — log now, no approval',
          full: true,
          variant: PulseBtnVariant.secondary,
          loading: _submitting,
          onTap: () => _submitOffline(dio),
        ),
      ],
    );
  }
}