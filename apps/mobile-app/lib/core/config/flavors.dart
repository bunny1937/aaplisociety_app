enum Flavor { dev, staging, prod }

class AppConfig {
  final Flavor flavor;
  final String apiBaseUrl;
  final String socketUrl;
  const AppConfig({required this.flavor, required this.apiBaseUrl, required this.socketUrl});

  static late AppConfig current;

  // Override per run: --dart-define=API_BASE_URL=http://<lan-ip>:5001/v1 --dart-define=SOCKET_URL=http://<lan-ip>:5001
  // Physical device without a LAN IP handy: `adb reverse tcp:5001 tcp:5001` then use http://localhost:5001.
  // 10.0.2.2 default below only resolves on the Android emulator's host-loopback alias.
  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:5001/v1');
  static const _socketUrl = String.fromEnvironment('SOCKET_URL', defaultValue: 'http://10.0.2.2:5001');

  static const dev = AppConfig(flavor: Flavor.dev, apiBaseUrl: _apiBaseUrl, socketUrl: _socketUrl);
  static const staging = AppConfig(flavor: Flavor.staging, apiBaseUrl: _apiBaseUrl, socketUrl: _socketUrl);
  static const prod = AppConfig(flavor: Flavor.prod, apiBaseUrl: _apiBaseUrl, socketUrl: _socketUrl);

  static AppConfig resolve() {
    switch (const String.fromEnvironment('FLAVOR', defaultValue: 'dev')) {
      case 'prod':
        return prod;
      case 'staging':
        return staging;
      default:
        return dev;
    }
  }
}
