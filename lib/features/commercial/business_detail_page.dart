import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_error.dart';
import 'data/commercial_api.dart';
import 'models/business_hours.dart';
import 'models/business_profile.dart';

/// Read-only business detail. Contact numbers are copyable rather than
/// dial-launched so the app adds no new platform permission or plugin.
class BusinessDetailPage extends StatefulWidget {
  final String businessId;
  const BusinessDetailPage({super.key, required this.businessId});

  @override
  State<BusinessDetailPage> createState() => _BusinessDetailPageState();
}

class _BusinessDetailPageState extends State<BusinessDetailPage> {
  BusinessProfile? _business;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final data = await CommercialApi(context.read<Dio>()).business(widget.businessId);
      if (!mounted) return;
      setState(() {
        _business = BusinessProfile.fromJson(Map.from(data['business'] as Map));
        _loading = false;
        _error = null;
      });
    } on DioException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(err, 'Could not load this business');
      });
    }
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    final b = _business;
    return Scaffold(
      appBar: AppBar(title: Text(b?.tradeName ?? 'Business')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : b == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error ?? 'Not found')))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Text(b.tradeName, style: Theme.of(context).textTheme.headlineSmall),
                    if (b.legalName != null && b.legalName!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(b.legalName!, style: Theme.of(context).textTheme.bodySmall),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (b.unitLabel.isNotEmpty) Chip(label: Text(b.unitLabel)),
                        for (final m in b.fulfillmentModes)
                          Chip(
                            label: Text(switch (m) {
                              'WalkIn' => 'Walk-in',
                              'Pickup' => 'Pickup',
                              'ShopDelivery' => 'Shop delivery',
                              _ => m,
                            }),
                          ),
                      ],
                    ),
                    if (b.description != null && b.description!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(b.description!),
                    ],
                    const SizedBox(height: 20),
                    if (b.phone != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.call_outlined),
                        title: Text(b.phone!),
                        subtitle: const Text('Phone'),
                        trailing: const Icon(Icons.copy_rounded, size: 18),
                        onTap: () => _copy('Phone number', b.phone!),
                      ),
                    if (b.whatsapp != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.chat_outlined),
                        title: Text(b.whatsapp!),
                        subtitle: const Text('WhatsApp'),
                        trailing: const Icon(Icons.copy_rounded, size: 18),
                        onTap: () => _copy('WhatsApp number', b.whatsapp!),
                      ),
                    if (b.email != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.mail_outline_rounded),
                        title: Text(b.email!),
                        subtitle: const Text('Email'),
                        trailing: const Icon(Icons.copy_rounded, size: 18),
                        onTap: () => _copy('Email', b.email!),
                      ),
                    if (b.businessHours != null) ...[
                      const Divider(height: 32),
                      Text('Opening hours', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (var day = 0; day < 7; day++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(BusinessHours.labelForDay(day)),
                              Text(_hoursFor(b, day),
                                  style: Theme.of(context).textTheme.bodyMedium),
                            ],
                          ),
                        ),
                    ],
                    if (b.gstin != null) ...[
                      const Divider(height: 32),
                      Text('GSTIN: ${b.gstin}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (b.licenseNumber != null)
                      Text('Licence: ${b.licenseNumber}',
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
    );
  }

  String _hoursFor(BusinessProfile b, int day) {
    final d = b.businessHours?.forDay(day);
    if (d == null || d.isClosed || d.intervals.isEmpty) return 'Closed';
    return d.intervals.map((i) => '${i.opensAt} - ${i.closesAt}').join(', ');
  }
}
