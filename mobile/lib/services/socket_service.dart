import 'dart:async';
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../core/constants/api_constants.dart';
import '../models/bid_model.dart';

abstract class PresenceSocket {
  bool get isConnected;
  void connect(String token);
  Future<void> ensureConnected(String token);
  Future<Map<String, dynamic>> request(String event, Map<String, dynamic> data);
  void on(String event, Function(dynamic) callback);
  void off(String event, [Function(dynamic)? callback]);
  void disconnect();
}

class SocketFailure implements Exception {
  final String message;
  final int? status;
  const SocketFailure(this.message, [this.status]);
}

class SocketService implements PresenceSocket {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal() : _create = io.io;
  // Isolated transport construction for controlled tests; production is singleton.
  SocketService.withFactory(this._create);
  final io.Socket Function(String, Map<String, dynamic>) _create;
  io.Socket? _socket;
  String? _token;
  Future<String?> Function(bool forceRefresh)? recoverCredentials;
  int _sessionGeneration = 0;
  bool _recovering = false;
  bool _connectionWanted = false;
  int _authRecoveries = 0;
  final Map<String, Set<Function(dynamic)>> _listeners = {};
  final Set<void Function(SocketFailure)> _pending = {};
  void _notify(String event, dynamic data) {
    for (final callback
        in List<Function(dynamic)>.from(_listeners[event] ?? {})) {
      callback(data);
    }
  }

  void _cancelPending(SocketFailure error) {
    for (final cancel in List<void Function(SocketFailure)>.from(_pending)) {
      cancel(error);
    }
  }

  @override
  void connect(String token) {
    _connectionWanted = token.trim().isNotEmpty;
    if (recoverCredentials == null) {
      _connectRaw(token);
      return;
    }
    _connectCurrent(_sessionGeneration);
  }

  Future<void> _connectCurrent(int generation) async {
    try {
      final token = await recoverCredentials!(false);
      if (generation == _sessionGeneration && token != null) _connectRaw(token);
    } catch (_) {
      _cancelPending(
          const SocketFailure('Session connection unavailable. Please retry.'));
    }
  }

  void _connectRaw(String token) {
    if (token.trim().isEmpty) {
      disconnect();
      return;
    }
    if (_socket != null && _token == token) {
      if (!_socket!.connected && !_socket!.io.reconnecting) _socket!.connect();
      return;
    }
    if (_socket != null) {
      if (recoverCredentials == null) {
        disconnect();
      } else {
        _close(false);
      }
    }
    _token = token;
    final socket = _create(
        ApiConstants.socketUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': token})
            .enableForceNew()
            .disableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(5)
            .setReconnectionDelay(1000)
            .build());
    _socket = socket;
    socket.onConnect((_) => _authRecoveries = 0);
    void authenticationError(dynamic error) {
      if (!identical(_socket, socket)) return;
      final status = objectMap(objectMap(error)['data'])['status'];
      if (status == 401 || status == 403) {
        socket.io.reconnection = false;
        if (recoverCredentials != null) {
          _recover(socket);
          return;
        }
        _cancelPending(SocketFailure(
            'Socket authentication rejected. Please sign in again.',
            status as int));
        _notify('auth:error', {'status': status});
        disconnect();
      }
    }

    socket.onConnectError(authenticationError);
    // Installed socket_io_client 2.x delivers namespace CONNECT_ERROR packets
    // as `error`; transport connection errors use `connect_error`.
    socket.on('error', authenticationError);
    socket.onDisconnect((reason) {
      _cancelPending(const SocketFailure('Connection lost.'));
      if (identical(_socket, socket) && reason == 'io server disconnect') {
        if (recoverCredentials != null) {
          _recover(socket);
        } else {
          _notify('auth:error', {'status': 401});
          disconnect();
        }
      }
    });
    socket.io.on('reconnect_attempt', (_) {
      if (recoverCredentials != null && _expired(token)) _recover(socket);
    });
    socket.io.on('reconnect_failed', (_) => _notify('connection:failed', null));
    for (final entry in _listeners.entries) {
      for (final callback in entry.value) {
        socket.on(entry.key, callback);
      }
    }
    socket.connect();
  }

