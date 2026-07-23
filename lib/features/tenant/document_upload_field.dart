import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// One document slot's constraints — mirrors the mobile-backend's
/// FIELD_CONFIG in tenantRequest.controller.ts exactly, so a rejection here
/// matches what the server would reject anyway, just without a round-trip.
class DocumentFieldConfig {
  final String field;
  final int maxBytes;
  final List<String> allowedExtensions;
  final String label;
  const DocumentFieldConfig({
    required this.field,
    required this.maxBytes,
    required this.allowedExtensions,
    required this.label,
  });
}

const List<DocumentFieldConfig> tenantDocumentFields = [
  DocumentFieldConfig(
      field: 'contract',
      maxBytes: 1048576,
      allowedExtensions: ['pdf'],
      label: 'Lease contract (PDF)'),
  DocumentFieldConfig(
      field: 'signature',
      maxBytes: 524288,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      label: 'Tenant signature'),
  DocumentFieldConfig(
      field: 'aadhaar',
      maxBytes: 524288,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      label: 'Aadhaar card photo'),
  DocumentFieldConfig(
      field: 'policeVerification',
      maxBytes: 524288,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      label: 'Police verification photo'),
];
String _sizeLabel(int bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).round()}MB'
    : '${(bytes / 1024).round()}KB';

/// Pure so it's unit-testable without picking a real file. Returns an error
/// message, or null if the file passes. No minimum size is enforced — only
/// an upper bound (see design spec: "256KB-512KB" is expected/typical size,
/// not a hard floor).
String? validateDocumentFile(
    DocumentFieldConfig config, int fileSizeBytes, String fileExtension) {
  final ext = fileExtension.toLowerCase().replaceFirst('.', '');
  if (!config.allowedExtensions.contains(ext)) {
    return '${config.label} must be a ${config.allowedExtensions.map((e) => e.toUpperCase()).join('/')} file';
  }
  if (fileSizeBytes > config.maxBytes) {
    return '${config.label} must be under ${_sizeLabel(config.maxBytes)} (this file is ${_sizeLabel(fileSizeBytes)})';
  }
  return null;
}

/// A single tap-to-pick document slot. Reports the picked, validated file's
/// local path back via [onPicked] once it passes [validateDocumentFile];
/// shows an inline error and does not call [onPicked] otherwise.
class DocumentUploadField extends StatefulWidget {
  final DocumentFieldConfig config;
  final ValueChanged<String> onPicked;
  const DocumentUploadField(
      {super.key, required this.config, required this.onPicked});
  @override
  State<DocumentUploadField> createState() => _DocumentUploadFieldState();
}

class _DocumentUploadFieldState extends State<DocumentUploadField> {
  String? _fileName;
  String? _error;
  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.config.allowedExtensions,
    );
    final picked = result?.files.single;
    if (picked == null || picked.path == null) return;
    final ext = picked.extension ?? '';
    // Don't trust PlatformFile.size directly - on Android it's unreliable
    // for files resolved through certain content providers (cloud storage,
    // some file managers), sometimes reporting 0 or a stale value, which
    // would let an oversized file sail through this check (0 <= maxBytes
    // always passes). Re-derive from disk instead, since `path` is a real
    // local file at this point on both Android and iOS. Falls back to the
    // reported size only if the file can't be read that way.
    int actualSize;
    try {
      actualSize = File(picked.path!).lengthSync();
    } catch (_) {
      actualSize = picked.size;
    }
    final error = validateDocumentFile(widget.config, actualSize, ext);
    setState(() {
      _error = error;
      _fileName = error == null ? picked.name : null;
    });
    if (error == null) widget.onPicked(picked.path!);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: _pick,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
                color: _error != null ? Colors.red : Colors.grey.shade400),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(_fileName != null ? Icons.check_circle : Icons.upload_file,
                  color: _fileName != null ? Colors.green : Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.config.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (_fileName != null)
                      Text(_fileName!,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    if (_error != null)
                      Text(_error!,
                          style:
                              const TextStyle(fontSize: 12, color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
