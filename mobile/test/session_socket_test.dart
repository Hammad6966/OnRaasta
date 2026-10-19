import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:onraasta/services/socket_service.dart';
import 'package:onraasta/providers/mechanic_presence_controller.dart';
import 'package:onraasta/providers/job_tracking_publisher.dart';
import 'package:onraasta/providers/assignment_controller.dart';
import 'package:onraasta/services/foreground_location.dart';
import 'assignment_fixtures.dart';
import 'presence_fixtures.dart';

class _Transport extends io.Socket {
  bool disposed = false;
  bool autoConnect = true;
  final calls = <String>[];
  _Transport(Map<String, dynamic> options)
      : super(
            io.io('http://fixture.invalid',
                {...options, 'autoConnect': false, 'forceNew': true}).io,
            '/',
            options);
  @override
  io.Socket connect() {
    scheduleMicrotask(() {
      if (!disposed && autoConnect) onconnect('fixture', null);
    });
    return this;
  }

  @override
  void dispose() {
    disposed = true;
    connected = false;
    super.dispose();
  }

  void rejectAuth() => onpacket({
        'nsp': '/',
        'type': 4,
        'data': {
          'message': 'Expired',
          'data': {'status': 401}
        }
      });
  @override
  void emitWithAck(String event, dynamic data,
      {Function? ack, bool binary = false}) {
    if (['connect', 'disconnect', 'disconnecting', 'error', 'connect_error']
        .contains(event)) {
      super.emitWithAck(event, data, ack: ack, binary: binary);
      return;
    }
    calls.add(event);
    if (event == 'job:mechanic_location') {
      ack?.call({
        'success': true,
        'data': {
          'accepted': true,
          'location': {
            ...data,
            'mechanicId': 'mechanic-1',
            'receivedAt': DateTime.now().toUtc().toIso8601String()
          }
        }
      });
    } else {
      ack?.call({
        'success': true,
        'data': {
          'mechanicId': 'mechanic-1',
          'isOnline': event != 'mechanic:go_offline',
          'lat': data['lat'],
          'lng': data['lng'],
          'serviceRadius': 15
        }
      });
    }
  }
}

