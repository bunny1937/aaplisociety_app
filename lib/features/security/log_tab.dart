import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_error.dart';
import '../../core/socket/socket_bus.dart';
import '../../core/theme/haptics.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/visitor_card.dart';
import '../member/pulse/pulse.dart';

class LogTab extends StatefulWidget {
  const LogTab({super.key});
  @override
  State<LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<LogTab> {
  static const _filters = ['All', 'Inside', 'Exited', 'Rejected'];
  final _listKey = GlobalKey<AsyncViewState<List>>();
  final _search = TextEditingController();
  String _filter = 'All';
  @override
  void initState() {
    super.initState();
    SocketBus.visitorEvents.addListener(_onEvent);
    _search.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    SocketBus.visitorEvents.removeListener(_onEvent);
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onEvent() => _listKey.currentState?.reload();
  void _onSearchChanged() => setState(() {});
  Future<void> _checkOut(Dio dio, String id) async {
    Haptics.medium();
    try {
      await dio.post('/visitors/$id/exit');
      if (!mounted) return;
      Haptics.success();
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
    final t = context.pulse;
    return AsyncView<List>(
      key: _listKey,
      fetch: () async => (await dio.get('/visitors')).data['visitors'] as List,
      cacheKey: '/visitors',
      builder: (context, all) {
        final query = _search.text.trim().toLowerCase();
        final filtered = all.where((v) {
          final status = '${v['status']}';
          final matchesFilter = switch (_filter) {
            'Inside' => status == 'Entered',
            'Exited' => status == 'Exited',
            'Rejected' => status == 'Rejected',
            _ => true,
          };
          if (!matchesFilter) return false;
          if (query.isEmpty) return true;
          final haystack =
              '${v['name']} ${v['vehicleNumber'] ?? ''}'.toLowerCase();
          return haystack.contains(query);
        }).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('Visitor Log',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: t.fg1,
                    letterSpacing: -0.3)),
            Text('Searchable history of every gate entry',
                style: TextStyle(fontSize: 12.5, color: t.fg4)),
            const SizedBox(height: 16),
            PulseSearchField(
                controller: _search, hint: 'Name, flat, vehicle...'),
            const SizedBox(height: 12),
            PulseSegmented<String>(
              options: _filters
                  .map((f) => PulseSegmentedOption(value: f, label: f))
                  .toList(),
              value: _filter,
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              const PulseEmptyState(
                  illo: PulseIllo.noData, title: 'No matching entries')
            else
              ...filtered.asMap().entries.map((e) {
                final v = e.value as Map;
                final id = v['_id'] as String;
                final status = '${v['status']}';
                final entryTime =
                    DateTime.tryParse('${v['entryTime'] ?? v['createdAt']}');
                final timeLabel = entryTime == null
                    ? ''
                    : DateFormat('hh:mm a')
                        .format(entryTime.toLocal())
                        .toLowerCase();
                final vehicle = '${v['vehicleNumber'] ?? ''}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LedgerVisitorCard(
                    index: e.key,
                    name: '${v['name']}',
                    subtitle:
                        '${v['purpose'] ?? ''} · $timeLabel${vehicle.isNotEmpty ? ' · $vehicle' : ''}',
                    status: status,
                    statusColor: switch (status) {
                      'Entered' => t.success,
                      'Rejected' => t.danger,
                      _ => t.fg3,
                    },
                    actions: status == 'Entered'
                        ? SizedBox(
                            width: double.infinity,
                            child: PulseButton(
                              label: 'Check out',
                              full: true,
                              size: PulseBtnSize.sm,
                              variant: PulseBtnVariant.secondary,
                              onTap: () => _checkOut(dio, id),
                            ),
                          )
                        : null,
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
