import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../core/constants/api_constants.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;

  void connect(String token) {
    if (_socket != null && _socket!.connected) {
      print('[Socket] Already connected');
      return;
    }

    _socket = IO.io(
      ApiConstants.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1000)
          .build(),
    );

    _socket!.onConnect((_) {
      print('[Socket] Connected: ${_socket!.id}');
    });

    _socket!.onDisconnect((_) {
      print('[Socket] Disconnected');
    });

    _socket!.onConnectError((err) {
      print('[Socket] Connection error: $err');
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  void emit(String event, dynamic data) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit(event, data);
      print('[Socket] Emitted $event: $data');
    } else {
      print('[Socket] Not connected, cannot emit $event');
    }
  }

  void on(String event, Function(dynamic) callback) {
    _socket?.on(event, callback);
    print('[Socket] Listening for $event');
  }

  void off(String event) {
    _socket?.off(event);
  }

  bool get isConnected => _socket?.connected ?? false;
}
