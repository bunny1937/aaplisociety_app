import 'package:flutter_test/flutter_test.dart';
import 'package:aapli_society/core/utils/time_ago.dart';

void main() {
  final now = DateTime(2026, 7, 20, 12, 0, 0);

  test('formats sub-minute durations as "just now"', () {
    expect(timeAgo(now.subtract(const Duration(seconds: 10)), now: now), 'just now');
  });

  test('formats minutes as "Xm ago"', () {
    expect(timeAgo(now.subtract(const Duration(minutes: 22)), now: now), '22m ago');
  });

  test('formats hours as "Xh ago"', () {
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
  });
}
