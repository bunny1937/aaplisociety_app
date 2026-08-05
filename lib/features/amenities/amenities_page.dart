import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../member/pulse/pulse.dart';
import 'data/amenities_api.dart';
import 'widgets/amenity_bits.dart';
import 'widgets/amenity_card.dart';

class AmenitiesPage extends StatefulWidget {
  const AmenitiesPage({super.key});

  @override
  State<AmenitiesPage> createState() => _AmenitiesPageState();
}

class _AmenitiesPageState extends State<AmenitiesPage> {
  late Future<List<AmenitySummary>> _future;
  String _category = 'All';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = fetchAmenities(context.read<Dio>());
  }

  Future<void> _refresh() async {
    final next = fetchAmenities(context.read<Dio>());
    // NOT `setState(() => _future = next)`: an arrow body returns the
    // assignment's value, which is `next` itself — a Future — and setState()
    // asserts against a callback that returns one. Block body returns void.
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);

    return Scaffold(
      backgroundColor: t.canvas,
      appBar: AppBar(
        backgroundColor: t.canvas,
        elevation: 0,
        title: const Text('Amenities'),
        actions: [
          IconButton(
            tooltip: 'My attendance',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/amenities/attendance'),
          ),
          IconButton(
            tooltip: 'Events',
            icon: const Icon(Icons.celebration_outlined),
            onPressed: () => context.push('/amenities/events'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/amenities/scan'),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan to check in'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AmenitySummary>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                // RefreshIndicator needs an always-scrollable child: content
                // this short would otherwise never overscroll, so a pull
                // gesture would do nothing.
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  AmenityEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not load amenities',
                    body: 'Pull down to try again.',
                  ),
                ],
              );
            }

            final all = snap.data ?? const <AmenitySummary>[];
            if (all.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  AmenityEmptyState(
                    icon: Icons.pool_outlined,
                    title: 'No amenities yet',
                    body: 'Your society has not published any amenities. '
                        'Once the committee adds them they appear here.',
                  ),
                ],
              );
            }

            final categories = <String>{
              'All',
              ...all.map((a) => a.categoryName).where((c) => c.isNotEmpty),
            }.toList();

            final visible = all.where((a) {
              final matchesCategory =
                  _category == 'All' || a.categoryName == _category;
              final matchesSearch = _search.isEmpty ||
                  a.name.toLowerCase().contains(_search.toLowerCase());
              return matchesCategory && matchesSearch;
            }).toList();

            // Anything the resident is currently checked into floats to the top:
            // the most likely reason to open this screen is to check out.
            visible.sort((a, b) {
              if (a.hasOpenSession != b.hasOpenSession) {
                return a.hasOpenSession ? -1 : 1;
              }
              return a.name.compareTo(b.name);
            });

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search amenities',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: t.surface,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
                      borderSide: BorderSide(color: t.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
                      borderSide: BorderSide(color: t.hairline),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories.map((c) {
                      final selected = c == _category;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: selected,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
                if (visible.isEmpty)
                  const AmenityEmptyState(
                    icon: Icons.search_off,
                    title: 'Nothing matches',
                    body: 'Try a different search or category.',
                  )
                else
                  ...visible.map(
                    (a) => AmenityCard(
                      amenity: a,
                      onTap: () async {
                        await context.push('/amenities/${a.id}');
                        if (mounted) _refresh();
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
