import 'package:flutter_test/flutter_test.dart';
import 'package:aapli_society/features/member/bills_page.dart';

void main() {
  group('billTitle', () {
    test('prefers periodLabel (the field the backend now always sends)', () {
      expect(billTitle({'periodLabel': 'May 2026', 'title': null, 'period': null}), 'May 2026');
    });

    test('falls back to title, then period, then "Bill" — never renders the string "null"', () {
      expect(billTitle({'title': 'Custom Title'}), 'Custom Title');
      expect(billTitle({'period': '2026-Q2'}), '2026-Q2');
      expect(billTitle(<String, dynamic>{}), 'Bill');
      expect(billTitle({'title': null, 'period': null}), 'Bill');
    });
  });
}
