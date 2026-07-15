import 'package:flutter/material.dart';
import '../network/api_error.dart';
import '../theme/app_colors.dart';
import '../theme/haptics.dart';

// Shared loading / error+retry / empty scaffolding so every list screen
// (bills, notices, complaints, visitors...) behaves the same on a slow
// or dropped connection instead of silently showing nothing.
class AsyncView<T> extends StatefulWidget {
  final Future<T> Function() fetch;
  final Widget Function(BuildContext, T) builder;
  final bool Function(T)? isEmpty;
  final WidgetBuilder? emptyBuilder;
  final WidgetBuilder? loadingBuilder;
  const AsyncView({super.key, required this.fetch, required this.builder, this.isEmpty, this.emptyBuilder, this.loadingBuilder});

  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetch();
  }

  Future<void> reload() async {
    final next = widget.fetch();
    setState(() { _future = next; });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return widget.loadingBuilder?.call(context) ??
              const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return _ErrorState(message: apiErrorMessage(snap.error!), onRetry: reload);
        }
        final data = snap.data as T;
        if (widget.isEmpty?.call(data) ?? false) {
          return widget.emptyBuilder?.call(context) ?? const _EmptyState();
        }
        return RefreshIndicator(onRefresh: reload, child: widget.builder(context, data));
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () { Haptics.light(); onRetry(); },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('Nothing here yet', style: TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}
