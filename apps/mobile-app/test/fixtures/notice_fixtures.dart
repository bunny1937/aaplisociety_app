/// Static sample payloads matching the shape `GET /notices` items take, as
/// read by `NoticesPage` (`lib/features/member/notices_page.dart`).
/// Data only — no test logic lives here.
library;

/// A single pinned notice list item.
const Map<String, dynamic> sampleNoticePinned = {
  '_id': 'notice_1',
  'tag': 'Maintenance',
  'title': 'Water supply shutdown on 10th July',
  'body': 'Water supply will be shut off from 10am to 2pm for tank cleaning.',
  'pinned': true,
};

/// A single non-pinned notice list item.
const Map<String, dynamic> sampleNoticeGeneral = {
  '_id': 'notice_2',
  'tag': 'General',
  'title': 'Society AGM scheduled',
  'body': 'The annual general meeting is scheduled for 20th July at 6pm.',
  'pinned': false,
};

/// A full `GET /notices` response body (a JSON array of notice items).
const List<Map<String, dynamic>> sampleNoticesResponse = [
  sampleNoticePinned,
  sampleNoticeGeneral,
];
