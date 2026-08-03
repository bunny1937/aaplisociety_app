import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_error.dart';
import '../../core/widgets/app_toast.dart';
import '../member/pulse/pulse.dart';
import 'tenant_api.dart';
import 'tenant_ui.dart';

/// **Owner-side document review.**
///
/// What existed before: a single grey pill that said "3 missing". That was the
/// whole feature. There was no way to see the document the tenant DID upload,
/// no way to open it, no way to accept it, and no way to send it back and say
/// why. Tapping the "missing documents" strip pushed the owner to
/// `/manage-tenants` — the ADD-a-tenant screen — which is not where any of
/// this lives.
///
/// This sheet is the actual review surface: every one of the four documents,
/// its real state, an Open action for the ones on file, Accept / Send back with
/// a reason, and an inline upload for the ones still missing.
Future<bool> showTenantDocumentsSheet(
  BuildContext context, {
  required Map tenancy,
  required bool asOwner,
}) async {
  final changed = await showPulseSheet<bool>(
    context,
    title: asOwner ? 'Tenant documents' : 'My documents',
    full: true,
    builder: (ctx) => _DocumentsBody(tenancy: tenancy, asOwner: asOwner),
  );
  return changed == true;
}

class _DocumentsBody extends StatefulWidget {
  const _DocumentsBody({required this.tenancy, required this.asOwner});
  final Map tenancy;
  final bool asOwner;
  @override
  State<_DocumentsBody> createState() => _DocumentsBodyState();
}

class _DocumentsBodyState extends State<_DocumentsBody> {
  late Map<String, dynamic> _docs = _readDocs(widget.tenancy);
  String? _busyField;
  bool _dirty = false;

  static Map<String, dynamic> _readDocs(Map tenancy) {
    final raw = tenancy['documents'];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  String get _requestId => '${widget.tenancy['_id'] ?? ''}';

  /// The backend stores `contractKey`, `signatureKey`, ... but older records
  /// (and the add-tenant form) sometimes wrote the bare field name. Accept both
  /// rather than declaring a document missing because of a suffix.
  bool _onFile(TenantDocField f) {
    final v = _docs['${f.field}Key'] ?? _docs[f.field];
    return v != null && '$v'.trim().isNotEmpty && '$v' != 'null';
  }

  Map? _review(TenantDocField f) {
    final r = _docs['${f.field}Review'];
    return r is Map ? r : null;
  }

  Future<void> _open(TenantDocField f) async {
    setState(() => _busyField = f.field);
    try {
      final url = await fetchTenantDocumentUrl(
          context.read<Dio>(), _requestId, f.field);
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        showAppToast(context, 'That document is no longer on file',
            kind: AppToastKind.alert);
        return;
      }
      final ok =
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showAppToast(context, 'Could not open the document',
            kind: AppToastKind.alert);
      }
    } catch (err) {
      if (mounted) {
        showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
      }
    } finally {
      if (mounted) setState(() => _busyField = null);
    }
  }

  Future<void> _submitReview(TenantDocField f, bool accept) async {
    final dio = context.read<Dio>();
    String? reason;
    if (!accept) {
      reason = await _askReason(f);
      // Sending a document back without saying why is exactly the behaviour
      // being complained about, so the reason is mandatory here.
      if (reason == null || reason.trim().isEmpty) return;
    }
    setState(() => _busyField = f.field);
    try {
      final docs = await reviewTenantDocument(
        dio,
        _requestId,
        field: f.field,
        accept: accept,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        if (docs != null) _docs = docs;
        _dirty = true;
        _busyField = null;
      });
      showAppToast(
        context,
        accept ? '${f.label} accepted' : '${f.label} sent back to the tenant',
        kind: accept ? AppToastKind.success : AppToastKind.alert,
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _busyField = null);
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    }
  }

  Future<String?> _askReason(TenantDocField f) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Send back ${f.label}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your tenant sees this reason and can re-upload. Be specific.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 200,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. Photo is blurred, last page missing',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Send back',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _upload(TenantDocField f) async {
    final dio = context.read<Dio>();
    setState(() => _busyField = f.field);
    try {
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      );
      final file = picked?.files.single;
      if (file == null || file.bytes == null) {
        if (mounted) setState(() => _busyField = null);
        return;
      }
      final key = await uploadTenantDocumentBytes(dio, f.field, file.bytes!,
          filename: file.name);
      final res = await attachTenantDocument(dio, _requestId, f.field, key);
      final docs = res['documents'];
      if (!mounted) return;
      setState(() {
        if (docs is Map) {
          _docs = Map<String, dynamic>.from(docs);
        } else {
          _docs['${f.field}Key'] = key;
        }
        _dirty = true;
        _busyField = null;
      });
      showAppToast(context, '${f.label} uploaded', kind: AppToastKind.success);
    } catch (err) {
      if (!mounted) return;
      setState(() => _busyField = null);
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final onFile = kTenantDocFields.where(_onFile).length;
    final complete = onFile == kTenantDocFields.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_dirty);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: complete ? t.successSoft : t.warningSoft,
              borderRadius: BorderRadius.circular(PulseTokens.radius),
            ),
            child: Row(
              children: [
                Icon(
                  complete
                      ? Icons.verified_rounded
                      : Icons.pending_actions_rounded,
                  size: 17,
                  color: complete ? t.success : t.warning,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '$onFile of ${kTenantDocFields.length} documents received',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: t.fg1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final f in kTenantDocFields)
            _DocReviewTile(
              field: f,
              onFile: _onFile(f),
              review: _review(f),
              busy: _busyField == f.field,
              asOwner: widget.asOwner,
              onOpen: () => _open(f),
              onAccept: () => _submitReview(f, true),
              onReject: () => _submitReview(f, false),
              onUpload: () => _upload(f),
            ),
          const SizedBox(height: 6),
          Text(
            widget.asOwner
                ? 'Accepting a document confirms you have checked it. Sending '
                    'one back notifies your tenant with your reason.'
                : 'Documents your owner sends back appear here with their '
                    'reason so you can re-upload.',
            style: TextStyle(fontSize: 11.5, color: t.fg5, height: 1.4),
          ),
          const SizedBox(height: 12),
          PulseButton(
            label: 'Done',
            full: true,
            variant: PulseBtnVariant.secondary,
            onTap: () => Navigator.of(context).pop(_dirty),
          ),
        ],
      ),
    );
  }
}

