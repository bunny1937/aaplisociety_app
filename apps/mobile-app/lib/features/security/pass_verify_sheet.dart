import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_x.dart';
import '../../core/theme/haptics.dart';

/// Guard-facing pass verification — was previously a bare AlertDialog with a
/// single text field; this mirrors the web app's dedicated verify-pass page
/// (two tabs: OTP or QR token, both hitting the same endpoint since the
/// backend checks the code against either hash) with a proper success panel
/// instead of just a toast, matching web's "✅ Entry granted" confirmation.
Future<void> showPassVerifySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => const _PassVerifySheetBody(),
  );
}

class _PassVerifySheetBody extends StatefulWidget {
  const _PassVerifySheetBody();
  @override
  State<_PassVerifySheetBody> createState() => _PassVerifySheetBodyState();
}

class _PassVerifySheetBodyState extends State<_PassVerifySheetBody> {
  int _tab = 0; // 0 = OTP, 1 = QR token
  final _otpController = TextEditingController();
  final _qrController = TextEditingController();
  bool _submitting = false;
  Map? _result; // set on success, switches the sheet to the confirmation panel

  @override
  void dispose() {
    _otpController.dispose();
    _qrController.dispose();
    super.dispose();
  }

  Future<void> _verify(Dio dio) async {
    final code = (_tab == 0 ? _otpController.text : _qrController.text).trim();
    if (code.isEmpty) {
      Haptics.heavy();
      return;
    }
    Haptics.medium();
    setState(() => _submitting = true);
    try {
      final res = await dio.post('/visitors/pass/verify', data: {'code': code});
      if (!mounted) return;
      Haptics.success();
      setState(() {
        _submitting = false;
        _result = Map<String, dynamic>.from(res.data['visitor'] as Map);
      });
    } on DioException catch (err) {
      if (!mounted) return;
      Haptics.heavy();
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(err, 'Invalid or expired pass'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dio = context.read<Dio>();
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _result != null ? _buildSuccessPanel(_result!) : _buildForm(dio),
      ),
    );
  }

  Widget _buildForm(Dio dio) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.qr_code_scanner_rounded, color: AppColors.brass, size: 22),
            const SizedBox(width: 10),
            Text('Verify gate pass', style: GoogleFonts.fraunces(fontSize: 18, fontWeight: FontWeight.w600, color: context.headline)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _TabChip(label: '🔢 OTP', selected: _tab == 0, onTap: () => setState(() => _tab = 0))),
            const SizedBox(width: 10),
            Expanded(child: _TabChip(label: '🎟️ QR token', selected: _tab == 1, onTap: () => setState(() => _tab = 1))),
          ],
        ),
        const SizedBox(height: 16),
        if (_tab == 0)
          TextField(
            controller: _otpController,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 20, letterSpacing: 4, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(labelText: '6-digit OTP', hintText: '123456'),
          )
        else
          TextField(
            controller: _qrController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'QR token', hintText: 'Paste the scanned code'),
          ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting ? null : () => _verify(dio),
            child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Verify & admit'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessPanel(Map visitor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.green, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Entry granted', style: GoogleFonts.fraunces(fontSize: 18, fontWeight: FontWeight.w600, color: context.headline)),
                  Text('Visitor admitted', style: GoogleFonts.manrope(fontSize: 12.5, color: AppColors.inkMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _InfoRow(label: 'Name', value: '${visitor['name'] ?? '—'}'),
        _InfoRow(label: 'Phone', value: '${visitor['phone'] ?? '—'}'),
        _InfoRow(label: 'Purpose', value: '${visitor['purpose'] ?? '—'}'),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.brass.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(color: selected ? AppColors.brass : AppColors.inkMuted.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? AppColors.brass : AppColors.inkMuted)),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.manrope(fontSize: 13, color: AppColors.inkMuted)),
          Text(value, style: GoogleFonts.manrope(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.headline)),
        ],
      ),
    );
  }
}
