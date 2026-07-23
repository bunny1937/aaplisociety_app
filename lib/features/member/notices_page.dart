import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../core/theme/haptics.dart';
import '../../core/socket/socket_bus.dart';
import '../../core/widgets/async_view.dart';
import 'pulse/pulse.dart';
import 'pulse/notice_emoji.dart';

/// Quick-glance overlay for the dashboard's top-right notice bell — shows
/// notices as a dismissible sheet over whatever the member was looking at,
/// instead of switching the bottom-nav to the Notices tab. Switching tabs
/// there meant pressing back from the bell landed nowhere to pop to (an
/// IndexedStack tab switch never pushes a route), so back closed the app
/// instead of returning to Home. The dedicated Notices tab (reached via the
/// bottom nav itself) is unaffected — this is only for the bell shortcut.
Future<void> showNoticesSheet(BuildContext context, Dio dio) {
  return showPulseSheet<void>(
    context,
    title: 'Notices',
    full: true,
    builder: (context) => _NoticesSheetBody(dio: dio),
  );
}

class _NoticesSheetBody extends StatefulWidget {
  final Dio dio;
  const _NoticesSheetBody({required this.dio});
  @override
  State<_NoticesSheetBody> createState() => _NoticesSheetBodyState();
}

class _NoticesSheetBodyState extends State<_NoticesSheetBody> {
  late final Future<List> _future =
      widget.dio.get('/notices').then((r) => r.data['notices'] as List);
  final _acknowledged = <String>{};
  bool _isUrgent(Map n) => n['priority'] == 'urgent' || n['priority'] == 'high';
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return FutureBuilder<List>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final notices = snapshot.data!;
        if (notices.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: PulseEmptyState(
                illo: PulseIllo.emptyInbox, title: 'No notices yet'),
          );
        }
        final urgent = notices.where((n) => _isUrgent(n as Map)).toList();
        final rest = notices.where((n) => !_isUrgent(n as Map)).toList();
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (urgent.isNotEmpty) ...[
                Text('🚨 Urgent',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: t.danger)),
                const SizedBox(height: 8),
                ...urgent.map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: NoticeCard(
                        notice: n as Map,
                        urgent: true,
                        acknowledged: _acknowledged.contains('${n['_id']}'),
                        onAcknowledge: () {
                          Haptics.success();
                          setState(() => _acknowledged.add('${n['_id']}'));
                        },
                      ),
                    )),
                const SizedBox(height: 8),
              ],
              ...rest.map((n) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NoticeCard(
                        notice: n as Map,
                        urgent: false,
                        acknowledged: false,
                        onAcknowledge: null),
                  )),
            ],
          ),
        );
      },
    );
  }
}

/// Notices tab — port of ui_kits/member-v2 `ScreensNoticesComplaints.jsx`
/// `NoticesScreen`: urgent-first section, acknowledge flow, segmented type
/// filter. Design uses a fixed 5-type filter; kept the current app's
/// dynamic tag-derived filtering instead (real `Notification.type`/`tag` is
/// free text, no enum — see MEMBER_V2_GAPS.md) restyled to the design's
/// segmented-pill look, with emoji mapped from the README table where a tag
/// matches. Acknowledge is local-only state, same as the design mock (no
/// backend ack endpoint exists).
class NoticesPage extends StatefulWidget {
  const NoticesPage({super.key});
  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  final _listKey = GlobalKey<AsyncViewState<List>>();
  String _filter = 'All';
  final _acknowledged = <String>{};
  @override
  void initState() {
    super.initState();
    SocketBus.noticeEvents.addListener(_onEvent);
  }

  @override
  void dispose() {
    SocketBus.noticeEvents.removeListener(_onEvent);
    super.dispose();
  }

