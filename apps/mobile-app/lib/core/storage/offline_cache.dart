import 'package:hive_flutter/hive_flutter.dart';

/// Generic read-through cache for list/map API responses, keyed by endpoint
/// (e.g. '/bills'). Not a general ORM — just enough to show the last known
/// good response when a fetch fails with no connectivity, instead of a bare
/// error screen. Values must be Hive-storable (List/Map of primitives),
/// which every endpoint's raw JSON response already is.
class OfflineCache {
  static const _boxName = 'offline_cache_v1';
  static Box? _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
  }

  static bool get isReady => _box != null;

  static void write(String key, dynamic data) {
    _box?.put(key, data);
  }

  static dynamic read(String key) => _box?.get(key);

  static bool has(String key) => _box?.containsKey(key) ?? false;
}
