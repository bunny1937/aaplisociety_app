import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../member/pulse/pulse.dart';
import 'data/amenities_api.dart';
import 'widgets/amenity_bits.dart';

/// Personal incident report history. A resident sees only what they reported —
/// the society's full queue (with everyone else's complaints) is an admin
/// surface, never exposed here.
class MyIncidentsPage extends StatefulWidget {
  const MyIncidentsPage({super.key});

  @override
  State<MyIncidentsPage> createState() => _MyIncidentsPageState();
}

class _MyIncidentsPageState extends State<MyIncidentsPage> {
  late Future<List<IncidentRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchMyIncidents(context.read<Dio>());
  }

  Future<void> _refresh() async {
    final next = fetchMyIncidents(context.read<Dio>());
    // Block body, not `() => _future = next`: an arrow body would return the
    // assignment's value (a Future), which setState() rejects.
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
        title: const Text('My reports'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<IncidentRecord>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: const [
                AmenityEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load your reports',
                  body: 'Pull down to try again.',
                ),
              ]);
            }
            final rows = snap.data ?? const <IncidentRecord>[];
            if (rows.isEmpty) {
              return ListView(children: const [
                AmenityEmptyState(
                  icon: Icons.report_gmailerrorred_outlined,
                  title: 'No reports yet',
                  body:
                      'When you report a problem with an amenity, it shows up here so you can track it.',
                ),
              ]);
            }

            final open = rows.where((r) => !_isClosed(r.status)).toList();
            final closed = rows.where((r) => _isClosed(r.status)).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
              children: [
                if (open.isNotEmpty) ...[
                  _Heading('Open'),
                  ...open.map((r) => _Row(record: r)),
                  const SizedBox(height: 20),
                ],
                if (closed.isNotEmpty) ...[
                  _Heading('Resolved'),
                  ...closed.map((r) => _Row(record: r)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static bool _isClosed(String status) =>
      status == 'RESOLVED' || status == 'CLOSED' || status == 'REJECTED';
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: t.fg4)),
    );
  }
}

class _Row extends StatelessWidget {
  final IncidentRecord record;
  const _Row({required this.record});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final closed = record.status == 'RESOLVED' ||
        record.status == 'CLOSED' ||
        record.status == 'REJECTED';

    late Color statusFg;
    late Color statusBg;
    if (record.status == 'REJECTED') {
      statusFg = t.danger;
      statusBg = t.dangerSoft;
    } else if (closed) {
      statusFg = t.success;
      statusBg = t.successSoft;
    } else {
      statusFg = t.warning;
      statusBg = t.warningSoft;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: t.fg1)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        record.amenityName,
                        record.incidentType,
                        if (record.createdAt != null) _stamp(record.createdAt!),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: TextStyle(fontSize: 12, color: t.fg4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(record.status),
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: statusFg),
                ),
              ),
            ],
          ),
          if (record.resolutionNotes != null &&
              record.resolutionNotes!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(record.resolutionNotes!,
                style: TextStyle(fontSize: 12.5, height: 1.4, color: t.fg3)),
          ],
        ],
      ),
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'RESOLVED':
        return 'Resolved';
      case 'CLOSED':
        return 'Closed';
      case 'REJECTED':
        return 'Rejected';
      case 'ASSIGNED':
        return 'Assigned';
      case 'IN_PROGRESS':
        return 'In progress';
      default:
        return 'Reported';
    }
  }

  static String _stamp(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}