void main() {
  test(
      'socket uses canonical credentials and preserves individual listeners on token renewal',
      () async {
    final transports = <_Transport>[];
    final socket = SocketService.withFactory((u, o) {
      final t = _Transport(o);
      transports.add(t);
      return t;
    });
    var token = 'current-token', ended = 0, bids = 0, refreshes = 0;
    socket.recoverCredentials = (force) async {
      if (force) {
        refreshes++;
        token = 'renewed-token';
      }
      return token;
    };
    socket.on('session:ended', (_) => ended++);
    socket.on('bid:new', (_) => bids++);
    await socket.ensureConnected('stale-client-argument');
    expect(transports.single.auth, {'token': 'current-token'});
    transports.single.rejectAuth();
    await flushPresence();
    expect(refreshes, 1);
    expect(transports.length, 2);
    expect(transports.first.disposed, true);
    expect(transports.last.auth, {'token': 'renewed-token'});
    expect(ended, 0);
    transports.last.onevent({
      'data': ['bid:new', {}]
    });
    expect(bids, 1);
    socket.disconnect();
    expect(ended, 1);
  });
  test(
      'logout cancels a pending socket refresh and prevents previous identity reconnect',
      () async {
    final transports = <_Transport>[];
    final socket = SocketService.withFactory((u, o) {
      final t = _Transport(o);
      transports.add(t);
      return t;
    });
    final pending = Completer<String?>();
    socket.recoverCredentials =
        (force) async => force ? await pending.future : 'old-token';
    await socket.ensureConnected('old-token');
    transports.single.rejectAuth();
    socket.disconnect();
    pending.complete('late-old-token');
    await flushPresence();
    expect(transports.length, 1);
    expect(socket.isConnected, false);
  });
  test('unavailable refresh pauses socket without reconnect loops', () async {
    final transports = <_Transport>[];
    final socket = SocketService.withFactory((u, o) {
      final t = _Transport(o);
      transports.add(t);
      return t;
    });
    var attempts = 0;
    socket.recoverCredentials = (force) async {
      if (force) {
        attempts++;
        throw StateError('offline');
      }
      return 'old';
    };
    await socket.ensureConnected('old');
    transports.single.rejectAuth();
    await flushPresence();
    expect(attempts, 1);
    expect(transports.length, 1);
    expect(socket.isConnected, false);
    socket.disconnect();
  });
  test(
      'renewal restores approved presence, assignments and foreground GPS only after revalidation',
      () async {
    final transports = <_Transport>[];
    final socket = SocketService.withFactory((u, o) {
      final t = _Transport(o);
      transports.add(t);
      return t;
    });
    var token = 'first', profileReads = 0, assignmentReads = 0;
    socket.recoverCredentials = (force) async {
      if (force) token = 'second';
      return token;
    };
    final source = FakeForegroundLocation();
    // Both publisher and availability use the same application-level broker.
    final shared = SharedForegroundLocation(source);
    Future<Map<String, dynamic>> profile() async {
      profileReads++;
      return mechanicProfile();
    }

    final presence = MechanicPresenceController(
        socket: socket,
        gps: shared,
        token: () async => token,
        profile: profile,
        loadRequests: () async => []);
    final publisher = JobTrackingPublisher(
        socket: socket,
        gps: shared,
        token: () async => token,
        profile: profile,
        assignments: () async {
          assignmentReads++;
          return [assignment(status: 'en_route')];
        });
    final inbox = AssignmentInboxController(
        socket: socket,
        loadActive: () async {
          assignmentReads++;
          return [assignment(status: 'en_route')];
        },
        loadOne: (_) async => assignment(status: 'en_route'));
    await presence.initialize();
    await flushPresence();
    await presence.toggle();
    await publisher.reconcile();
    await flushPresence();
    expect(presence.online, true);
    expect(publisher.sharing('job-1'), true);
    final reads = profileReads, assignments = assignmentReads;
    transports.last.rejectAuth();
    await flushPresence();
    expect(transports.last.auth, {'token': 'second'});
    expect(presence.wantsOnline, true);
    expect(presence.online, true);
    expect(profileReads, greaterThan(reads));
    expect(assignmentReads, greaterThan(assignments));
    expect(inbox.bookings.single.jobId, 'job-1');
    expect(publisher.sharing('job-1'), true);
    socket.disconnect();
    expect(presence.wantsOnline, false);
    expect(publisher.sharing('job-1'), false);
    expect(inbox.bookings, isEmpty);
    final sent = transports.fold(0, (int n, t) => n + t.calls.length);
    source.updates.add(GpsPoint(31.01, 74.01));
    await flushPresence();
    expect(transports.fold(0, (int n, t) => n + t.calls.length), sent);
    publisher.dispose();
    presence.dispose();
    inbox.dispose();
    await source.close();
  });

  test(
      'a later HTTP refresh restores a paused desired socket, but not a logged-out socket',
      () async {
    final transports = <_Transport>[];
    final socket = SocketService.withFactory((u, o) {
      final t = _Transport(o);
      transports.add(t);
      return t;
    });
    var token = 'old';
    bool offline = true;
    socket.recoverCredentials = (force) async {
      if (force && offline) throw StateError('network');
      return token;
    };
    await socket.ensureConnected('old');
    transports.single.rejectAuth();
    await flushPresence();
    expect(socket.isConnected, false);
    token = 'new';
    offline = false;
    socket.replaceCredentials(token);
    await flushPresence();
    expect(socket.isConnected, true);
    expect(transports.last.auth, {'token': 'new'});
    socket.disconnect();
    socket.replaceCredentials('late');
    await flushPresence();
    expect(transports.length, 2);
    expect(socket.isConnected, false);
  });
  test(
      'repeated rejected handshakes have a bounded authentication recovery budget',
      () async {
    final transports = <_Transport>[];
    final socket = SocketService.withFactory((u, o) {
      final t = _Transport(o)..autoConnect = false;
      transports.add(t);
      return t;
    });
    var reads = 0;
    socket.recoverCredentials = (force) async {
      if (force) reads++;
      return 'rejected';
    };
    socket.connect('rejected');
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 3; i++) {
      transports.last.rejectAuth();
      await flushPresence();
    }
    expect(reads, 2);
    expect(transports.length, 3);
    expect(socket.isConnected, false);
    socket.disconnect();
  });
}
