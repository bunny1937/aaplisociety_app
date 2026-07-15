import 'package:socket_io_client/socket_io_client.dart' as sio;
import '../config/flavors.dart';

class SocketService {
  SocketService._();
  static final instance = SocketService._();

  sio.Socket? _socket;
  bool get isConnected => _socket?.connected ?? false;

  void connect(String accessToken, void Function(String event, dynamic data) onEvent) {
    if (_socket != null) dispose();
    _socket = sio.io(AppConfig.current.socketUrl, sio.OptionBuilder()
        .setTransports(['websocket'])
        .setPath('/socket')
        .setAuth({'token': accessToken})
        .setReconnectionAttempts(5)
        .disableAutoConnect()
        .build());
    for (final e in ['VISITOR_ENTERED', 'VISITOR_EXITED', 'VISITOR_APPROVAL', 'VISITOR_DECISION', 'VISITOR_SOS', 'BILL_GENERATED', 'PAYMENT_RECEIVED', 'NOTICE_POSTED']) {
      _socket!.on(e, (data) => onEvent(e, data));
    }
    _socket!.connect();
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}
