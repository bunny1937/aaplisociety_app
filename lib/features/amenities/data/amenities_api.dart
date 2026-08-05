import 'package:dio/dio.dart';

/// Amenities API surface for the member app.
///
/// Mirrors the existing convention in the repo: plain top-level functions that
/// take the configured [Dio] instance, with paths relative to /v1. Nothing here
/// caches or holds state — the pages own that.

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}

class AmenityStatusView {
  final String state;
  final String label;
  final String? reason;
  final bool isUsable;
  final DateTime? nextOpenAt;
  final String? nextOpenTime;

  const AmenityStatusView({
    required this.state,
    required this.label,
    required this.isUsable,
    this.reason,
    this.nextOpenAt,
    this.nextOpenTime,
  });

  factory AmenityStatusView.fromJson(Map? j) {
    final m = j ?? const {};
    return AmenityStatusView(
      state: (m['state'] ?? 'OPEN').toString(),
      label: (m['label'] ?? 'Open').toString(),
      isUsable: m['isUsable'] == true,
      reason: m['reason']?.toString(),
      nextOpenAt: _asDate(m['nextOpenAt']),
      nextOpenTime: m['nextOpenTime']?.toString(),
    );
  }
}

class AmenityCapacity {
  final bool unlimited;
  final int? maxOccupancy;
  final int current;
  final int? remaining;
  final int usagePct;
  final String level;

  const AmenityCapacity({
    required this.unlimited,
    required this.current,
    required this.usagePct,
    required this.level,
    this.maxOccupancy,
    this.remaining,
  });

  factory AmenityCapacity.fromJson(Map? j) {
    final m = j ?? const {};
    return AmenityCapacity(
      unlimited: m['unlimited'] != false,
      maxOccupancy: m['maxOccupancy'] == null ? null : _asInt(m['maxOccupancy']),
      current: _asInt(m['current']),
      remaining: m['remaining'] == null ? null : _asInt(m['remaining']),
      usagePct: _asInt(m['usagePct']),
      level: (m['level'] ?? 'OK').toString(),
    );
  }

  bool get isFull => !unlimited && (remaining ?? 1) <= 0;
  bool get isBusy => !unlimited && level == 'WARNING';
}

class AmenitySummary {
  final String id;
  final String name;
  final String categoryName;
  final String? location;
  final String? description;
  final String status;
  final String attendanceMode;
  final AmenityStatusView effective;
  final AmenityCapacity capacity;
  final String? openingTime;
  final String? closingTime;
  final bool hasOpenSession;

  const AmenitySummary({
    required this.id,
    required this.name,
    required this.categoryName,
    required this.status,
    required this.attendanceMode,
    required this.effective,
    required this.capacity,
    required this.hasOpenSession,
    this.location,
    this.description,
    this.openingTime,
    this.closingTime,
  });

  factory AmenitySummary.fromJson(Map j) => AmenitySummary(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        categoryName: (j['categoryName'] ?? '').toString(),
        location: j['location']?.toString(),
        description: j['description']?.toString(),
        status: (j['status'] ?? 'OPEN').toString(),
        attendanceMode: (j['attendanceMode'] ?? 'NONE').toString(),
        // Server key is `effective` (app/api/v1/amenities/route.js), not
        // `effectiveStatus` - that name is only used by the admin-web API.
        effective: AmenityStatusView.fromJson(j['effective'] as Map?),
        capacity: AmenityCapacity.fromJson(j['capacity'] as Map?),
        openingTime: j['openingTime']?.toString(),
        closingTime: j['closingTime']?.toString(),
        hasOpenSession: j['hasOpenSession'] == true,
      );

  bool get supportsCheckIn =>
      attendanceMode == 'QR' || attendanceMode == 'QR_MANUAL';
}

class AmenityRuleGroup {
  final String kind;
  final List<String> items;
  const AmenityRuleGroup(this.kind, this.items);
}