  @override
  Future<void> ensureConnected(String token) async {
    final generation = _sessionGeneration;
    if (recoverCredentials != null) {
      token = await recoverCredentials!(false) ?? '';
      if (generation != _sessionGeneration) {
        throw const SocketFailure('Session changed.');
      }
    }
    if (token.trim().isEmpty) {
      throw const SocketFailure('Please sign in again.', 401);
    }
    if (isConnected && _token == token) return;
    if (_socket != null && _token != token) {
      if (recoverCredentials == null) {
        disconnect();
      } else {
        _close(false);
      }
    }
    final ready = Completer<void>();
    void connected(dynamic _) {
      if (!ready.isCompleted) ready.complete();
    }

    void cancelled(SocketFailure error) {
      if (!ready.isCompleted) ready.completeError(error);
    }

    _pending.add(cancelled);
    on('connect', connected);
    try {
      connect(token);
      if (isConnected) connected(null);
      await ready.future.timeout(const Duration(seconds: 10),
          onTimeout: () =>
              throw const SocketFailure('Unable to connect. Please retry.'));
    } finally {
      off('connect', connected);
      _pending.remove(cancelled);
    }
  }

  @override
  Future<Map<String, dynamic>> request(
      String event, Map<String, dynamic> data) async {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      throw const SocketFailure('Not connected. Please retry.');
    }
    final result = Completer<Map<String, dynamic>>();
    void cancelled(SocketFailure error) {
      if (!result.isCompleted) result.completeError(error);
    }

    _pending.add(cancelled);
    try {
      socket.emitWithAck(event, data, ack: (dynamic response) {
        if (result.isCompleted) return;
        final envelope = objectMap(response);
        if (envelope['success'] != true) {
          result.completeError(SocketFailure(
              textValue(envelope['message']) ??
                  'Socket request failed. Please retry.',
              envelope['status'] is int ? envelope['status'] as int : null));
        } else {
          result.complete(objectMap(envelope['data']));
        }
      });
      return await result.future.timeout(const Duration(seconds: 8),
          onTimeout: () => throw const SocketFailure(
              'Server did not acknowledge the request. Please retry.'));
    } finally {
      _pending.remove(cancelled);
    }
  }

  static bool _expired(String token) {
    try {
      final data = objectMap(jsonDecode(utf8
          .decode(base64Url.decode(base64Url.normalize(token.split('.')[1])))));
      return data['exp'] is int &&
          (data['exp'] as int) * 1000 <=
              DateTime.now().millisecondsSinceEpoch + 30000;
    } catch (_) {
      return false;
    }
  }

  Future<void> _recover(io.Socket socket) async {
    if (_recovering || !identical(_socket, socket)) return;
    if (++_authRecoveries > 2) {
      _notify('auth:error', {'status': 401});
      disconnect();
      return;
    }
    _recovering = true;
    final generation = _sessionGeneration;
    _close(false);
    try {
      final token = await recoverCredentials!(true);
      if (generation == _sessionGeneration && token != null) connect(token);
    } catch (_) {
      // A transient failure leaves availability intent paused, without an
      // infinite reconnect loop. Session rejection is cleared by AuthService.
      _notify('session:paused', null);
    } finally {
      _recovering = false;
    }
  }

  void replaceCredentials(String token) {
    if (_token == token) return;
    if (_socket != null) _close(false);
    if (_connectionWanted) connect(token);
  }

  void _close(bool endSession) {
    final socket = _socket;
    _socket = null;
    _token = null;
    _cancelPending(const SocketFailure('Connection credentials changed.'));
    socket?.dispose();
    _notify(endSession ? 'session:ended' : 'disconnect', null);
  }

  @override
  void disconnect() {
    ++_sessionGeneration;
    _connectionWanted = false;
    _authRecoveries = 0;
    _close(true);
  }

  void emit(String event, dynamic data) {
    if (isConnected) _socket!.emit(event, data);
  }

  @override
  void on(String event, Function(dynamic) callback) {
    if (_listeners.putIfAbsent(event, () => {}).add(callback)) {
      _socket?.on(event, callback);
    }
  }

  @override
  void off(String event, [Function(dynamic)? callback]) {
    if (callback == null) {
      _listeners.remove(event);
      _socket?.off(event);
    } else {
      _listeners[event]?.remove(callback);
      _socket?.off(event, callback);
    }
  }

  @override
  bool get isConnected => _socket?.connected ?? false;
}
