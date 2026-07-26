// material re-exports both TextStyle and FontFeature, so importing dart:ui
// here would only trigger unnecessary_import.
import 'package:flutter/material.dart';

/// SINGLE SOURCE OF TRUTH for money / date / period formatting.
///
/// Audit fix X-4: the app previously shipped three date formats (`25/7/2026`,
/// `25 Jul 2026`, `2026-07`) and two currency renderings (`Rs 20000` and
/// `₹20,000.00`) for the same concepts. Every screen must now call these
/// helpers. `tool/ui_guard.sh` fails CI if a widget under `lib/features/**`
/// hardcodes `'Rs '` or constructs its own `DateFormat`.

const List<String> _kMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _kMonthsLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Placeholder used when a value is genuinely absent. Prefer a human phrase
/// (`Not provided`, `Open ended`) at call sites that have room for one — a
/// bare em-dash was flagged across four screens in the audit.
const String kEmDash = '\u2014';

/// Indian-grouped rupee string: 2000000 -> `₹20,00,000`.
///
/// [decimals] renders paise. Money in *summaries* uses no decimals so the
/// hero number stays legible; money in *ledger/receipt rows* uses two so it
/// reconciles against the bill exactly.
String inr(num? value, {bool decimals = false}) {
  if (value == null) return kEmDash;
  final negative = value < 0;
  final abs = value.abs();
  final whole = abs.truncate();
  final paise = ((abs - whole) * 100).round();
  final digits = whole.toString();
  final buf = StringBuffer();
  // Indian grouping: last 3 digits, then pairs.
  if (digits.length <= 3) {
    buf.write(digits);
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final pairs = <String>[];
    while (rest.length > 2) {
      pairs.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) pairs.insert(0, rest);
    buf.write('${pairs.join(',')},$last3');
  }
  final body = decimals
      ? '${buf.toString()}.${paise.toString().padLeft(2, '0')}'
      : buf.toString();
  return '${negative ? '-' : ''}\u20B9$body';
}

/// Tabular figures so columns of money line up. Pair with [inr].
const TextStyle kTabularFigures =
    TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

DateTime? parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  final s = raw.toString().trim();
  if (s.isEmpty || s == 'null') return null;
  return DateTime.tryParse(s)?.toLocal();
}

/// `25 Jul 2026` — the one date format for the whole app.
String fmtDate(dynamic raw, {String fallback = kEmDash}) {
  final d = parseDate(raw);
  if (d == null) return fallback;
  return '${d.day} ${_kMonths[d.month - 1]} ${d.year}';
}

/// `25 Jul 2026, 9:18 PM` — for gate/visitor events where time matters.
String fmtDateTime(dynamic raw, {String fallback = kEmDash}) {
  final d = parseDate(raw);
  if (d == null) return fallback;
  final h24 = d.hour;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  final ampm = h24 < 12 ? 'AM' : 'PM';
  final mm = d.minute.toString().padLeft(2, '0');
  return '${fmtDate(d)}, $h:$mm $ampm';
}

/// `9:18 PM`
String fmtTime(dynamic raw, {String fallback = kEmDash}) {
  final d = parseDate(raw);
  if (d == null) return fallback;
  final h24 = d.hour;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  final ampm = h24 < 12 ? 'AM' : 'PM';
  return '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
}

/// Turns a raw billing-period id (`2026-07`) into `Jul 2026`.
///
/// Audit fix: `Bill period 2026-08`, `2026-07 — ₹20,000.00` and
/// `Payment via Excel for 2026-07` all leaked this database key into the UI.
String fmtPeriodId(dynamic raw, {String fallback = kEmDash}) {
  if (raw == null) return fallback;
  final s = raw.toString().trim();
  final m = RegExp(r'^(\d{4})-(\d{1,2})').firstMatch(s);
  if (m == null) return s.isEmpty ? fallback : s;
  final year = m.group(1)!;
  final month = int.parse(m.group(2)!);
  if (month < 1 || month > 12) return s;
  return '${_kMonths[month - 1]} $year';
}

/// `July 2026` — sticky month headers in grouped lists.
String fmtMonthHeader(dynamic raw, {String fallback = kEmDash}) {
  final d = parseDate(raw);
  if (d != null) return '${_kMonthsLong[d.month - 1]} ${d.year}';
  final s = raw?.toString() ?? '';
  final m = RegExp(r'^(\d{4})-(\d{1,2})').firstMatch(s);
  if (m == null) return fallback;
  final month = int.parse(m.group(2)!);
  if (month < 1 || month > 12) return fallback;
  return '${_kMonthsLong[month - 1]} ${m.group(1)}';
}

/// Groups a list by `YYYY-MM` key, newest first — used by payment history and
/// rent records so rows never appear as one undifferentiated stream.
Map<String, List<T>> groupByMonth<T>(
    List<T> items, dynamic Function(T) dateOf) {
  final out = <String, List<T>>{};
  for (final item in items) {
    final d = parseDate(dateOf(item));
    final key = d == null
        ? 'unknown'
        : '${d.year}-${d.month.toString().padLeft(2, '0')}';
    out.putIfAbsent(key, () => <T>[]).add(item);
  }
  final sorted = out.keys.toList()
    ..sort((a, b) {
      if (a == 'unknown') return 1;
      if (b == 'unknown') return -1;
      return b.compareTo(a);
    });
  return {for (final k in sorted) k: out[k]!};
}

/// Lease end dates are legitimately open — say so instead of printing `—`.
String fmtLeaseEnd(dynamic raw) {
  final d = parseDate(raw);
  return d == null ? 'Open ended' : fmtDate(d);
}

/// `1 Jan 2025 → Open ended`
String fmtLeaseRange(dynamic start, dynamic end) =>
    '${fmtDate(start)} \u2192 ${fmtLeaseEnd(end)}';

/// Human relative time for activity feeds (`2h ago`, `Yesterday`).
String timeAgo(dynamic raw) {
  final d = parseDate(raw);
  if (d == null) return kEmDash;
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return fmtDate(d);
}

/// Title-cases a name that arrived from the gate as `unknown` / empty.
/// Audit fix 3.11: a visitor row literally rendered the string `unknown`.
String displayName(dynamic raw, {String fallback = 'Unnamed visitor'}) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty || s.toLowerCase() == 'unknown' || s.toLowerCase() == 'null') {
    return fallback;
  }
  return s;
}

/// Masks all but the last 4 digits of an identity number.
String maskId(dynamic raw) {
  final s = raw?.toString().replaceAll(RegExp(r'\s+'), '') ?? '';
  if (s.isEmpty) return kEmDash;
  if (s.length <= 4) return s;
  return '${'\u2022' * (s.length - 4)}${s.substring(s.length - 4)}';
}
