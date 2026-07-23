import 'package:firebase_remote_config/firebase_remote_config.dart';

class GateResult {
  final bool forceUpdate;
  final bool maintenance;
  const GateResult(this.forceUpdate, this.maintenance);
}

class AppGate {
  static Future<GateResult> evaluate(String currentVersion) async {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 8),
      minimumFetchInterval: const Duration(hours: 1),
    ));
    await rc
        .setDefaults({'minimum_version': '1.0.0', 'maintenance_mode': false});
    await rc.fetchAndActivate();
    final minVersion = rc.getString('minimum_version');
    final maintenance = rc.getBool('maintenance_mode');
    return GateResult(_isOlder(currentVersion, minVersion), maintenance);
  }

  static bool _isOlder(String current, String min) {
    final c = current.split('.').map(int.parse).toList();
    final m = min.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (c[i] < m[i]) return true;
      if (c[i] > m[i]) return false;
    }
    return false;
  }
}
