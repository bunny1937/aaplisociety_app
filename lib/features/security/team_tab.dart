import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/haptics.dart';
import '../../core/widgets/app_toast.dart';
import '../member/pulse/pulse.dart';

/// Guard-to-guard coordination: message a colleague about a pending
/// approval, or hand off (reassign) a specific visitor to them.
class TeamTab extends StatefulWidget {
  const TeamTab({super.key});
  @override
  State<TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends State<TeamTab> {
  List<Map> _guards = [];
  List<Map> _pending = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final dio = context.read<Dio>();
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        dio.get('/security/guards'),
        dio.get('/visitors', queryParameters: {'status': 'Pending'}),
      ]);
      if (!mounted) return;
      setState(() {
        _guards = List<Map>.from(results[0].data['guards'] as List);
        _pending = List<Map>.from(results[1].data['visitors'] as List);
      });
    } on DioException catch (err) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openGuardActions(Dio dio, Map guard) async {
    Haptics.select();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.message_rounded),
              title: const Text('Send a message'),
              onTap: () => Navigator.pop(sheetContext, 'message'),
            ),
            if (_pending.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: const Text('Hand off a pending visitor'),
                onTap: () => Navigator.pop(sheetContext, 'reassign'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'message') {
      await _sendMessage(dio, guard);
    } else if (action == 'reassign') {
      await _reassign(dio, guard);
    }
  }

  Future<void> _sendMessage(Dio dio, Map guard) async {
    final controller = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Message ${guard['name']}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 500,
          decoration:
              const InputDecoration(hintText: 'e.g. Cover the gate, back in 5'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Send')),
        ],
      ),
    );
    if (sent != true || controller.text.trim().isEmpty || !mounted) return;
    try {
      await dio.post('/security/message', data: {
        'toGuardId': guard['_id'],
        'message': controller.text.trim(),
      });
      if (!mounted) return;
      Haptics.success();
      showAppToast(context, 'Message sent to ${guard['name']}',
          kind: AppToastKind.success);
    } on DioException catch (err) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(err, 'Could not send message'),
          kind: AppToastKind.alert);
    }
  }

  Future<void> _reassign(Dio dio, Map guard) async {
    final visitor = await showModalBottomSheet<Map>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Hand off which visitor to ${guard['name']}?',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            ..._pending.map((v) => ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text('${v['name']}'),
                  subtitle: Text('${v['purpose'] ?? ''}'),
                  onTap: () => Navigator.pop(sheetContext, v),
                )),
          ],
        ),
      ),
    );
    if (visitor == null || !mounted) return;
    try {
      await dio.patch('/visitors/${visitor['_id']}/reassign',
          data: {'toGuardId': guard['_id']});
      if (!mounted) return;
      Haptics.success();
      showAppToast(context, '${visitor['name']} handed off to ${guard['name']}',
          kind: AppToastKind.success);
      _load();
    } on DioException catch (err) {
      if (!mounted) return;
      showAppToast(context, apiErrorMessage(err, 'Could not hand off visitor'),
          kind: AppToastKind.alert);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dio = context.read<Dio>();
    final t = context.pulse;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Team',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: t.fg1,
                  letterSpacing: -0.3)),
          Text('Coordinate with other guards on duty',
              style: TextStyle(fontSize: 12.5, color: t.fg4)),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: PulseSpinner()),
            )
          else if (_guards.isEmpty)
            const PulseEmptyState(
                illo: PulseIllo.allClear,
                title: 'No other guards on this society yet.')
          else
            ..._guards.map((g) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PulseCard(
                    child: InkWell(
                      onTap: () => _openGuardActions(dio, g),
                      child: Row(
                        children: [
                          PulseAvatar(name: '${g['name']}', size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${g['name']}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: t.fg1)),
                                if ('${g['gateLabel'] ?? ''}'.isNotEmpty)
                                  Text('${g['gateLabel']}',
                                      style: TextStyle(
                                          fontSize: 12, color: t.fg4)),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: t.fg4),
                        ],
                      ),
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
