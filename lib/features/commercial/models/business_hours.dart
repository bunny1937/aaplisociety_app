/// Normalized opening hours, mirroring the server shape exactly
/// (timezone + weeklySchedule + exceptions) so holidays and one-off closures
/// never need a schema or app migration.
class OpeningInterval {
  final String opensAt; // "HH:mm"
  final String closesAt;
  const OpeningInterval(this.opensAt, this.closesAt);

  factory OpeningInterval.fromJson(Map json) => OpeningInterval(
        '${json['opensAt'] ?? ''}',
        '${json['closesAt'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {'opensAt': opensAt, 'closesAt': closesAt};
}

class DaySchedule {
  final int dayOfWeek; // 0 = Sunday
  final bool isClosed;
  final List<OpeningInterval> intervals;
  const DaySchedule({
    required this.dayOfWeek,
    this.isClosed = false,
    this.intervals = const [],
  });

  factory DaySchedule.fromJson(Map json) => DaySchedule(
        dayOfWeek: (json['dayOfWeek'] as num?)?.toInt() ?? 0,
        isClosed: json['isClosed'] == true,
        intervals: ((json['intervals'] as List?) ?? const [])
            .map((e) => OpeningInterval.fromJson(Map.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'dayOfWeek': dayOfWeek,
        'isClosed': isClosed,
        'intervals': intervals.map((i) => i.toJson()).toList(),
      };
}

class BusinessHours {
  final String timezone;
  final List<DaySchedule> weeklySchedule;
  const BusinessHours({
    this.timezone = 'Asia/Kolkata',
    this.weeklySchedule = const [],
  });

  static const _labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  factory BusinessHours.fromJson(Map json) => BusinessHours(
        timezone: '${json['timezone'] ?? 'Asia/Kolkata'}',
        weeklySchedule: ((json['weeklySchedule'] as List?) ?? const [])
            .map((e) => DaySchedule.fromJson(Map.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'timezone': timezone,
        'weeklySchedule': weeklySchedule.map((d) => d.toJson()).toList(),
      };

  DaySchedule? forDay(int dayOfWeek) {
    for (final d in weeklySchedule) {
      if (d.dayOfWeek == dayOfWeek) return d;
    }
    return null;
  }

  static String labelForDay(int dayOfWeek) => _labels[dayOfWeek % 7];

  /// Display-only. Uses the device clock; the server never derives an
  /// open/closed decision from the client.
  String todaySummary([DateTime? now]) {
    final today = (now ?? DateTime.now()).weekday % 7; // Dart: Mon=1..Sun=7
    final day = forDay(today);
    if (day == null || day.isClosed || day.intervals.isEmpty) return 'Closed today';
    return day.intervals.map((i) => '${i.opensAt}-${i.closesAt}').join(', ');
  }
}
