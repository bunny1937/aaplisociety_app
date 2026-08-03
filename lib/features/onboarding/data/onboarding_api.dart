// lib/features/onboarding/data/onboarding_api.dart
//
// Thin typed client for the two onboarding endpoints. Deliberately has no
// business logic - the server decides everything, the app only renders the
// decision. That is what keeps the app and the website from drifting apart.

import 'package:dio/dio.dart';

enum LookupOutcome {
  newAccount,
  existingAccount,
  prohibited,
  linkInvalid,
  linkMismatch,
  proofRequired,
}

class FlatSummary {
  const FlatSummary({
    required this.profileId,
    required this.label,
    required this.flatNo,
    required this.societyName,
    required this.occupancyType,
    this.wing,
    this.isPrimary = false,
    this.split = false,
    this.status = 'Active',
  });

  final String profileId;
  final String label;
  final String flatNo;
  final String? wing;
  final String societyName;
  final String occupancyType;
  final bool isPrimary;
  final bool split;
  final String status;

  factory FlatSummary.fromJson(Map<String, dynamic> j) => FlatSummary(
        profileId: (j['profileId'] ?? '').toString(),
        label: (j['label'] ?? j['flatNo'] ?? '').toString(),
        flatNo: (j['flatNo'] ?? '').toString(),
        wing: j['wing'] as String?,
        societyName: (j['societyName'] ?? 'Society').toString(),
        occupancyType: (j['occupancyType'] ?? 'Owner').toString(),
        isPrimary: j['isPrimary'] == true,
        split: j['split'] == true,
        status: (j['status'] ?? 'Active').toString(),
      );
}

class LookupResult {
  const LookupResult({
    required this.outcome,
    required this.message,
    this.maskedEmail,
    this.name,
    this.username,
    this.flats = const [],
    this.splitAccount = false,
    this.totalFlats = 0,
  });

  final LookupOutcome outcome;
  final String message;
  final String? maskedEmail;
  final String? name;
  final String? username;
  final List<FlatSummary> flats;
  final bool splitAccount;
  final int totalFlats;

  static LookupOutcome _outcome(String? raw) {
    switch (raw) {
      case 'NEW_ACCOUNT':
        return LookupOutcome.newAccount;
      case 'EXISTING_ACCOUNT':
        return LookupOutcome.existingAccount;
      case 'LINK_INVALID':
        return LookupOutcome.linkInvalid;
      case 'LINK_MISMATCH':
        return LookupOutcome.linkMismatch;
      case 'PROOF_REQUIRED':
        return LookupOutcome.proofRequired;
      case 'PROHIBITED':
      default:
        return LookupOutcome.prohibited;
    }
  }

  factory LookupResult.fromJson(Map<String, dynamic> j) => LookupResult(
        outcome: _outcome(j['outcome'] as String? ?? j['error'] as String?),
        message: (j['message'] ?? j['error'] ?? 'Something went wrong.').toString(),
        maskedEmail: j['maskedEmail'] as String?,
        name: j['name'] as String?,
        username: j['username'] as String?,
        flats: ((j['flats'] as List?) ?? const [])
            .map((e) => FlatSummary.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        splitAccount: j['splitAccount'] == true,
        totalFlats: (j['totalFlats'] as num?)?.toInt() ?? 0,
      );
}

class ActivateResult {
  const ActivateResult({
    required this.success,
    required this.message,
    this.username,
    this.flats = const [],
    this.field,
  });

  final bool success;
  final String message;
  final String? username;
  final List<FlatSummary> flats;

  /// Which input the server blamed, so the UI can focus and shake that field
  /// instead of showing a generic banner.
  final String? field;
}

class OnboardingApi {
  OnboardingApi(this._dio);

  final Dio _dio;

  Future<LookupResult> lookup({
    required String email,
    String? token,
    String? societyCode,
    String? flatNo,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/onboarding/lookup',
        data: {
          'email': email.trim().toLowerCase(),
          if (token != null && token.isNotEmpty) 'token': token,
          if (societyCode != null && societyCode.isNotEmpty)
            'societyCode': societyCode.trim().toUpperCase(),
          if (flatNo != null && flatNo.isNotEmpty) 'flatNo': flatNo.trim().toUpperCase(),
        },
      );
      return LookupResult.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        return LookupResult.fromJson(Map<String, dynamic>.from(data));
      }
      return const LookupResult(
        outcome: LookupOutcome.prohibited,
        message: 'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  Future<ActivateResult> activate({
    required String token,
    required String username,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/onboarding/activate',
        data: {
          'token': token,
          'username': username.trim().toLowerCase(),
          'email': email.trim().toLowerCase(),
          'password': password,
          'confirmPassword': confirmPassword,
        },
      );
      final j = res.data ?? const <String, dynamic>{};
      return ActivateResult(
        success: j['success'] == true,
        message: (j['message'] ?? 'Your account is ready.').toString(),
        username: j['username'] as String?,
        flats: ((j['activatedFlats'] as List?) ?? const [])
            .map((e) => FlatSummary.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        return ActivateResult(
          success: false,
          message: (data['error'] ?? 'Could not complete setup.').toString(),
          field: data['field'] as String?,
        );
      }
      return const ActivateResult(
        success: false,
        message: 'Could not reach the server. Check your connection and try again.',
      );
    }
  }
}
