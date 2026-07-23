import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/haptics.dart';
import '../member/pulse/pulse.dart';

class VerifyTab extends StatefulWidget {
  const VerifyTab({super.key});
  @override
  State<VerifyTab> createState() => _VerifyTabState();
}

class _VerifyTabState extends State<VerifyTab> {
  int _mode = 0; // 0 = OTP, 1 = QR token
  final _otp = TextEditingController();
  final _qr = TextEditingController();
  bool _submitting = false;
  Map? _result;
  @override
  void dispose() {
    _otp.dispose();
    _qr.dispose();
    super.dispose();
  }

  Future<void> _verify(Dio dio) async {
    final code = (_mode == 0 ? _otp.text : _qr.text).trim();
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
        SnackBar(
            content: Text(apiErrorMessage(err, 'Invalid or expired pass'))),
      );
    }
  }

  void _reset() {
    _otp.clear();
    _qr.clear();
    setState(() => _result = null);
  }

  @override
  Widget build(BuildContext context) {
    final dio = context.read<Dio>();
    final t = context.pulse;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('Verify Gate Pass',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: t.fg1,
                letterSpacing: -0.3)),
        Text('Validate a pre-approved visitor',
            style: TextStyle(fontSize: 12.5, color: t.fg4)),
        const SizedBox(height: 18),
        if (_result == null) ...[
          Row(
            children: [
              Expanded(
                  child: _ModeChip(
                      label: 'OTP',
                      icon: Icons.dialpad_rounded,
                      active: _mode == 0,
                      onTap: () {
                        Haptics.select();
                        setState(() => _mode = 0);
                      })),
              const SizedBox(width: 10),
              Expanded(
                  child: _ModeChip(
                      label: 'QR token',
                      icon: Icons.qr_code_rounded,
                      active: _mode == 1,
                      onTap: () {
                        Haptics.select();
                        setState(() => _mode = 1);
                      })),
            ],
          ),
          const SizedBox(height: 18),
          if (_mode == 0)
            TextField(
              controller: _otp,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.w800),
              decoration:
                  const InputDecoration(hintText: '000000', counterText: ''),
              maxLength: 6,
            )
          else
            TextField(
              key: const ValueKey('qr-field'),
              controller: _qr,
              autofocus: true,
              decoration:
                  const InputDecoration(hintText: 'Paste the scanned code'),
            ),
          const SizedBox(height: 18),
          PulseButton(
              label: 'Verify & grant entry',
              full: true,
              loading: _submitting,
              icon: Icons.shield_rounded,
              onTap: () => _verify(dio)),
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                const PulseIllustration(kind: PulseIllo.shield),
                const SizedBox(height: 14),
                Text('Verified visitor details will appear here',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: t.fg3)),
              ],
            ),
          ),
        ] else
          _buildSuccessPanel(t, _result!),
      ],
    );
  }

  Widget _buildSuccessPanel(PulseTokens t, Map visitor) {
    return PulseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration:
                    BoxDecoration(color: t.successSoft, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, color: t.success, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Entry granted',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: t.fg1)),
                    Text('Visitor admitted',
                        style: TextStyle(fontSize: 12.5, color: t.fg4)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _InfoRow(label: 'Name', value: '${visitor['name'] ?? '—'}'),
          _InfoRow(label: 'Phone', value: '${visitor['phone'] ?? '—'}'),
          _InfoRow(label: 'Purpose', value: '${visitor['purpose'] ?? '—'}'),
          const SizedBox(height: 16),
          PulseButton(label: 'Done', full: true, onTap: _reset),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.08);
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ModeChip(
      {required this.label,
      required this.icon,
      required this.active,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? t.brandSoft : t.surface,
          border: Border.all(color: active ? t.brand : t.border, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? t.brand : t.fg3),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? t.brand : t.fg3)),
          ],
        ),
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
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: t.fg4)),
          Text(value,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700, color: t.fg1)),
        ],
      ),
    );
  }
}
