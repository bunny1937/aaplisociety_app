import 'package:aapli_society/core/storage/token_store.dart';

/// In-memory stand-in for [TokenStore] with the same public shape
/// (`save`, `saveAccess`, `access`, `refresh`, `clear`), so tests never hit
/// the real `flutter_secure_storage` platform channels (which aren't
/// available under plain `flutter test`).
///
/// This is a real fake, not a mocktail mock — bloc/widget tests can just
/// construct it and read/assert on `accessValue`/`refreshValue` directly if
/// needed, with no stubbing required.
class FakeTokenStore implements TokenStore {
  String? accessValue;
  String? refreshValue;

  FakeTokenStore({this.accessValue, this.refreshValue});

  @override
  Future<void> save(String access, String refresh) async {
    accessValue = access;
    refreshValue = refresh;
  }

  @override
  Future<void> saveAccess(String access) async {
    accessValue = access;
  }

  @override
  Future<String?> get access async => accessValue;

  @override
  Future<String?> get refresh async => refreshValue;

  @override
  Future<void> clear() async {
    accessValue = null;
    refreshValue = null;
  }
}
