import 'business_hours.dart';

/// A business listing. Deliberately carries no billing, balance, receipt or
/// owner-identity data: those already live in the existing member/billing
/// screens and are not duplicated here.
class BusinessProfile {
  final String id;
  final String tradeName;
  final String? legalName;
  final String? categoryId;
  final String? description;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? gstin;
  final String? licenseNumber;
  final String? logoKey;
  final String? coverKey;
  final int mediaVersion;
  final List<String> fulfillmentModes;
  final String? visibilityStatus;
  final String? updatedAt;
  final BusinessHours? businessHours;
  final String? wing;
  final String? flatNo;
  final String? flatType;

  const BusinessProfile({
    required this.id,
    required this.tradeName,
    this.legalName,
    this.categoryId,
    this.description,
    this.phone,
    this.whatsapp,
    this.email,
    this.gstin,
    this.licenseNumber,
    this.logoKey,
    this.coverKey,
    this.mediaVersion = 0,
    this.fulfillmentModes = const [],
    this.visibilityStatus,
    this.updatedAt,
    this.businessHours,
    this.wing,
    this.flatNo,
    this.flatType,
  });

  static String? _s(dynamic v) => v == null ? null : '$v';

  factory BusinessProfile.fromJson(Map json) {
    final unit = json['unit'] as Map?;
    return BusinessProfile(
      id: '${json['id'] ?? ''}',
      tradeName: '${json['tradeName'] ?? ''}',
      legalName: _s(json['legalName']),
      categoryId: _s(json['categoryId']),
      description: _s(json['description']),
      phone: _s(json['phone']),
      whatsapp: _s(json['whatsapp']),
      email: _s(json['email']),
      gstin: _s(json['gstin']),
      licenseNumber: _s(json['licenseNumber']),
      logoKey: _s(json['logoKey']),
      coverKey: _s(json['coverKey']),
      mediaVersion: (json['mediaVersion'] as num?)?.toInt() ?? 0,
      fulfillmentModes:
          ((json['fulfillmentModes'] as List?) ?? const []).map((e) => '$e').toList(),
      visibilityStatus: _s(json['visibilityStatus']),
      updatedAt: _s(json['updatedAt']),
      businessHours: json['businessHours'] == null
          ? null
          : BusinessHours.fromJson(Map.from(json['businessHours'] as Map)),
      wing: _s(unit?['wing']),
      flatNo: _s(unit?['flatNo']),
      flatType: _s(unit?['flatType']),
    );
  }

  static List<BusinessProfile> listFrom(dynamic raw) =>
      ((raw as List?) ?? const [])
          .map((e) => BusinessProfile.fromJson(Map.from(e as Map)))
          .toList();

  String get unitLabel =>
      [wing, flatNo].where((e) => e != null && e.isNotEmpty).join(' ');

  bool get isPublished => visibilityStatus == 'Published';

  String get fulfillmentLabel {
    if (fulfillmentModes.isEmpty) return '';
    return fulfillmentModes
        .map((m) => switch (m) {
              'WalkIn' => 'Walk-in',
              'Pickup' => 'Pickup',
              'ShopDelivery' => 'Shop delivery',
              _ => m,
            })
        .join(' - ');
  }
}
