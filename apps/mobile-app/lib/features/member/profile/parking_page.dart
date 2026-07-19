import 'package:flutter/material.dart';
import '../pulse/pulse.dart';

/// Read-only — parking slots are admin/web-managed, no edit-request workflow.
class ParkingPage extends StatelessWidget {
  final List<Map> slots;
  const ParkingPage({super.key, required this.slots});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Scaffold(
      appBar: AppBar(title: const Text('Parking')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (slots.isEmpty)
            Text('Not available yet', style: TextStyle(fontSize: 13.5, color: t.fg5, fontStyle: FontStyle.italic))
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: slots.map((s) {
                final label = '${s['slotNumber'] ?? '—'}';
                final sub = [s['type'], s['vehicleType']]
                    .where((v) => v != null && '$v'.isNotEmpty)
                    .join(' · ');
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: t.brandSoft, borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: t.brand)),
                      if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 11.5, color: t.fg4)),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
