/// Pure helpers for resolving what to show as a person's/society's display
/// name from the `GET /auth/me` response shape — `user['member']` and
/// `user['society']` are attached server-side by
/// `apps/mobile-backend/src/modules/auth/auth.controller.ts` (Task 3 of
/// `docs/superpowers/plans/2026-07-12-member-data-ui-fill.md`).
/// `username` is a login handle (e.g. "gs_salmank_101_22"), never a real
/// person's name — always prefer the linked Member's `ownerName` when it's
/// present and non-blank.
library;

String resolveDisplayName(Map<String, dynamic> user) {
  final member = user['member'] as Map?;
  final ownerName = member?['ownerName']?.toString().trim();
  if (ownerName != null && ownerName.isNotEmpty) return ownerName;
  final username = user['username']?.toString();
  return (username != null && username.isNotEmpty) ? username : 'there';
}

String? resolveSocietyName(Map<String, dynamic> user, Map? activeProfile) {
  final society = user['society'] as Map?;
  final name = society?['name']?.toString().trim();
  if (name != null && name.isNotEmpty) return name;
  final profileName = activeProfile?['societyName']?.toString().trim();
  return (profileName != null && profileName.isNotEmpty) ? profileName : null;
}
