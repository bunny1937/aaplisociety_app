import 'package:socket_io_client/socket_io_client.dart' as sio;
import '../config/flavors.dart';

class SocketService {
  SocketService._();
  static final instance = SocketService._();
  sio.Socket? _socket;
  bool get isConnected => _socket?.connected ?? false;

  /// [onEvent] fires for every backend notification event (VISITOR_*,
  /// BILL_*, NOTICE_POSTED, COMPLAINT_*, TENANT_LEASE_EXPIRED, ...) via
  /// `onAny`, so a new NOTIFICATION_TYPES value on the backend doesn't need a
  /// matching hardcoded listener added here. [onReconnect] fires once the
  /// socket re-establishes a dropped connection — screens use it to refetch,
  /// since events that fired while disconnected are otherwise lost forever
  /// (no offline event replay/queue on the server side).
  void connect(
    String accessToken,
    void Function(String event, dynamic data) onEvent, {
    void Function()? onReconnect,
  }) {
    if (_socket != null) dispose();
    _socket = sio.io(
        AppConfig.current.socketUrl,
        sio.OptionBuilder()
            .setTransports(['websocket'])
            .setPath('/socket')
            .setAuth({'token': accessToken})
            // Reconnect indefinitely with exponential backoff (1s -> 30s cap,
            // randomized) rather than the previous hard cap of 5 attempts, after
            // which the client silently gave up reconnecting for the rest of
            // the session.
            .setReconnectionAttempts(0x7fffffff)
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(30000)
            .setRandomizationFactor(0.5)
            .disableAutoConnect()
            .build());
    _socket!.onAny((event, data) => onEvent(event, data));
    if (onReconnect != null) {
      _socket!.on('reconnect', (_) => onReconnect());
    }
    _socket!.connect();
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}
