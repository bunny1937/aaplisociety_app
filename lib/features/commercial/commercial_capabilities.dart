/// Server-driven visibility for the commercial surfaces.
///
/// The app does NOT decide who sees the directory: `GET /auth/me` returns
/// `capabilities`, and every entry point reads it. A society that turns the
/// module off makes these false on the next session refresh, and the UI
/// disappears without an app release. An older build that has never heard of
/// these keys simply sees false everywhere and behaves exactly as before.
class CommercialCapabilities {
  final bool directory;
  final bool manageBusinessProfile;
  final String? businessProfileId;
  final String? tradeName;
  final String? visibilityStatus;

  const CommercialCapabilities({
    this.directory = false,
    this.manageBusinessProfile = false,
    this.businessProfileId,
    this.tradeName,
    this.visibilityStatus,
  });

  static const none = CommercialCapabilities();

  bool get showsAnything => directory || manageBusinessProfile;
  bool get hasProfile => businessProfileId != null;

  factory CommercialCapabilities.fromAuthUser(Map? user) {
    if (user == null) return none;
    final caps = (user['capabilities'] as Map?) ?? const {};
    final bp = user['businessProfile'] as Map?;
    return CommercialCapabilities(
      directory: caps['commercialDirectory'] == true,
      manageBusinessProfile: caps['manageBusinessProfile'] == true,
      businessProfileId: bp?['id']?.toString(),
      tradeName: bp?['tradeName']?.toString(),
      visibilityStatus: bp?['visibilityStatus']?.toString(),
    );
  }
}