class AmenityMaintenanceView {
  final String reason;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;

  const AmenityMaintenanceView({
    required this.reason,
    required this.status,
    this.startDate,
    this.endDate,
  });

  factory AmenityMaintenanceView.fromJson(Map j) => AmenityMaintenanceView(
        reason: (j['reason'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        startDate: _asDate(j['startDate']),
        endDate: _asDate(j['endDate']),
      );
}

class AmenitySlotView {
  final String startTime;
  final String endTime;
  final String? label;
  final int? capacity;

  const AmenitySlotView({
    required this.startTime,
    required this.endTime,
    this.label,
    this.capacity,
  });

  factory AmenitySlotView.fromJson(Map j) => AmenitySlotView(
        startTime: (j['startTime'] ?? '').toString(),
        endTime: (j['endTime'] ?? '').toString(),
        label: j['label']?.toString(),
        capacity: j['capacity'] == null ? null : _asInt(j['capacity']),
      );
}

class AmenityDetail {
  final AmenitySummary amenity;
  final List<AmenityRuleGroup> ruleGroups;
  final List<AmenityMaintenanceView> maintenance;
  final List<AmenitySlotView> todaySlots;
  final List<Map> weeklyHours;
  final List<AmenityEventSummary> upcomingEvents;
  final String? contactName;
  final String? contactPhone;
  final bool visitorsAllowed;
  final Map? openSession;

  const AmenityDetail({
    required this.amenity,
    required this.ruleGroups,
    required this.maintenance,
    required this.todaySlots,
    required this.weeklyHours,
    required this.upcomingEvents,
    required this.visitorsAllowed,
    this.contactName,
    this.contactPhone,
    this.openSession,
  });

  factory AmenityDetail.fromJson(Map j) {
    final a = (j['amenity'] as Map?) ?? const {};
    // Server shape (app/api/v1/amenities/[id]/route.js) is one flat string
    // array per kind, not a list of {kind, text} rows.
    final rulesObj = (j['rules'] as Map?) ?? const {};
    List<String> strings(dynamic v) =>
        ((v as List?) ?? const []).map((e) => e.toString()).where((t) => t.isNotEmpty).toList();

    final groups = <AmenityRuleGroup>[];
    for (final entry in const {
      'RULE': 'rules',
      'DO': 'dos',
      'DONT': 'donts',
      'INSTRUCTION': 'instructions',
    }.entries) {
      final items = strings(rulesObj[entry.value]);
      if (items.isNotEmpty) groups.add(AmenityRuleGroup(entry.key, items));
    }

    return AmenityDetail(
      amenity: AmenitySummary.fromJson(a),
      ruleGroups: groups,
      maintenance: ((j['maintenance'] as List?) ?? const [])
          .whereType<Map>()
          .map(AmenityMaintenanceView.fromJson)
          .toList(),
      todaySlots: ((j['todaySlots'] ?? j['slots']) as List? ?? const [])
          .whereType<Map>()
          .map(AmenitySlotView.fromJson)
          .toList(),
      // Server key is `weeklyGrid`.
      weeklyHours: ((j['weeklyGrid'] ?? j['weeklyHours'] ?? j['availability'])
              as List? ??
          const [])
          .whereType<Map>()
          .toList(),
      upcomingEvents: ((j['upcomingEvents'] as List?) ?? const [])
          .whereType<Map>()
          .map(AmenityEventSummary.fromJson)
          .toList(),
      visitorsAllowed: ((a['visitorPolicy'] as Map?)?['allowed']) == true,
      // publicAmenity() (lib/amenities/memberContext.js) sends these flat,
      // not nested under a `contactPerson` object.
      contactName: a['contactPersonName']?.toString(),
      contactPhone: a['contactPersonPhone']?.toString(),
      // Server key is `myOpenSession`.
      openSession: (j['myOpenSession'] ?? j['openSession']) as Map?,
    );
  }
}

class AmenityEventSummary {
  final String id;
  final String title;
  final String? description;
  final String amenityName;
  final String? venue;
  final String? organizerName;
  final DateTime? startAt;
  final DateTime? endAt;
  final int? capacity;
  final int registeredCount;
  final int waitlistCount;
  final bool registrationRequired;
  final bool guestsAllowed;
  final bool waitlistEnabled;
  final String status;
  final String? myStatus; // CONFIRMED | WAITING | null
  final int? myWaitlistPosition;

  const AmenityEventSummary({
    required this.id,
    required this.title,
    required this.amenityName,
    required this.registeredCount,
    required this.waitlistCount,
    required this.registrationRequired,
    required this.guestsAllowed,
    required this.waitlistEnabled,
    required this.status,
    this.description,
    this.venue,
    this.organizerName,
    this.startAt,
    this.endAt,
    this.capacity,
    this.myStatus,
    this.myWaitlistPosition,
  });

  factory AmenityEventSummary.fromJson(Map j) {
    // Server (app/api/v1/amenities/events/route.js) nests the resident's own
    // state under `my: {registered, registrationStatus, waitlisted,
    // waitlistPosition}` rather than flat myStatus/myWaitlistPosition keys.
    final my = (j['my'] as Map?) ?? const {};
    final String? myStatus = my['registered'] == true
        ? 'CONFIRMED'
        : (my['waitlisted'] == true ? 'WAITING' : null);

    return AmenityEventSummary(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      description: j['description']?.toString(),
      amenityName: (j['amenityName'] ?? '').toString(),
      venue: j['venue']?.toString(),
      organizerName: j['organizerName']?.toString(),
      startAt: _asDate(j['startAt']),
      endAt: _asDate(j['endAt']),
      capacity: j['capacity'] == null ? null : _asInt(j['capacity']),
      registeredCount: _asInt(j['registeredCount']),
      waitlistCount: _asInt(j['waitlistCount']),
      registrationRequired: j['registrationRequired'] != false,
      guestsAllowed: j['guestsAllowed'] == true,
      waitlistEnabled: j['waitlistEnabled'] == true,
      status: (j['status'] ?? '').toString(),
      myStatus: myStatus,
      myWaitlistPosition:
          my['waitlistPosition'] == null ? null : _asInt(my['waitlistPosition']),
    );
  }

  bool get isFull =>
      capacity != null && registeredCount >= (capacity ?? 0);
  bool get amRegistered => myStatus == 'CONFIRMED';
  bool get amWaiting => myStatus == 'WAITING';
}

class AttendanceRecord {
  final String id;
  final String amenityName;
  final DateTime? timeIn;
  final DateTime? timeOut;
  final int? durationMins;
  final String checkInMethod;
  final bool autoCheckedOut;
  final String? slotLabel;

  const AttendanceRecord({
    required this.id,
    required this.amenityName,
    required this.checkInMethod,
    required this.autoCheckedOut,
    this.timeIn,
    this.timeOut,
    this.durationMins,
    this.slotLabel,
  });

  factory AttendanceRecord.fromJson(Map j) => AttendanceRecord(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        amenityName: (j['amenityName'] ?? '').toString(),
        timeIn: _asDate(j['timeIn']),
        timeOut: _asDate(j['timeOut']),
        durationMins:
            j['durationMins'] == null ? null : _asInt(j['durationMins']),
        checkInMethod: (j['checkInMethod'] ?? '').toString(),
        autoCheckedOut: j['autoCheckedOut'] == true,
        slotLabel: j['slotLabel']?.toString(),
      );

  bool get isOpen => timeOut == null;
}

class CheckInResult {
  final AttendanceRecord attendance;
  final AmenityCapacity capacity;
  final String? slotLabel;

  const CheckInResult({
    required this.attendance,
    required this.capacity,
    this.slotLabel,
  });

  factory CheckInResult.fromJson(Map j) => CheckInResult(
        attendance:
            AttendanceRecord.fromJson((j['attendance'] as Map?) ?? const {}),
        capacity: AmenityCapacity.fromJson(j['capacity'] as Map?),
        slotLabel: (j['slot'] as Map?)?['label']?.toString(),
      );
}

// ─────────────────────────────────────────────────────────────── endpoints

Future<List<AmenitySummary>> fetchAmenities(Dio dio,
    {String? categoryId, String? search}) async {
  final res = await dio.get('/amenities', queryParameters: {
    if (categoryId != null) 'categoryId': categoryId,
    // Server (app/api/v1/amenities/route.js) reads the search term as `q`.
    if (search != null && search.isNotEmpty) 'q': search,
  });
  final list = (res.data['amenities'] as List?) ?? const [];
  return list.whereType<Map>().map(AmenitySummary.fromJson).toList();
}

Future<AmenityDetail> fetchAmenityDetail(Dio dio, String id) async {
  final res = await dio.get('/amenities/$id');
  return AmenityDetail.fromJson(res.data as Map);
}

/// Check in by scanning. [raw] is the exact payload decoded from the QR code;
/// the server owns validation, so nothing is parsed on the device.
Future<CheckInResult> qrCheckIn(Dio dio, String raw) async {
  final res = await dio.post('/amenities/qr/check-in', data: {'token': raw});
  return CheckInResult.fromJson(res.data as Map);
}

Future<CheckInResult> qrCheckOut(Dio dio, {String? raw, String? attendanceId}) async {
  final res = await dio.post('/amenities/qr/check-out', data: {
    if (raw != null) 'token': raw,
    if (attendanceId != null) 'attendanceId': attendanceId,
  });
  return CheckInResult.fromJson(res.data as Map);
}

Future<List<AttendanceRecord>> fetchMyAttendance(Dio dio,
    {int page = 1, int limit = 30}) async {
  final res = await dio.get('/amenities/my-attendance',
      queryParameters: {'page': page, 'limit': limit});
  final list = (res.data['attendance'] as List?) ?? const [];
  return list.whereType<Map>().map(AttendanceRecord.fromJson).toList();
}

Future<List<AmenityEventSummary>> fetchEvents(Dio dio,
    {String? amenityId, bool mineOnly = false}) async {
  final res = await dio.get('/amenities/events', queryParameters: {
    if (amenityId != null) 'amenityId': amenityId,
    if (mineOnly) 'mine': 'true',
  });
  final list = (res.data['events'] as List?) ?? const [];
  return list.whereType<Map>().map(AmenityEventSummary.fromJson).toList();
}

Future<AmenityEventSummary> fetchEvent(Dio dio, String id) async {
  final res = await dio.get('/amenities/events/$id');
  return AmenityEventSummary.fromJson((res.data['event'] as Map?) ?? res.data as Map);
}

Future<void> registerForEvent(Dio dio, String eventId,
    {int guestCount = 0, String? note}) async {
  await dio.post('/amenities/events/$eventId/register', data: {
    'guestCount': guestCount,
    if (note != null && note.isNotEmpty) 'note': note,
  });
}

Future<void> cancelRegistration(Dio dio, String eventId, {String? reason}) async {
  await dio.delete('/amenities/events/$eventId/register',
      data: {if (reason != null) 'reason': reason});
}

Future<void> joinWaitlist(Dio dio, String eventId, {int guestCount = 0}) async {
  await dio.post('/amenities/events/$eventId/waitlist',
      data: {'guestCount': guestCount});
}

Future<void> leaveWaitlist(Dio dio, String eventId) async {
  await dio.delete('/amenities/events/$eventId/waitlist');
}

Future<void> reportIncident(
  Dio dio, {
  required String amenityId,
  required String incidentType,
  required String title,
  required String description,
}) async {
  await dio.post('/amenities/incidents', data: {
    'amenityId': amenityId,
    'incidentType': incidentType,
    'title': title,
    'description': description,
  });
}
