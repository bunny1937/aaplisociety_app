import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../member/pulse/pulse.dart';
import 'data/amenities_api.dart';
import 'widgets/amenity_bits.dart';

const _kindHeadings = {
  'RULE': 'Rules',
  'DO': 'Please do',
  'DONT': 'Please do not',
  'INSTRUCTION': 'Good to know',
};

class AmenityDetailPage extends StatefulWidget {
  final String amenityId;
  const AmenityDetailPage({super.key, required this.amenityId});

  @override
  State<AmenityDetailPage> createState() => _AmenityDetailPageState();
}

class _AmenityDetailPageState extends State<AmenityDetailPage> {
  late Future<AmenityDetail> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = fetchAmenityDetail(context.read<Dio>(), widget.amenityId);
  }

  void _reload() {
    setState(() {
      _future = fetchAmenityDetail(context.read<Dio>(), widget.amenityId);
    });
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? tokensOf(context).danger : null,
      ),
    );
  }

  Future<void> _checkOut(String attendanceId) async {
    setState(() => _busy = true);
    try {
      final result = await qrCheckOut(context.read<Dio>(),
          attendanceId: attendanceId);
      final mins = result.attendance.durationMins;
      _snack(mins == null
          ? 'Checked out'
          : 'Checked out after ${mins < 60 ? "$mins min" : "${(mins / 60).toStringAsFixed(1)} h"}');
      _reload();
    } on DioException catch (e) {
      _snack(_message(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return 'Something went wrong. Please try again.';
  }

  Future<void> _reportIncident(AmenityDetail detail) async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String type = 'Other';

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final t = tokensOf(sheetContext);
        return Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report a problem',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: t.fg1)),
              const SizedBox(height: 4),
              Text(
                'Goes to the committee with your name and flat attached.',
                style: TextStyle(fontSize: 12.5, color: t.fg4),
              ),
              const SizedBox(height: 16),
              StatefulBuilder(
                builder: (ctx, setSheetState) => DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    'Damage',
                    'Cleaning Issue',
                    'Equipment Failure',
                    'Safety Hazard',
                    'Rule Violation',
                    'Noise Complaint',
                    'Lost & Found',
                    'Other',
                  ]
                      .map((v) =>
                          DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => type = v ?? 'Other'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                    labelText: 'Summary',
                    hintText: 'Treadmill belt slipping'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'What happened',
                    alignLabelWithHint: true),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('Send report'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (submitted != true) return;
    if (titleCtrl.text.trim().length < 3 || bodyCtrl.text.trim().isEmpty) {
      _snack('A summary and a description are both needed', error: true);
      return;
    }

    try {
      await reportIncident(
        context.read<Dio>(),
        amenityId: widget.amenityId,
        incidentType: type,
        title: titleCtrl.text.trim(),
        description: bodyCtrl.text.trim(),
      );
      _snack('Reported — the committee has been notified');
    } on DioException catch (e) {
      _snack(_message(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);

    return Scaffold(
      backgroundColor: t.canvas,
      appBar: AppBar(backgroundColor: t.canvas, elevation: 0),
      body: FutureBuilder<AmenityDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data == null) {
            // A 404 body carries a specific "not found" reason from the
            // server; anything else (network drop, 5xx) falls back to the
            // generic message _message() already uses for action failures.
            final err = snap.error;
            final message =
                err is DioException ? _message(err) : 'Something went wrong. Please try again.';
            return AmenityEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load this amenity',
              body: message,
            );
          }

          final detail = snap.data!;
          final a = detail.amenity;
          final openSessionId = detail.openSession?['_id']?.toString();

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
            children: [
              Text(a.name,
                  style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: t.fg1)),
              const SizedBox(height: 5),
              Text(
                [
                  a.categoryName,
                  if (a.location != null && a.location!.isNotEmpty) a.location!,
                ].join(' · '),
                style: TextStyle(fontSize: 13, color: t.fg4),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: AmenityStatusPill(status: a.effective),
              ),
              const SizedBox(height: 18),

              MaintenanceBanner(
                  status: a.effective, maintenance: detail.maintenance),

              if (!a.capacity.unlimited) ...[
                _SectionCard(
                  title: 'How busy it is',
                  child: CapacityBar(capacity: a.capacity),
                ),
              ],

              if (openSessionId != null)
                _SectionCard(
                  title: 'You are checked in',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Remember to check out when you leave. Sessions left open '
                        'are closed automatically later, which makes your history '
                        'less accurate.',
                        style: TextStyle(
                            fontSize: 12.5, height: 1.45, color: t.fg3),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                              _busy ? null : () => _checkOut(openSessionId),
                          icon: const Icon(Icons.logout, size: 18),
                          label: Text(_busy ? 'Working…' : 'Check out'),
                        ),
                      ),
                    ],
                  ),
                )
              else if (a.supportsCheckIn && a.effective.isUsable)
                _SectionCard(
                  title: 'Check in',
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: a.capacity.isFull
                          ? null
                          : () async {
                              await context.push('/amenities/scan');
                              if (mounted) _reload();
                            },
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      label: Text(a.capacity.isFull
                          ? 'Full right now'
                          : 'Scan the code at the entrance'),
                    ),
                  ),
                ),

              if (a.description != null && a.description!.isNotEmpty)
                _SectionCard(
                  title: 'About',
                  child: Text(a.description!,
                      style: TextStyle(
                          fontSize: 13.5, height: 1.55, color: t.fg2)),
                ),

              if (a.openingTime != null && a.closingTime != null)
                _SectionCard(
                  title: 'Opening hours',
                  child: Text('${a.openingTime} – ${a.closingTime}',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.fg2)),
                ),

              if (detail.todaySlots.isNotEmpty)
                _SectionCard(
                  title: "Today's slots",
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SlotStrip(slots: detail.todaySlots),
                      const SizedBox(height: 9),
                      Text(
                        'Slots are not bookable — they are shown so you know how '
                        'the day is divided.',
                        style: TextStyle(fontSize: 11.5, color: t.fg4),
                      ),
                    ],
                  ),
                ),

              for (final group in detail.ruleGroups)
                _SectionCard(
                  title: _kindHeadings[group.kind] ?? group.kind,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: group.items
                        .map((text) => Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: t.fg5,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(text,
                                        style: TextStyle(
                                            fontSize: 13,
                                            height: 1.5,
                                            color: t.fg2)),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),

              if (detail.upcomingEvents.isNotEmpty)
                _SectionCard(
                  title: 'Upcoming here',
                  child: Column(
                    children: detail.upcomingEvents
                        .map((e) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(e.title,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                e.startAt == null
                                    ? ''
                                    : _when(e.startAt!),
                                style:
                                    TextStyle(fontSize: 12, color: t.fg4),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/amenities/events'),
                            ))
                        .toList(),
                  ),
                ),

              if (detail.contactName != null &&
                  detail.contactName!.isNotEmpty)
                _SectionCard(
                  title: 'Who to ask',
                  child: Text(
                    [
                      detail.contactName!,
                      if (detail.contactPhone != null &&
                          detail.contactPhone!.isNotEmpty)
                        detail.contactPhone!,
                    ].join(' · '),
                    style: TextStyle(fontSize: 13.5, color: t.fg2),
                  ),
                ),

              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _reportIncident(detail),
                icon: const Icon(Icons.report_problem_outlined, size: 18),
                label: const Text('Report a problem'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _when(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final suffix = d.hour < 12 ? 'am' : 'pm';
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} · $hour:$minute $suffix';
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(PulseTokens.radius),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: t.fg4)),
          const SizedBox(height: 11),
          child,
        ],
      ),
    );
  }
}
