import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/haptics.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ledger_timeline.dart';
import '../auth/bloc/auth_bloc.dart';
import '../member/pulse/pulse.dart';

/// Port of ui_kits/member-v2 `ScreensNoticesComplaints.jsx` `ComplaintsScreen`
/// + `NewComplaintSheet`. Real category list (6: maintenance/water/parking/
/// security/noise/other) and real status vocabulary (Open/In progress/
/// Resolved/Rejected) used instead of the design fixture's 10 categories /
/// 5-value status enum — see MEMBER_V2_GAPS.md. Admin/secretary inline
/// status-management branch kept (no design equivalent, per user decision).
class ComplaintsPage extends StatefulWidget {
  const ComplaintsPage({super.key});
  @override
  State<ComplaintsPage> createState() => _ComplaintsPageState();
}

class _ComplaintsPageState extends State<ComplaintsPage> {
  final _listKey = GlobalKey<AsyncViewState<List>>();
  String _filter = 'All';
  static const _categories = [
    'maintenance',
    'water',
    'parking',
    'security',
    'noise',
    'other'
  ];
  static const _categoryEmoji = {
    'maintenance': '🔧',
    'water': '💧',
    'parking': '🚗',
    'security': '🔒',
    'noise': '🔊',
    'other': '📋',
  };
  PulseTone _statusTone(String s) => switch (s) {
        'Resolved' => PulseTone.resolved,
        'Rejected' => PulseTone.rejected,
        'In progress' => PulseTone.inProgress,
        _ => PulseTone.open,
      };
  String _fmt(dynamic iso) {
    final d = DateTime.tryParse('$iso');
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openNew(BuildContext context) async {
    final desc = TextEditingController();
    var cat = 'maintenance';
    var submitting = false;
    String? error;
    await showPulseSheet(
      context,
      title: 'New Complaint',
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final t = sheetCtx.pulse;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Raised anonymously, reviewed by admin',
                  style: TextStyle(fontSize: 12, color: t.fg4)),
              const SizedBox(height: 16),
              Text('Category',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: t.fg2)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories.map((c) {
                  final sel = c == cat;
                  return GestureDetector(
                    onTap: () => setSheet(() => cat = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? t.brandSoft : t.surface,
                        border: Border.all(
                            color: sel ? t.brand : t.border,
                            width: sel ? 1.6 : 1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                          '${_categoryEmoji[c]} ${c[0].toUpperCase()}${c.substring(1)}',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: sel ? t.brand : t.fg3)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text('Describe the issue',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: t.fg2)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                    color: t.surface,
                    border: Border.all(color: t.border),
                    borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
                child: TextField(
                  controller: desc,
                  maxLines: 3,
                  style: TextStyle(color: t.fg1, fontSize: 13.5),
                  decoration: const InputDecoration(
                      hintText: 'What happened?',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12)),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: TextStyle(color: t.danger, fontSize: 12.5)),
              ],
              const SizedBox(height: 18),
              PulseButton(
                label: 'Submit complaint',
                icon: Icons.send_rounded,
                full: true,
                loading: submitting,
                onTap: () async {
                  if (desc.text.trim().length < 30) {
                    Haptics.heavy();
                    setSheet(() => error =
                        'Please describe the issue in at least 30 characters');
                    return;
                  }
                  setSheet(() {
                    submitting = true;
                    error = null;
                  });
                  try {
                    await sheetCtx.read<Dio>().post('/complaints', data: {
                      'category': cat,
                      'title': desc.text.trim().length > 120
                          ? desc.text.trim().substring(0, 120)
                          : desc.text.trim(),
                      'description': desc.text.trim(),
                    });
                    Haptics.success();
                    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    await _listKey.currentState?.reload();
                    if (context.mounted) {
                      showPulseToast(context, 'Complaint raised',
                          kind: PulseToastKind.success);
                    }
                  } on DioException catch (err) {
                    Haptics.heavy();
                    setSheet(() {
                      submitting = false;
                      error = apiErrorMessage(err, 'Could not raise complaint');
                    });
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _detail(BuildContext context, Map it, bool canManage) async {
    Haptics.light();
    const statuses = ['Open', 'In progress', 'Resolved', 'Rejected'];
    var status = '${it['status']}';
    final note =
        TextEditingController(text: it['resolutionNote']?.toString() ?? '');
    var submitting = false;
    String? error;
    await showPulseSheet(
      context,
      title: '${it['title']}',
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final t = sheetCtx.pulse;
          final stages = [
            TimelineStage(
                label: 'Raised',
                timestamp: _fmt(it['createdAt']),
                color: t.brand),
            if (status != 'Open')
              TimelineStage(
                  label: status,
                  timestamp: _fmt(it['updatedAt']),
                  note: it['resolutionNote']?.toString(),
                  color: t.fg2),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                      '${_categoryEmoji[it['category']] ?? '📋'} ${it['category']}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: t.fg4)),
                  const Spacer(),
                  PulsePill(label: status, tone: _statusTone(status)),
                ],
              ),
              const SizedBox(height: 6),
              Text('${it['description'] ?? ''}',
                  style: TextStyle(fontSize: 13, color: t.fg3, height: 1.4)),
              const SizedBox(height: 18),
              LedgerTimeline(stages: stages),
              if (canManage) ...[
                const SizedBox(height: 6),
                Text('Update status',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.fg1)),
                const SizedBox(height: 10),
                PulseSegmented<String>(
                  value: status,
                  onChanged: (v) => setSheet(() => status = v),
                  options: statuses
                      .map((s) => PulseSegmentedOption(value: s, label: s))
                      .toList(),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                      color: t.surface,
                      border: Border.all(color: t.border),
                      borderRadius:
                          BorderRadius.circular(PulseTokens.radiusSm)),
                  child: TextField(
                    controller: note,
                    maxLines: 2,
                    style: TextStyle(color: t.fg1, fontSize: 13),
                    decoration: const InputDecoration(
                        hintText: 'Resolution note (optional)',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(12)),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: TextStyle(color: t.danger, fontSize: 12.5)),
                ],
                const SizedBox(height: 16),
                PulseButton(
                  label: 'Update status',
                  full: true,
                  loading: submitting,
                  onTap: () async {
                    setSheet(() {
                      submitting = true;
                      error = null;
                    });
                    try {
                      await sheetCtx
                          .read<Dio>()
                          .patch('/complaints/${it['_id']}/status', data: {
                        'status': status,
                        'resolutionNote': note.text.trim()
                      });
                      Haptics.success();
                      if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                      await _listKey.currentState?.reload();
                    } on DioException catch (err) {
                      Haptics.heavy();
                      setSheet(() {
                        submitting = false;
                        error = apiErrorMessage(err);
                      });
                    }
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final dio = context.read<Dio>();
    final auth = context.watch<AuthBloc>().state;
    final role = auth is AuthAuthed ? auth.claims['role']?.toString() : null;
    final canManage = role == 'Admin' || role == 'Secretary';
    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: PulseTopBar(
                title: 'Complaints',
                subtitle: canManage
                    ? 'All complaints'
                    : 'Raised anonymously, reviewed by admin',
                trailing: [
                  if (!canManage)
                    PulseButton(
                        label: '+ New',
                        size: PulseBtnSize.sm,
                        onTap: () => _openNew(context)),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: PulseSegmented<String>(
                    value: _filter,
                    onChanged: (v) => setState(() => _filter = v),
                    options: const [
                      PulseSegmentedOption(value: 'All', label: 'All'),
                      PulseSegmentedOption(value: 'Open', label: 'Open'),
                      PulseSegmentedOption(
                          value: 'In progress', label: 'In progress'),
                      PulseSegmentedOption(
                          value: 'Resolved', label: 'Resolved'),
                      PulseSegmentedOption(
                          value: 'Rejected', label: 'Rejected'),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverToBoxAdapter(
                child: AsyncView<List>(
                  key: _listKey,
                  fetch: () async =>
                      (await dio.get('/complaints')).data['complaints'] as List,
                  cacheKey: '/complaints',
                  isEmpty: (l) => l.isEmpty,
                  emptyBuilder: (_) => const PulseEmptyState(
                      illo: PulseIllo.allClear, title: 'No complaints yet'),
                  builder: (context, allItems) {
                    final items = _filter == 'All'
                        ? allItems
                        : allItems
                            .where(
                                (it) => '${(it as Map)['status']}' == _filter)
                            .toList();
                    if (items.isEmpty) {
                      return PulseEmptyState(
                          illo: PulseIllo.noData,
                          title: 'No complaints in "$_filter"');
                    }
                    return Column(
                      children: items.map((raw) {
                        final it = raw as Map;
                        final status = '${it['status']}';
                        final createdAt =
                            DateTime.tryParse('${it['createdAt']}');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: PulseCard(
                            padding: const EdgeInsets.all(14),
                            onTap: () => _detail(context, it, canManage),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(_categoryEmoji[it['category']] ?? '📋',
                                        style: const TextStyle(fontSize: 16)),
                                    const SizedBox(width: 6),
                                    Text('${it['category']}',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: t.fg4)),
                                    const Spacer(),
                                    PulsePill(
                                        label: status,
                                        tone: _statusTone(status),
                                        small: true),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('${it['title'] ?? ''}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                        color: t.fg1)),
                                const SizedBox(height: 3),
                                Text('${it['description'] ?? ''}',
                                    style:
                                        TextStyle(fontSize: 12, color: t.fg3),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 8),
                                Text(
                                  '${createdAt != null ? '${createdAt.day}/${createdAt.month}/${createdAt.year}' : ''}${it['replyCount'] != null && (it['replyCount'] as num) > 0 ? ' · ${it['replyCount']} replies' : ''}',
                                  style: TextStyle(fontSize: 11, color: t.fg4),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
