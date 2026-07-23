/// Shared notice-type → emoji mapping (README "Iconography" table). Real
/// `Notification.type` is free text with no enum (see MEMBER_V2_GAPS.md), so
/// this matches by substring against known keywords and falls back to a
/// generic megaphone for anything unrecognized.
String emojiForNoticeType(String type) {
  final t = type.toLowerCase();
  if (t.contains('secur')) return '🔒';
  if (t.contains('water')) return '💧';
  if (t.contains('meet')) return '📅';
  if (t.contains('maint')) return '🔧';
  if (t.contains('event')) return '🎉';
  if (t.contains('bill')) return '💰';
  if (t.contains('park')) return '🚗';
  if (t.contains('elect')) return '⚡';
  return '📢';
}