  void _onEvent() => _listKey.currentState?.reload();
  String _tagOf(Map n) => '${n['tag'] ?? n['type'] ?? 'General'}';
  bool _isUrgent(Map n) => n['priority'] == 'urgent' || n['priority'] == 'high';
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final dio = context.read<Dio>();
    return SafeArea(
      bottom: false,
      child: AsyncView<List>(
        key: _listKey,
        fetch: () async => (await dio.get('/notices')).data['notices'] as List,
        cacheKey: '/notices',
        builder: (context, allNotices) {
          final tags = <String>{'All'};
          for (final n in allNotices) {
            tags.add(_tagOf(n as Map));
          }
          final notices = _filter == 'All'
              ? allNotices
              : allNotices.where((n) => _tagOf(n as Map) == _filter).toList();
          final urgent = notices.where((n) => _isUrgent(n as Map)).toList();
          final rest = notices.where((n) => !_isUrgent(n as Map)).toList();
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(
                  child: PulseTopBar(
                      title: 'Notice Board',
                      subtitle: 'Society announcements')),
              if (tags.length > 1)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: PulseSegmented<String>(
                        value: _filter,
                        onChanged: (v) => setState(() => _filter = v),
                        options: tags
                            .map((tg) => PulseSegmentedOption(
                                value: tg,
                                label: tg == 'All'
                                    ? 'All'
                                    : '${emojiForNoticeType(tg)} $tg'))
                            .toList(),
                      ),
                    ),
                  ),
                ),
              if (notices.isEmpty)
                const SliverToBoxAdapter(
                    child: PulseEmptyState(
                        illo: PulseIllo.emptyInbox, title: 'No notices yet')),
              if (urgent.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  sliver: SliverToBoxAdapter(
                    child: Text('🚨 Urgent',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: t.danger)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  sliver: SliverList.separated(
                    itemCount: urgent.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => NoticeCard(
                      notice: urgent[i] as Map,
                      urgent: true,
                      acknowledged: _acknowledged
                          .contains('${(urgent[i] as Map)['_id']}'),
                      onAcknowledge: () {
                        Haptics.success();
                        setState(() =>
                            _acknowledged.add('${(urgent[i] as Map)['_id']}'));
                      },
                    ),
                  ),
                ),
              ],
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                sliver: SliverList.separated(
                  itemCount: rest.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => NoticeCard(
                      notice: rest[i] as Map,
                      urgent: false,
                      acknowledged: false,
                      onAcknowledge: null),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class NoticeCard extends StatelessWidget {
  final Map notice;
  final bool urgent;
  final bool acknowledged;
  final VoidCallback? onAcknowledge;
  const NoticeCard(
      {super.key,
      required this.notice,
      required this.urgent,
      required this.acknowledged,
      required this.onAcknowledge});
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final tag = '${notice['tag'] ?? notice['type'] ?? 'General'}';
    final pinned = notice['pinned'] == true;
    final createdAt = DateTime.tryParse('${notice['createdAt']}');
    final expiresAt = DateTime.tryParse('${notice['expiresAt']}');
    return PulseCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emojiForNoticeType(tag),
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              if (pinned)
                Icon(Icons.push_pin_rounded, size: 13, color: t.brand),
              const Spacer(),
              if (urgent)
                const PulsePill(
                    label: 'Urgent', tone: PulseTone.overdue, small: true),
            ],
          ),
          const SizedBox(height: 8),
          Text('${notice['title'] ?? ''}',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14.5, color: t.fg1)),
          const SizedBox(height: 4),
          Text('${notice['description'] ?? notice['body'] ?? ''}',
              style: TextStyle(fontSize: 12.5, color: t.fg3, height: 1.45)),
          const SizedBox(height: 8),
          Text(
            '— ${notice['createdByName'] ?? 'Society'}${createdAt != null ? ' · ${createdAt.day}/${createdAt.month}/${createdAt.year}' : ''}'
            '${expiresAt != null ? ' · till ${expiresAt.day}/${expiresAt.month}' : ''}',
            style: TextStyle(fontSize: 11, color: t.fg4),
          ),
          if (urgent) ...[
            const SizedBox(height: 10),
            if (acknowledged)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: t.successSoft,
                    borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
                child: Text('✓ Acknowledged',
                    style: TextStyle(
                        color: t.success,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5)),
              )
            else
              PulseButton(
                  label: '✋ Acknowledge this notice',
                  full: true,
                  size: PulseBtnSize.sm,
                  variant: PulseBtnVariant.secondary,
                  onTap: onAcknowledge),
          ],
        ],
      ),
    );
  }
}
