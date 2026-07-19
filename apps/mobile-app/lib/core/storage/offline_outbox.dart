import 'dart:math';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Guard-app offline entry queue: when POST /visitors/offline-entry fails
/// (no connectivity), the entry is persisted here instead of lost, keyed by
/// a client-generated `clientRef` the server dedupes on (see mobile-backend's
/// Visitor.offlineMeta.clientRef unique partial index) — so a retried sync
/// after a flaky connection never double-logs the same physical entry.
class OfflineOutbox {
  static const _boxName = 'offline_outbox_v1';
  static Box? _box;
  static final _rand = Random.secure();

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  static bool get isReady => _box != null;

  // Device-scoped unique id: timestamp + random suffix. Doesn't need to be a
  // formal UUID — the server only requires it be unique per society, which a
  // 128-bit-entropy string plus a monotonic timestamp guarantees in practice.
  static String generateClientRef() {
    final rand = List.generate(16, (_) => _rand.nextInt(16).toRadixString(16)).join();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$rand';
  }

  /// Queues an entry for later sync. `payload` must already contain
  /// name/phone/purpose/vehicleNumber/note/clientRef/queuedAt (i.e. the exact
  /// body a live POST would have sent) — callers generate the clientRef
  /// up front via [generateClientRef] so the same id is used whether the
  /// live attempt or the queued retry is what eventually lands.
  static void enqueue(Map<String, dynamic> payload) {
    final clientRef = payload['clientRef'] as String;
    _box?.put(clientRef, payload);
  }

  static List<Map> pending() => (_box?.values ?? const []).cast<Map>().toList();

  static int get pendingCount => _box?.length ?? 0;

  /// Attempts to POST every queued entry; each success is removed from the
  /// box. A per-entry failure (still offline, or a genuine 4xx) leaves that
  /// entry queued for the next sync attempt rather than aborting the batch.
  static Future<int> sync(Dio dio) async {
    if (_box == null) return 0;
    var synced = 0;
    for (final key in _box!.keys.toList()) {
      final entry = Map<String, dynamic>.from(_box!.get(key) as Map);
      try {
        await dio.post('/visitors/offline-entry', data: entry);
        await _box!.delete(key);
        synced++;
      } on DioException catch (err) {
        // 4xx other than a connectivity failure means this entry is bad
        // (e.g. failed validation) — drop it rather than retry forever.
        final status = err.response?.statusCode;
        if (status != null && status >= 400 && status < 500 && status != 408 && status != 429) {
          await _box!.delete(key);
        }
        // Otherwise (no response / network error / 5xx) leave it queued.
      }
    }
    return synced;
  }
}
