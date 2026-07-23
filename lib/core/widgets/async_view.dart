import 'package:flutter/material.dart';
import '../network/api_error.dart';
import '../storage/offline_cache.dart';
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
  // When set, a successful fetch is cached under this key (Hive-backed, see
  // core/storage/offline_cache.dart) and a failed fetch falls back to the
  // last cached value instead of an error screen — the offline banner above
  // the content makes clear the data may be stale. T must be Hive-storable
  // (a raw List/Map from a JSON response, not a custom class) for this to work.
  final String? cacheKey;
  const AsyncView(
      {super.key,
      required this.fetch,
      required this.builder,
      this.isEmpty,
      this.emptyBuilder,
      this.loadingBuilder,
      this.cacheKey});
  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future;
  bool _servingFromCache = false;
  @override
  void initState() {
    super.initState();
    _future = _fetchWithCacheFallback();
  }

  Future<T> _fetchWithCacheFallback() async {
    try {
      final result = await widget.fetch();
      if (widget.cacheKey != null && OfflineCache.isReady) {
        OfflineCache.write(widget.cacheKey!, result);
      }
      _servingFromCache = false;
      return result;
    } catch (err) {
      if (widget.cacheKey != null &&
          OfflineCache.isReady &&
          OfflineCache.has(widget.cacheKey!)) {
        _servingFromCache = true;
        return OfflineCache.read(widget.cacheKey!) as T;
      }
      rethrow;
    }
  }

  Future<void> reload() async {
    final next = _fetchWithCacheFallback();
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return widget.loadingBuilder?.call(context) ??
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return _ErrorState(
              message: apiErrorMessage(snap.error!), onRetry: reload);
        }
        final data = snap.data as T;
        Widget content;
        if (widget.isEmpty?.call(data) ?? false) {
          content = widget.emptyBuilder?.call(context) ?? const _EmptyState();
        } else {
          content = RefreshIndicator(
              onRefresh: reload, child: widget.builder(context, data));
        }
        if (!_servingFromCache) return content;
        return Column(
          children: [
            const _OfflineBanner(),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 15, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Text('Offline — showing last saved data',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600)),
        ],
      ),
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
            const Icon(Icons.cloud_off_rounded,
                size: 40, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                Haptics.light();
                onRetry();
              },
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
        child: Text('Nothing here yet',
            style: TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}
