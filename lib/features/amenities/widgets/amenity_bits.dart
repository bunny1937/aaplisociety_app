import 'package:flutter/material.dart';
import '../../member/pulse/pulse.dart';
import '../data/amenities_api.dart';

PulseTokens tokensOf(BuildContext context) =>
    Theme.of(context).extension<PulseTokens>() ?? PulseTokens.light;

/// Small status chip. Colour carries meaning here, so the label is always
/// spelled out too — "closed" should not depend on seeing red.
class AmenityStatusPill extends StatelessWidget {
  final AmenityStatusView status;
  const AmenityStatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    late Color bg;
    late Color fg;
    if (status.isUsable) {
      bg = t.successSoft;
      fg = t.success;
    } else if (status.state == 'UNDER_MAINTENANCE') {
      bg = t.warningSoft;
      fg = t.warning;
    } else {
      bg = t.dangerSoft;
      fg = t.danger;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Occupancy bar. Only rendered when the amenity actually has a cap — showing
/// "0 of unlimited" would be noise.
class CapacityBar extends StatelessWidget {
  final AmenityCapacity capacity;
  const CapacityBar({super.key, required this.capacity});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (capacity.unlimited) return const SizedBox.shrink();

    final pct = (capacity.usagePct.clamp(0, 100)) / 100;
    final colour = capacity.isFull
        ? t.danger
        : capacity.isBusy
            ? t.warning
            : t.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: t.surface3,
            valueColor: AlwaysStoppedAnimation<Color>(colour),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          capacity.isFull
              ? 'Full · ${capacity.current} of ${capacity.maxOccupancy}'
              : '${capacity.current} of ${capacity.maxOccupancy} inside',
          style: TextStyle(fontSize: 11.5, color: t.fg4),
        ),
      ],
    );
  }
}

/// The banner residents actually care about: why they cannot use something
/// today, and when that changes.
class MaintenanceBanner extends StatelessWidget {
  final AmenityStatusView status;
  final List<AmenityMaintenanceView> maintenance;
  const MaintenanceBanner({
    super.key,
    required this.status,
    this.maintenance = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (status.isUsable && maintenance.isEmpty) return const SizedBox.shrink();
    final t = tokensOf(context);

    final active = maintenance.where((m) => m.status == 'IN_PROGRESS').toList();
    final upcoming = maintenance.where((m) => m.status == 'SCHEDULED').toList();

    String body;
    if (active.isNotEmpty) {
      final m = active.first;
      body = m.reason;
      if (m.endDate != null) {
        body = '$body · expected back on ${_d(m.endDate!)}';
      }
    } else if (!status.isUsable) {
      body = status.reason ?? status.label;
      if (status.nextOpenTime != null) {
        body = '$body · opens ${status.nextOpenTime}';
      } else if (status.nextOpenAt != null) {
        body = '$body · opens ${_d(status.nextOpenAt!)}';
      }
    } else {
      final m = upcoming.first;
      body = 'Closing for ${m.reason}'
          '${m.startDate != null ? " from ${_d(m.startDate!)}" : ""}';
    }

    final warn = active.isNotEmpty || !status.isUsable;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: warn ? t.warningSoft : t.surface2,
        borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
        border: Border.all(color: t.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(warn ? Icons.build_circle_outlined : Icons.event_busy_outlined,
              size: 18, color: warn ? t.warning : t.fg3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active.isNotEmpty
                      ? 'Under maintenance'
                      : !status.isUsable
                          ? status.label
                          : 'Scheduled closure',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.fg1),
                ),
                const SizedBox(height: 3),
                Text(body,
                    style: TextStyle(
                        fontSize: 12.5, height: 1.4, color: t.fg3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _d(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

/// Row of today's slots. Present even though booking is switched off, because
/// knowing the court runs in hourly blocks changes when someone turns up.
class SlotStrip extends StatelessWidget {
  final List<AmenitySlotView> slots;
  const SlotStrip({super.key, required this.slots});

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) return const SizedBox.shrink();
    final t = tokensOf(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: slots.map((s) {
          return Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
              border: Border.all(color: t.hairline),
            ),
            child: Text('${s.startTime}–${s.endTime}',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: t.fg2)),
          );
        }).toList(),
      ),
    );
  }
}

class AmenityEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const AmenityEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(34, 60, 34, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: t.fg5),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: t.fg2)),
            const SizedBox(height: 7),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.5, color: t.fg4)),
          ],
        ),
      ),
    );
  }
}
