import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../member/pulse/pulse.dart';
import 'data/amenities_api.dart';
import 'widgets/amenity_bits.dart';

class AmenityEventsPage extends StatefulWidget {
  const AmenityEventsPage({super.key});

  @override
  State<AmenityEventsPage> createState() => _AmenityEventsPageState();
}

class _AmenityEventsPageState extends State<AmenityEventsPage> {
  late Future<List<AmenityEventSummary>> _future;
  bool _mineOnly = false;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = fetchEvents(context.read<Dio>(), mineOnly: _mineOnly);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? tokensOf(context).danger : null,
    ));
  }

  static String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return 'Something went wrong. Please try again.';
  }

  Future<void> _act(
    AmenityEventSummary event,
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _busyId = event.id);
    try {
      await action();
      _snack(successMessage);
      setState(_load);
    } on DioException catch (e) {
      _snack(_message(e), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Asks for a guest count only when the event actually permits guests.
  Future<int?> _askGuests(AmenityEventSummary event) async {
    if (!event.guestsAllowed) return 0;
    int count = 0;
    return showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) {
        final t = tokensOf(sheetContext);
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bringing guests?',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: t.fg1)),
                const SizedBox(height: 6),
                Text(
                  'Guests count towards the capacity, so please only reserve '
                  'seats you will use.',
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: t.fg4),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: count == 0
                          ? null
                          : () => setSheetState(() => count--),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text('$count',
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: count >= 10
                          ? null
                          : () => setSheetState(() => count++),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, count),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);

    return Scaffold(
      backgroundColor: t.canvas,
      appBar: AppBar(
        backgroundColor: t.canvas,
        elevation: 0,
        title: const Text('Events'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AmenityEventSummary>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final events = snap.data ?? const <AmenityEventSummary>[];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
              children: [
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All events'),
                      selected: !_mineOnly,
                      onSelected: (_) => setState(() {
                        _mineOnly = false;
                        _load();
                      }),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text("I'm going"),
                      selected: _mineOnly,
                      onSelected: (_) => setState(() {
                        _mineOnly = true;
                        _load();
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (snap.hasError)
                  const AmenityEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not load events',
                    body: 'Pull down to try again.',
                  )
                else if (events.isEmpty)
                  AmenityEmptyState(
                    icon: Icons.celebration_outlined,
                    title: _mineOnly
                        ? 'Nothing booked'
                        : 'No events scheduled',
                    body: _mineOnly
                        ? 'Events you register for appear here.'
                        : 'When the committee publishes an event it shows up here.',
                  )
                else
                  ...events.map((e) => _EventCard(
                        event: e,
                        busy: _busyId == e.id,
                        onRegister: () async {
                          // Guard here, not just inside _act: _askGuests awaits
                          // a bottom sheet, and a second tap landing in that gap
                          // would slip through before _act ever sets _busyId.
                          if (_busyId == e.id) return;
                          setState(() => _busyId = e.id);
                          final guests = await _askGuests(e);
                          if (guests == null) {
                            if (mounted) setState(() => _busyId = null);
                            return;
                          }
                          await _act(
                            e,
                            () => registerForEvent(context.read<Dio>(), e.id,
                                guestCount: guests),
                            'You are registered',
                          );
                        },
                        onCancel: () => _act(
                          e,
                          () => cancelRegistration(context.read<Dio>(), e.id),
                          'Registration cancelled — your seat has been released',
                        ),
                        onJoinWaitlist: () async {
                          if (_busyId == e.id) return;
                          setState(() => _busyId = e.id);
                          final guests = await _askGuests(e);
                          if (guests == null) {
                            if (mounted) setState(() => _busyId = null);
                            return;
                          }
                          await _act(
                            e,
                            () => joinWaitlist(context.read<Dio>(), e.id,
                                guestCount: guests),
                            'Added to the waitlist — you will be notified if a seat opens',
                          );
                        },
                        onLeaveWaitlist: () => _act(
                          e,
                          () => leaveWaitlist(context.read<Dio>(), e.id),
                          'Left the waitlist',
                        ),
                      )),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final AmenityEventSummary event;
  final bool busy;
  final VoidCallback onRegister;
  final VoidCallback onCancel;
  final VoidCallback onJoinWaitlist;
  final VoidCallback onLeaveWaitlist;

  const _EventCard({
    required this.event,
    required this.busy,
    required this.onRegister,
    required this.onCancel,
    required this.onJoinWaitlist,
    required this.onLeaveWaitlist,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final cancelled = event.status == 'CANCELLED';
    final seatsLeft = event.capacity == null
        ? null
        : (event.capacity! - event.registeredCount).clamp(0, event.capacity!);

    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(PulseTokens.radius),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(event.title,
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: cancelled ? t.fg4 : t.fg1,
                        decoration:
                            cancelled ? TextDecoration.lineThrough : null)),
              ),
              if (event.amRegistered)
                _Chip(text: 'Going', bg: t.successSoft, fg: t.success)
              else if (event.amWaiting)
                _Chip(
                    text: event.myWaitlistPosition != null
                        ? 'Waitlist #${event.myWaitlistPosition}'
                        : 'Waitlisted',
                    bg: t.warningSoft,
                    fg: t.warning)
              else if (cancelled)
                _Chip(text: 'Cancelled', bg: t.dangerSoft, fg: t.danger),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            [
              if (event.startAt != null) _when(event.startAt!),
              if (event.venue != null && event.venue!.isNotEmpty)
                event.venue!
              else if (event.amenityName.isNotEmpty)
                event.amenityName,
            ].join(' · '),
            style: TextStyle(fontSize: 12.5, color: t.fg4),
          ),
          if (event.description != null && event.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(event.description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.5, color: t.fg3)),
          ],
          if (event.organizerName != null &&
              event.organizerName!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Organised by ${event.organizerName}',
                style: TextStyle(fontSize: 12, color: t.fg4)),
          ],
          if (!cancelled && event.registrationRequired) ...[
            const SizedBox(height: 12),
            Text(
              seatsLeft == null
                  ? '${event.registeredCount} registered'
                  : seatsLeft > 0
                      ? '$seatsLeft of ${event.capacity} seats left'
                      : 'Full · ${event.waitlistCount} waiting',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: seatsLeft == 0 ? t.warning : t.fg3),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _action(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _action(BuildContext context) {
    if (busy) {
      return const FilledButton(onPressed: null, child: Text('Working…'));
    }
    if (event.amRegistered) {
      return OutlinedButton(
          onPressed: onCancel, child: const Text('Cancel my registration'));
    }
    if (event.amWaiting) {
      return OutlinedButton(
          onPressed: onLeaveWaitlist, child: const Text('Leave waitlist'));
    }
    if (event.isFull) {
      return event.waitlistEnabled
          ? FilledButton(
              onPressed: onJoinWaitlist, child: const Text('Join waitlist'))
          : const FilledButton(onPressed: null, child: Text('Full'));
    }
    return FilledButton(onPressed: onRegister, child: const Text('Register'));
  }

  static String _when(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final suffix = d.hour < 12 ? 'am' : 'pm';
    return '${d.day} ${months[d.month - 1]} · $hour:${d.minute.toString().padLeft(2, '0')} $suffix';
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Chip({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
}
