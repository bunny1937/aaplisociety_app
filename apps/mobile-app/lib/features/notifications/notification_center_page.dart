import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/socket/socket_bus.dart';

/// Notification history: GET /notifications + mark-read / mark-all-read.
/// Plain Material widgets, matching the precedent set by
/// features/tenant/add_tenant_page.dart and rent_payment_page.dart — visual
/// polish to the "Pulse" design system is a separate follow-up pass.
class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({super.key});
  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  List _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    SocketBus.notificationEvents.addListener(_onEvent);
  }

  @override
  void dispose() {
    SocketBus.notificationEvents.removeListener(_onEvent);
    super.dispose();
  }

  void _onEvent() => _load();

  Future<void> _load() async {
    final dio = context.read<Dio>();
    try {
      final res = await dio.get('/notifications');
      if (mounted) setState(() { _items = res.data as List; _loading = false; _error = null; });
    } on DioException catch (err) {
      if (mounted) setState(() { _loading = false; _error = err.message; });
    }
  }

  Future<void> _markRead(String id) async {
    final dio = context.read<Dio>();
    await dio.post('/notifications/$id/mark-read');
    await _load();
  }

  Future<void> _markAllRead() async {
    final dio = context.read<Dio>();
    await dio.post('/notifications/mark-all-read');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _items.where((n) => (n as Map)['read'] != true).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unreadCount > 0)
            TextButton(onPressed: _markAllRead, child: const Text('Mark all read')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(child: Text('No notifications yet', style: TextStyle(color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final n = _items[i] as Map;
                          final read = n['read'] == true;
                          final createdAt = DateTime.tryParse('${n['createdAt']}');
                          return Card(
                            color: read ? null : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                            child: ListTile(
                              leading: Icon(read ? Icons.notifications_none : Icons.notifications_active, color: read ? Colors.grey : Theme.of(context).colorScheme.primary),
                              title: Text('${n['title'] ?? ''}', style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.w700)),
                              subtitle: Text('${n['message'] ?? ''}${createdAt != null ? '\n${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}' : ''}'),
                              isThreeLine: createdAt != null,
                              trailing: read ? null : IconButton(icon: const Icon(Icons.check_circle_outline), onPressed: () => _markRead('${n['_id']}')),
                              onTap: read ? null : () => _markRead('${n['_id']}'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
