import 'dart:async';
import 'package:onraasta/services/foreground_location.dart';
import 'package:onraasta/services/socket_service.dart';

class FakePresenceSocket implements PresenceSocket {
  final listeners = <String, Set<Function(dynamic)>>{};
  final calls = <Map<String, dynamic>>[];
  String? accessToken;
  bool connected = false;
  bool autoConnect = true;
  late Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
      respond;
  FakePresenceSocket() {
    respond = (event, data) async => {
          'mechanicId': 'mechanic-1',
          'isOnline': event != 'mechanic:go_offline',
          if (event != 'mechanic:go_offline') ...{
            'lat': data['lat'],
            'lng': data['lng'],
            'serviceRadius': 15
          }
        };
  }
  void fire(String event, [dynamic data]) {
    for (final callback
        in List<Function(dynamic)>.from(listeners[event] ?? {})) {
      callback(data);
    }
  }

  void loseConnection() {
    connected = false;
    fire('disconnect', 'transport close');
  }

  void reconnect() {
    connected = true;
    fire('connect');
  }

  @override
  bool get isConnected => connected;
  @override
  void connect(String token) {
    if (accessToken != null && accessToken != token) disconnect();
    accessToken = token;
    if (autoConnect && !connected) reconnect();
  }

  @override
  Future<void> ensureConnected(String token) async {
    connect(token);
    if (!connected) throw const SocketFailure('Connection unavailable.');
  }

  @override
  Future<Map<String, dynamic>> request(
      String event, Map<String, dynamic> data) {
    calls.add({'event': event, 'data': data});
    return respond(event, data);
  }

  @override
  void disconnect() {
    connected = false;
    accessToken = null;
    fire('disconnect', 'client disconnect');
    fire('session:ended');
  }

  @override
  void on(String event, Function(dynamic) callback) {
    listeners.putIfAbsent(event, () => {}).add(callback);
  }

  @override
  void off(String event, [Function(dynamic)? callback]) {
    if (callback == null) {
      listeners.remove(event);
    } else {
      listeners[event]?.remove(callback);
    }
  }
}

class FakeForegroundLocation implements ForegroundLocation {
  final updates = StreamController<GpsPoint>.broadcast();
  final services = StreamController<bool>.broadcast();
  int reads = 0, subscriptions = 0;
  Object? failure;
  GpsPoint? point;
  @override
  Future<GpsPoint> current() async {
    reads++;
    if (failure != null) throw failure!;
    return point ?? GpsPoint(31, 74);
  }

  @override
  Stream<GpsPoint> positions() {
    subscriptions++;
    return updates.stream;
  }

  @override
  Stream<bool> serviceChanges() => services.stream;
  Future<void> close() async {
    await updates.close();
    await services.close();
  }
}

Future<void> flushPresence() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, dynamic> mechanicProfile({bool approved = true}) => {
      '_id': 'mechanic-1',
      'isApproved': approved,
      'userId': {'_id': 'user-1', 'name': 'Actual Mechanic'}
    };
Map<String, dynamic> requestJson([String id = 'job-1']) => {
      'jobId': id,
      'description': 'Battery failed',
      'location': {'lat': 31, 'lng': 74},
      'distance': 2.25,
      'createdAt': DateTime.now().toIso8601String(),
      'aiDiagnosis': {'fault_class': 'dead_battery'}
    };
