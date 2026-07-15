/// Static sample payloads matching the shape `GET /bills` items take, as
/// read by `BillsPage` (`lib/features/member/bills_page.dart`).
/// Data only — no test logic lives here.
library;

/// A single fully-paid bill list item.
const Map<String, dynamic> sampleBillPaid = {
  '_id': 'bill_1',
  'periodLabel': 'June 2026',
  'title': 'Maintenance - June 2026',
  'period': '2026-06',
  'status': 'Paid',
  'amount': 3500,
  'amountPaid': 3500,
  'dueDate': '2026-06-10T00:00:00.000Z',
};

/// A single unpaid bill list item.
const Map<String, dynamic> sampleBillDue = {
  '_id': 'bill_2',
  'periodLabel': 'July 2026',
  'title': 'Maintenance - July 2026',
  'period': '2026-07',
  'status': 'Due',
  'amount': 3500,
  'amountPaid': 0,
  'dueDate': '2026-07-10T00:00:00.000Z',
};

/// A full `GET /bills` response body (a JSON array of bill items).
const List<Map<String, dynamic>> sampleBillsResponse = [
  sampleBillPaid,
  sampleBillDue,
];
