import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/haptics.dart';
import '../member/pulse/pulse.dart';

/// The home screen's top-right bell.
///
/// It used to open the NOTICES sheet, which is a completely different feature:
/// notices are society-wide announcements, notifications are things that
/// happened to YOU (rent reminder, visitor at the gate, payment confirmed).
/// A rent reminder therefore had nowhere to surface on the home screen at all.
///
/// Tapping the bell no longer navigates. It floats a small, fast dialog with
/// the three most recent notifications and a single link into the full
/// `/notifications` page — so the common case ("what just pinged me?") costs
/// one tap and no page transition.
Future<void> showRecentNotificationsPopover(
  BuildContext context,
  Dio dio,
) {
  Haptics.light();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Recent notifications',
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, __, ___) => _RecentNotificationsDialog(dio: dio),
    transitionBuilder: (ctx, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0, -0.045), end: Offset.zero)
                  .animate(curved),
          child: ScaleTransition(
            // Grows out of the bell rather than zooming from the middle.
            alignment: Alignment.topRight,
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class _RecentNotificationsDialog extends StatefulWidget {
  const _RecentNotificationsDialog({required this.dio});
  final Dio dio;
  @override
  State<_RecentNotificationsDialog> createState() =>
      _RecentNotificationsDialogState();
}

class _RecentNotificationsDialogState
    extends State<_RecentNotificationsDialog> {
  List<Map> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.dio.get('/notifications');
      final raw = (res.data as Map)['notifications'];
      final list = (raw is List ? raw : const []).whereType<Map>().toList()
        ..sort((a, b) {
          final da = DateTime.tryParse('${a['createdAt']}');
          final db = DateTime.tryParse('${b['createdAt']}');
          if (da == null || db == null) return 0;
          return db.compareTo(da);
        });
      if (!mounted) return;
      setState(() {
        _items = list.take(3).toList();
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load notifications.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final top = MediaQuery.of(context).padding.top;
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(top: top + 58, right: 14, left: 14),
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(
                      children: [
                        Icon(Icons.notifications_active_rounded,
                            size: 16, color: t.brand),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text('Notifications',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: t.fg1)),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: t.hairline),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 26),
                      child: Center(child: PulseSpinner()),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 22, horizontal: 14),
                      child: Text(_error!,
                          style: TextStyle(fontSize: 12.5, color: t.fg4)),
                    )
                  else if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 22, horizontal: 14),
                      child: Text('Nothing new right now.',
                          style: TextStyle(fontSize: 12.5, color: t.fg4)),
                    )
                  else
                    for (var i = 0; i < _items.length; i++)
                      _RecentTile(
                        item: _items[i],
                        last: i == _items.length - 1,
                      ),
                  Divider(height: 1, thickness: 1, color: t.hairline),
                  InkWell(
                    borderRadius:
                        const BorderRadius.vertical(bottom: Radius.circular(16)),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/notifications');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('View all notifications',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: t.brand)),
                          Icon(Icons.chevron_right_rounded,
                              size: 17, color: t.brand),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.item, required this.last});
  final Map item;
  final bool last;

  String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final unread = item['read'] != true;
    final when = _ago(DateTime.tryParse('${item['createdAt']}'));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: t.hairline, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 5, right: 9),
            decoration: BoxDecoration(
              color: unread ? t.brand : Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${item['title'] ?? 'Notification'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                      color: t.fg1),
                ),
                if ('${item['message'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${item['message']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: t.fg3),
                  ),
                ],
              ],
            ),
          ),
          if (when.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(when, style: TextStyle(fontSize: 10.5, color: t.fg5)),
          ],
        ],
      ),
    );
  }
}
