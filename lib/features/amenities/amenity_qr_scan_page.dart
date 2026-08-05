import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../member/pulse/pulse.dart';
import 'data/amenities_api.dart';
import 'widgets/amenity_bits.dart';

/// Scan-to-check-in.
///
/// The camera is the whole screen because that is the only thing this page does.
/// Nothing about the token is interpreted on the device: the raw payload is
/// posted as-is and the server decides whether it is valid, expired, revoked or
/// for another society. A phone should not be trusted to make that call.
class AmenityQrScanPage extends StatefulWidget {
  const AmenityQrScanPage({super.key});

  @override
  State<AmenityQrScanPage> createState() => AmenityQrScanPageState();
}

// Public: widget tests drive scans directly (handleScannedPayload) instead of
// constructing a MobileScanner BarcodeCapture, which the camera plugin does
// not make easy to fake. The camera itself is still the only entry point on
// a real device — this seam exists for tests, not as a second product path.
class AmenityQrScanPageState extends State<AmenityQrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _handling = false;
  bool _checkingOut = false;
  String? _error;
  CheckInResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Flips whether the next scan checks in or checks out. Exposed for the
  /// header toggle and for tests.
  void setDirection({required bool checkingOut}) {
    setState(() => _checkingOut = checkingOut);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null) return;
    await handleScannedPayload(raw);
  }

  /// Posts the raw scanned payload verbatim -- see the file comment. Public
  /// so both the camera callback and tests can drive it the same way.
  Future<void> handleScannedPayload(String raw) async {
    if (_handling) return;
    setState(() {
      _handling = true;
      _error = null;
    });
    // Fire-and-forget: _handling already gates re-entry synchronously above,
    // so posting to the server does not need to wait for the camera to
    // actually stop. Awaiting this platform call previously hung forever in
    // the widget-test host, which has no camera to answer it.
    unawaited(_controller.stop());

    try {
      final result = _checkingOut
          ? await qrCheckOut(context.read<Dio>(), raw: raw)
          : await qrCheckIn(context.read<Dio>(), raw);
      if (!mounted) return;
      setState(() => _result = result);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (!mounted) return;
      setState(() {
        _error = (data is Map && data['error'] != null)
            ? data['error'].toString()
            : 'That code could not be used. Ask at the desk if it keeps failing.';
      });
    } finally {
      if (mounted) setState(() => _handling = false);
    }
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _result = null;
    });
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Scan to check in'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
            tooltip: 'Torch',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Framing guide. Purely to tell people where to point the phone.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(PulseTokens.radius),
              ),
            ),
          ),

          if (_handling)
            const Center(child: CircularProgressIndicator()),

          if (_result != null || _error != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(PulseTokens.radiusLg)),
                ),
                child: _result != null
                    ? _Success(result: _result!, onDone: () => Navigator.pop(context))
                    : _Failure(message: _error!, onRetry: _retry),
              ),
            ),

          if (_result == null && _error == null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 46,
              child: Text(
                'Point at the code posted at the entrance.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _Success extends StatelessWidget {
  final CheckInResult result;
  final VoidCallback onDone;
  const _Success({required this.result, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final cap = result.capacity;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: t.success, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.attendance.timeOut == null
                    ? 'Checked in'
                    : 'Checked out',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: t.fg1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          result.attendance.amenityName,
          style: TextStyle(fontSize: 14, color: t.fg3),
        ),
        if (result.slotLabel != null) ...[
          const SizedBox(height: 4),
          Text('Slot ${result.slotLabel}',
              style: TextStyle(fontSize: 12.5, color: t.fg4)),
        ],
        if (!cap.unlimited) ...[
          const SizedBox(height: 12),
          CapacityBar(capacity: cap),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onDone, child: const Text('Done')),
        ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Failure({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, color: t.danger, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Could not check in',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: t.fg1)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(message,
            style: TextStyle(fontSize: 13.5, height: 1.5, color: t.fg3)),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: onRetry,
                child: const Text('Scan again'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