class _DocReviewTile extends StatelessWidget {
  const _DocReviewTile({
    required this.field,
    required this.onFile,
    required this.review,
    required this.busy,
    required this.asOwner,
    required this.onOpen,
    required this.onAccept,
    required this.onReject,
    required this.onUpload,
  });

  final TenantDocField field;
  final bool onFile;
  final Map? review;
  final bool busy;
  final bool asOwner;
  final VoidCallback onOpen;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final status = '${review?['status'] ?? ''}'.toLowerCase();
    final accepted = status == 'accepted';
    final returned = status == 'returned' || status == 'rejected';
    final reason = '${review?['reason'] ?? ''}'.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PulseCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(field.label,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: t.fg1)),
                ),
                if (busy)
                  const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else if (accepted)
                  const PulsePill(label: 'Accepted', tone: PulseTone.approved)
                else if (returned)
                  const PulsePill(label: 'Sent back', tone: PulseTone.rejected)
                else if (onFile)
                  const PulsePill(label: 'On file', tone: PulseTone.info)
                else
                  const PulsePill(label: 'Missing', tone: PulseTone.pending),
              ],
            ),
            if (returned && reason.isNotEmpty) ...[
              const SizedBox(height: 7),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: t.dangerSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text('Reason: $reason',
                    style: TextStyle(fontSize: 11.5, color: t.fg2)),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onFile)
                  PulseButton(
                    label: 'Open',
                    icon: Icons.open_in_new_rounded,
                    variant: PulseBtnVariant.secondary,
                    size: PulseBtnSize.sm,
                    onTap: busy ? null : onOpen,
                  ),
                if (onFile && asOwner && !accepted)
                  PulseButton(
                    label: 'Accept',
                    icon: Icons.check_rounded,
                    size: PulseBtnSize.sm,
                    onTap: busy ? null : onAccept,
                  ),
                if (onFile && asOwner)
                  PulseButton(
                    label: 'Send back',
                    icon: Icons.undo_rounded,
                    variant: PulseBtnVariant.danger,
                    size: PulseBtnSize.sm,
                    onTap: busy ? null : onReject,
                  ),
                if (!onFile)
                  PulseButton(
                    label: 'Upload',
                    icon: Icons.upload_file_rounded,
                    variant: PulseBtnVariant.secondary,
                    size: PulseBtnSize.sm,
                    onTap: busy ? null : onUpload,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
