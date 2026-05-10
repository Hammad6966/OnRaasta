import 'package:socket_io_client/socket_io_client.dart' as io;
import '../core/constants/api_constants.dart';

class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();

  io.Socket? _socket;

  bool get isConnected => _socket?.connected ?? false;

  /// Initialise and connect the socket with a JWT for auth handshake.
  void connect(String token) {
    if (isConnected) return;

    _socket = io.io(
      ApiConstants.socketUrl,
      <String, dynamic>{
        'transports':   ['websocket'],
        'autoConnect':  false,
        'extraHeaders': {'Authorization': 'Bearer $token'},
      },
    );

    _socket!.connect();

    _socket!.onConnect((_)    => print('[Socket] connected'));
    _socket!.onDisconnect((_) => print('[Socket] disconnected'));
    _socket!.onError((e)      => print('[Socket] error: $e'));
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  void on(String event, Function(dynamic) callback) {
    _socket?.on(event, callback);
  }

  void off(String event) {
    _socket?.off(event);
  }
}
