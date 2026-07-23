import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  static const _s = FlutterSecureStorage();
  static const _access = 'jwt_token';
  static const _refresh = 'refresh_token';
  Future<void> save(String access, String refresh) async {
    await _s.write(key: _access, value: access);
    await _s.write(key: _refresh, value: refresh);
  }

  // Used for the short-lived profile-select token, which has no refresh token yet.
  Future<void> saveAccess(String access) async {
    await _s.write(key: _access, value: access);
  }

  Future<String?> get access => _s.read(key: _access);
  Future<String?> get refresh => _s.read(key: _refresh);
  Future<void> clear() async {
    await _s.deleteAll();
  }
}
