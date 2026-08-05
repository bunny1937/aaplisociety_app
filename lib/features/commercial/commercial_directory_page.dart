import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../core/storage/offline_cache.dart';
import '../auth/bloc/auth_bloc.dart';
import 'data/commercial_api.dart';
import 'models/business_profile.dart';
import 'models/commercial_category.dart';

/// Shops and offices inside THIS society. Read-only by design: this release
/// has no catalogs, carts, orders or payments.
///
/// Caching reuses the existing Hive OfflineCache with a key scoped by society
/// and active profile, so switching flats can never show the previous
/// society's shops.
class CommercialDirectoryPage extends StatefulWidget {
  const CommercialDirectoryPage({super.key});

  @override
  State<CommercialDirectoryPage> createState() => _CommercialDirectoryPageState();
}

class _CommercialDirectoryPageState extends State<CommercialDirectoryPage> {
  final _searchCtrl = TextEditingController();
  List<BusinessProfile> _rows = const [];
  List<CommercialCategory> _cats = const [];
  String? _categoryId;
  String? _error;
  bool _loading = true;
  bool _fromCache = false;

  String get _cacheKey {
    final auth = context.read<AuthBloc>().state;
    final claims = auth is AuthAuthed ? auth.claims : const <String, dynamic>{};
    return 'commercial:directory:${claims['societyId']}:${claims['activeProfileId'] ?? claims['memberId']}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(initial: true));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    final api = CommercialApi(context.read<Dio>());
    final key = _cacheKey;

    // Show last-known-good instantly, then refresh.
    if (initial && OfflineCache.isReady && OfflineCache.has(key)) {
      final cached = OfflineCache.read(key);
      if (cached is Map) {
        setState(() {
          _rows = BusinessProfile.listFrom(cached['businesses']);
          _cats = CommercialCategory.listFrom(cached['categories']);
          _loading = false;
          _fromCache = true;
        });
      }
    }

    try {
      final results = await Future.wait([
        api.directory(categoryId: _categoryId, search: _searchCtrl.text),
        if (_cats.isEmpty) api.categories() else Future.value(const <String, dynamic>{}),
      ]);
      final businesses = BusinessProfile.listFrom(results.first['businesses']);
      final cats = results.length > 1 && results[1].isNotEmpty
          ? CommercialCategory.listFrom(results[1]['categories'])
          : _cats;
      if (!mounted) return;
      setState(() {
        _rows = businesses;
        _cats = cats;
        _loading = false;
        _fromCache = false;
        _error = null;
      });
      // Only the unfiltered first page is cached, so an offline user always
      // sees a complete list rather than a stale filtered subset.
      if (_categoryId == null && _searchCtrl.text.isEmpty && OfflineCache.isReady) {
        OfflineCache.write(key, {
          'businesses': results.first['businesses'],
          'categories': cats.map((c) => {'id': c.id, 'name': c.name, 'slug': c.slug, 'scope': c.scope, 'isActive': c.isActive}).toList(),
        });
      }
    } on DioException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(err, 'Could not load the shop directory');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Shops & services')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            if (_fromCache)
              Container(
                width: double.infinity,
                color: theme.colorScheme.secondaryContainer,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text('Offline - showing last saved list',
                    style: theme.textTheme.bodySmall),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  hintText: 'Search shops in your society',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            _load();
                          },
                        ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ),
            if (_cats.isNotEmpty)
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _categoryId == null,
                        onSelected: (_) {
                          setState(() => _categoryId = null);
                          _load();
                        },
                      ),
                    ),
                    for (final c in _cats)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c.name),
                          selected: _categoryId == c.id,
                          onSelected: (_) {
                            setState(() => _categoryId = c.id);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(child: _body(theme)),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rows.isEmpty) {
      return _Message(icon: Icons.wifi_off_rounded, title: _error!, onRetry: _load);
    }
    if (_rows.isEmpty) {
      return const _Message(
        icon: Icons.storefront_outlined,
        title: 'No shops listed yet',
        subtitle: 'Businesses appear here once your society publishes them.',
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final b = _rows[i];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                b.tradeName.isEmpty ? '?' : b.tradeName.characters.first.toUpperCase(),
              ),
            ),
            title: Text(b.tradeName, style: theme.textTheme.titleMedium),
            subtitle: Text(
              [b.unitLabel, b.fulfillmentLabel].where((s) => s.isNotEmpty).join(' - '),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/commercial/business/${b.id}'),
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Future<void> Function()? onRetry;
  const _Message({required this.icon, required this.title, this.subtitle, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
      children: [
        Icon(icon, size: 40, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          Center(
            child: FilledButton.tonal(onPressed: () => onRetry!(), child: const Text('Try again')),
          ),
        ],
      ],
    );
  }
}
