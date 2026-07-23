import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/haptics.dart';
import '../../core/widgets/app_toast.dart';
import '../auth/bloc/auth_bloc.dart';
import '../member/pulse/pulse.dart';

class GuardProfileTab extends StatefulWidget {
  const GuardProfileTab({super.key});
  @override
  State<GuardProfileTab> createState() => _GuardProfileTabState();
}

class _GuardProfileTabState extends State<GuardProfileTab> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _gateLabel = TextEditingController();
  String _username = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _gateLabel.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dio = context.read<Dio>();
    setState(() => _loading = true);
    try {
      final res = await dio.get('/me');
      if (!mounted) return;
      final user = Map<String, dynamic>.from(res.data['user'] as Map);
      _name.text = '${user['name'] ?? ''}';
      _phone.text = '${user['phone'] ?? ''}';
      _gateLabel.text = '${user['gateLabel'] ?? ''}';
      setState(() => _username = '${user['username'] ?? ''}');
    } on DioException catch (err) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(Dio dio) async {
    final name = _name.text.trim();
    if (name.length < 2) {
      Haptics.heavy();
      showAppToast(context, 'Enter your name', kind: AppToastKind.alert);
      return;
    }
    final phone = _phone.text.trim();
    if (phone.isNotEmpty && !RegExp(r'^[0-9]{10}$').hasMatch(phone)) {
      Haptics.heavy();
      showAppToast(context, 'Phone must be 10 digits, or left blank',
          kind: AppToastKind.alert);
      return;
    }
    setState(() => _saving = true);
    Haptics.medium();
    try {
      await dio.patch('/me', data: {
        'name': name,
        'phone': phone,
        'gateLabel': _gateLabel.text.trim(),
      });
      if (!mounted) return;
      Haptics.success();
      showAppToast(context, 'Profile updated', kind: AppToastKind.success);
    } on DioException catch (err) {
      if (!mounted) return;
      Haptics.heavy();
      showAppToast(context, apiErrorMessage(err, 'Could not update profile'),
          kind: AppToastKind.alert);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dio = context.read<Dio>();
    final t = context.pulse;
    if (_loading) {
      return const Center(child: PulseSpinner());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Center(
          child: Column(
            children: [
              PulseAvatar(
                  name: _name.text.isEmpty ? 'Guard' : _name.text, size: 72),
              const SizedBox(height: 10),
              Text(_username.isEmpty ? '' : '@$_username',
                  style: TextStyle(fontSize: 12.5, color: t.fg4)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Full name', style: TextStyle(fontSize: 12, color: t.fg3)),
        const SizedBox(height: 6),
        TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: 'Your name')),
        const SizedBox(height: 14),
        Text('Contact number', style: TextStyle(fontSize: 12, color: t.fg3)),
        const SizedBox(height: 6),
        TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '10-digit mobile')),
        const SizedBox(height: 14),
        Text('Gate label', style: TextStyle(fontSize: 12, color: t.fg3)),
        const SizedBox(height: 6),
        TextField(
            controller: _gateLabel,
            decoration:
                const InputDecoration(hintText: 'e.g. Main Gate, Gate 2')),
        const SizedBox(height: 22),
        PulseButton(
            label: 'Save changes',
            full: true,
            loading: _saving,
            onTap: () => _save(dio)),
        const SizedBox(height: 10),
        PulseButton(
          label: 'Log out',
          full: true,
          variant: PulseBtnVariant.secondary,
          onTap: () {
            Haptics.heavy();
            context.read<AuthBloc>().add(LogoutRequested());
          },
        ),
      ],
    );
  }
}
