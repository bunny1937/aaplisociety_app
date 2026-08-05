import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import 'data/commercial_api.dart';
import 'models/business_profile.dart';

/// What the owner of a Shop/Office unit sees about their own listing.
///
/// Publishing, suspending and creating a profile stay with the society admin
/// on the website; the owner edits the business details only. That keeps one
/// approval path and avoids a second, weaker moderation surface.
class MyBusinessPage extends StatefulWidget {
  const MyBusinessPage({super.key});

  @override
  State<MyBusinessPage> createState() => _MyBusinessPageState();
}

class _MyBusinessPageState extends State<MyBusinessPage> {
  BusinessProfile? _profile;
  bool _canEdit = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final data = await CommercialApi(context.read<Dio>()).myBusiness();
      if (!mounted) return;
      setState(() {
        final raw = data['profile'];
        _profile = raw == null ? null : BusinessProfile.fromJson(Map.from(raw as Map));
        _canEdit = data['canEdit'] == true;
        _loading = false;
        _error = null;
      });
    } on DioException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(err, 'Could not load your business');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('My business')),
      floatingActionButton: (p != null && _canEdit)
          ? FloatingActionButton.extended(
              onPressed: () async {
                final changed = await context.push<bool>('/commercial/me/edit');
                if (changed == true) _load();
              },
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Edit'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
                    ),
                  if (p == null && _error == null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('No listing yet',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 6),
                            const Text(
                              'Your society admin creates the listing for your shop or office. '
                              'Once it exists you can keep the details up to date from here.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (p != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(p.tradeName,
                              style: Theme.of(context).textTheme.headlineSmall),
                        ),
                        Chip(
                          label: Text(p.visibilityStatus ?? 'Draft'),
                          backgroundColor: p.isPublished
                              ? Colors.green.withValues(alpha: 0.15)
                              : null,
                        ),
                      ],
                    ),
                    if (!p.isPublished)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          p.visibilityStatus == 'Suspended'
                              ? 'This listing is suspended and is hidden from residents. Contact your society office.'
                              : 'This listing is a draft. Your society admin publishes it.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 16),
                    _row('Unit', p.unitLabel),
                    _row('Phone', p.phone),
                    _row('WhatsApp', p.whatsapp),
                    _row('Email', p.email),
                    _row('GSTIN', p.gstin),
                    _row('Licence', p.licenseNumber),
                    _row('Fulfilment', p.fulfillmentLabel),
                    if (p.description != null && p.description!.isNotEmpty) ...[
                      const Divider(height: 32),
                      Text(p.description!),
                    ],
                    if (!_canEdit)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          'Self-service editing is turned off for your society. '
                          'Ask the society office to update these details.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _row(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
