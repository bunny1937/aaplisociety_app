import 'package:flutter_test/flutter_test.dart';
import 'package:aapli_society/features/member/pulse/member_display.dart';

void main() {
  group('resolveDisplayName', () {
    test('prefers the linked Member\'s ownerName over the login username', () {
      final user = {'username': 'gs_salmank_101_22', 'member': {'ownerName': 'Tanvi Bansal'}};
      expect(resolveDisplayName(user), 'Tanvi Bansal');
    });

    test('falls back to username when member is null or ownerName is blank', () {
      expect(resolveDisplayName({'username': 'gs_salmank_101_22', 'member': null}), 'gs_salmank_101_22');
      expect(resolveDisplayName({'username': 'gs_salmank_101_22', 'member': {'ownerName': ''}}), 'gs_salmank_101_22');
    });

    test('falls back to "there" when nothing is available', () {
      expect(resolveDisplayName(<String, dynamic>{}), 'there');
    });
  });

  group('resolveSocietyName', () {
    test('prefers the linked Society\'s name over the cached profile.societyName', () {
      final user = {'society': {'name': 'Sunrise Complex'}};
      final profile = {'societyName': 'stale-cached-name'};
      expect(resolveSocietyName(user, profile), 'Sunrise Complex');
    });

    test('falls back to profile.societyName when society is null', () {
      final user = {'society': null};
      final profile = {'societyName': 'Palm Residency'};
      expect(resolveSocietyName(user, profile), 'Palm Residency');
    });

    test('returns null when neither source has a name', () {
      expect(resolveSocietyName(<String, dynamic>{}, null), null);
    });
  });
}
