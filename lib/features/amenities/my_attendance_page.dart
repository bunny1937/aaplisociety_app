import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../member/pulse/pulse.dart';
import 'data/amenities_api.dart';
import 'widgets/amenity_bits.dart';

/// Personal attendance history. Read-only by design — residents cannot edit or
/// delete their own records, because the same rows feed occupancy limits and
/// incident investigations.
class MyAttendancePage extends StatefulWidget {
  const MyAttendancePage({super.key});

  @override
  State<MyAttendancePage> createState() => _MyAttendancePageState();
}

class _MyAttendancePageState extends State<MyAttendancePage> {
  late Future<List<AttendanceRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchMyAttendance(context.read<Dio>());
  }

  Future<void> _refresh() async {
    final next = fetchMyAttendance(context.read<Dio>());
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
        title: const Text('My visits'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AttendanceRecord>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snap.data ?? const <AttendanceRecord>[];
            if (snap.hasError) {
              return ListView(children: const [
                AmenityEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load your visits',
                  body: 'Pull down to try again.',
                ),
              ]);
            }
            if (rows.isEmpty) {
              return ListView(children: const [
                AmenityEmptyState(
                  icon: Icons.how_to_reg_outlined,
                  title: 'No visits recorded',
                  body: 'Once you check in to an amenity your visits appear here.',
                ),
              ]);
            }

            final open = rows.where((r) => r.isOpen).toList();
            final closed = rows.where((r) => !r.isOpen).toList();
            final thisMonth = closed.where((r) {
              final now = DateTime.now();
              return r.timeIn != null &&
                  r.timeIn!.year == now.year &&
                  r.timeIn!.month == now.month;
            }).toList();
            final minutesThisMonth = thisMonth.fold<int>(
                0, (sum, r) => sum + (r.durationMins ?? 0));

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(PulseTokens.radius),
                    border: Border.all(color: t.hairline),
                  ),
                  child: Row(
                    children: [
                      _Metric(
                          label: 'Visits this month',
                          value: '${thisMonth.length}'),
                      _Metric(
                        label: 'Time spent',
                        value: minutesThisMonth >= 60
                            ? '${(minutesThisMonth / 60).toStringAsFixed(1)} h'
                            : '$minutesThisMonth m',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                if (open.isNotEmpty) ...[
                  _Heading('Open now'),
                  ...open.map((r) => _Row(record: r)),
                  const SizedBox(height: 8),
                  Text(
                    'An open visit means no check-out was recorded. It is closed '
                    'automatically after a while, and the entry stays in your history.',
                    style: TextStyle(fontSize: 11.5, height: 1.45, color: t.fg4),
                  ),
                  const SizedBox(height: 20),
                ],

                _Heading('History'),
                ...closed.map((r) => _Row(record: r)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w800, color: t.fg1)),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 11.5, color: t.fg4)),
        ],
      ),
    );
  }
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
  final AttendanceRecord record;
  const _Row({required this.record});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final mins = record.durationMins;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
        border: Border.all(color: t.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.amenityName,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.fg1)),
                const SizedBox(height: 3),
                Text(
                  [
                    if (record.timeIn != null) _stamp(record.timeIn!),
                    if (record.slotLabel != null) record.slotLabel!,
                    if (record.checkInMethod == 'OVERRIDE')
                      'recorded by staff',
                    if (record.autoCheckedOut) 'closed automatically',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: t.fg4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            record.isOpen
                ? 'Inside'
                : mins == null
                    ? '—'
                    : mins >= 60
                        ? '${(mins / 60).toStringAsFixed(1)} h'
                        : '$mins m',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: record.isOpen ? t.success : t.fg2),
          ),
        ],
      ),
    );
  }

  static String _stamp(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final suffix = d.hour < 12 ? 'am' : 'pm';
    return '${d.day} ${months[d.month - 1]}, $hour:${d.minute.toString().padLeft(2, '0')} $suffix';
  }
}
