enum Flavor { dev, staging, prod }

class AppConfig {
  final Flavor flavor;
  final String apiBaseUrl;
  final String socketUrl;

  const AppConfig({
    required this.flavor,
    required this.apiBaseUrl,
    required this.socketUrl,
  });

  static late AppConfig current;

  // Local backend. Used only when explicitly running with FLAVOR=dev.
  static const _devApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/v1',
  );

  static const _devSocketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  // Deployed backend. This is the default for Run, APK and Play Store builds.
  static const _deployedApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://aaplisociety.vercel.app/v1',
  );

  static const _deployedSocketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'https://aaplisociety.vercel.app',
  );

  static const dev = AppConfig(
    flavor: Flavor.dev,
    apiBaseUrl: _devApiBaseUrl,
    socketUrl: _devSocketUrl,
  );

  static const staging = AppConfig(
    flavor: Flavor.staging,
    apiBaseUrl: _deployedApiBaseUrl,
    socketUrl: _deployedSocketUrl,
  );

  static const prod = AppConfig(
    flavor: Flavor.prod,
    apiBaseUrl: _deployedApiBaseUrl,
    socketUrl: _deployedSocketUrl,
  );

  static AppConfig resolve() {
    const selected = String.fromEnvironment('FLAVOR', defaultValue: 'prod');
    const isRelease = bool.fromEnvironment('dart.vm.product');
    if (isRelease && selected != 'prod') {
      throw StateError('Release builds require --dart-define=FLAVOR=prod');
    }
    if (isRelease && !_deployedApiBaseUrl.startsWith('https://')) {
      throw StateError('Production API_BASE_URL must use HTTPS');
    }
    switch (selected) {
      case 'dev':
        return dev;
      case 'staging':
        return staging;
      case 'prod':
      default:
        return prod;
    }
  }
}
