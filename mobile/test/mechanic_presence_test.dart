import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:onraasta/models/job_request.dart';
import 'package:onraasta/providers/mechanic_presence_controller.dart';
import 'package:onraasta/services/foreground_location.dart';
import 'package:onraasta/services/socket_service.dart';
import 'presence_fixtures.dart';

void main() {
  late FakePresenceSocket socket;
  late FakeForegroundLocation gps;
  late MechanicPresenceController controller;
  bool approved = true;
  Object? profileError;
  String? token = 'access-token-current';
  Future<List<dynamic>> Function() feed = () async => [];
  setUp(() {
    socket = FakePresenceSocket();
    gps = FakeForegroundLocation();
    approved = true;
    profileError = null;
    token = 'access-token-current';
    feed = () async => [];
    controller = MechanicPresenceController(
        socket: socket,
        gps: gps,
        token: () async => token,
        profile: () async {
          if (profileError != null) throw profileError!;
          return mechanicProfile(approved: approved);
        },
        loadRequests: () => feed());
  });
  tearDown(() async {
    controller.dispose();
    await gps.close();
  });
  Future<void> start() async {
    await controller.initialize();
    await controller.toggle();
    await flushPresence();
  }

  test(
      'approved mechanic becomes online only after acknowledgment with real GPS',
      () async {
    final ack = Completer<Map<String, dynamic>>();
    socket.respond = (_, __) => ack.future;
    await controller.initialize();
    final pending = controller.toggle();
    await flushPresence();
    expect(controller.busy, true);
    expect(controller.online, false);
    expect(gps.reads, 1);
    expect(socket.calls.single['data'], {'lat': 31.0, 'lng': 74.0});
    ack.complete({
      'mechanicId': 'mechanic-1',
      'isOnline': true,
      'lat': 31,
      'lng': 74,
      'serviceRadius': 15
    });
    await pending;
    expect(controller.online, true);
    expect(controller.busy, false);
    expect(gps.subscriptions, 1);
    expect(socket.accessToken, 'access-token-current');
  });
  test('manual approval change reloads profile and stops revoked availability',
      () async {
    await start();
    approved = false;
    socket.fire('mechanic:approval_changed', {
      'mechanicId': 'mechanic-1',
      'isApproved': false,
      'accountApprovalStatus': 'revoked'
    });
    await flushPresence();
    expect(controller.online, false);
    expect(controller.approved, false);
    expect(controller.wantsOnline, false);
    expect(gps.updates.hasListener, false);
  });
  test('foreign approval events are ignored and owned listener is cleaned up',
      () async {
    await start();
    socket.fire('mechanic:approval_changed',
        {'mechanicId': 'other', 'isApproved': false});
    expect(controller.online, true);
    controller.dispose();
    expect(socket.listeners['mechanic:approval_changed'], isEmpty);
    controller = MechanicPresenceController(
        socket: socket,
        gps: gps,
        token: () async => token,
        profile: () async => mechanicProfile(),
        loadRequests: () => feed());
  });
  test('duplicate online taps send one request and subscribe once', () async {
    await controller.initialize();
    final first = controller.toggle(), second = controller.toggle();
    await Future.wait([first, second]);
    expect(socket.calls.where((c) => c['event'] == 'mechanic:go_online'),
        hasLength(1));
    expect(gps.subscriptions, 1);
  });
  test('unapproved mechanic sees pending approval and never registers presence',
      () async {
    approved = false;
    await start();
    expect(controller.online, false);
    expect(controller.approved, false);
    expect(controller.error, contains('approval'));
    expect(socket.calls, isEmpty);
    expect(gps.reads, 0);
  });
  test('approval is rechecked when toggling and after reconnect', () async {
    await start();
    socket.loseConnection();
    approved = false;
    socket.reconnect();
    await flushPresence();
    expect(controller.online, false);
    expect(controller.wantsOnline, false);
    expect(controller.error, contains('approval'));
    expect(socket.calls.where((c) => c['event'] == 'mechanic:go_online'),
        hasLength(1));
  });
  for (final message in [
    'Location permission denied. Allow access in settings.',
    'Location services disabled. Enable GPS.',
    'Unable to acquire GPS.'
  ]) {
    test('GPS failure is visible and never shows online: $message', () async {
      gps.failure = LocationFailure(message);
      await start();
      expect(controller.online, false);
      expect(controller.error, message);
      expect(socket.calls, isEmpty);
      expect(gps.subscriptions, 0);
    });
  }
  test('invalid and stale GPS never sent', () async {
    for (final point in [
      GpsPoint(0, 0),
      GpsPoint(91, 74),
      GpsPoint(double.nan, 74),
      GpsPoint(31, 74,
          observedAt: DateTime.now().subtract(const Duration(minutes: 2)))
    ]) {
      gps.point = point;
      await start();
      expect(controller.online, false);
    }
    expect(socket.calls, isEmpty);
  });
  test(
      'failed or malformed online acknowledgment never creates local availability',
      () async {
    socket.respond = (_, __) async => {};
    await start();
    expect(controller.online, false);
    expect(controller.error, contains('acknowledgment'));
    socket.respond =
        (_, __) async => throw const SocketFailure('Not approved', 403);
    await start();
    expect(controller.online, false);
    expect(controller.error, 'Not approved');
  });
  test(
      'offline is confirmed before UI changes and subscriptions stop immediately',
      () async {
    await start();
    final ack = Completer<Map<String, dynamic>>();
    socket.respond = (_, __) => ack.future;
    final pending = controller.goOffline();
    await flushPresence();
    expect(controller.online, true);
    expect(controller.busy, true);
    expect(controller.wantsOnline, false);
    expect(gps.updates.hasListener, false);
    socket.fire('job:new_request', requestJson());
    expect(controller.jobs, isEmpty);
    ack.complete({'mechanicId': 'mechanic-1', 'isOnline': false});
    await pending;
    expect(controller.online, false);
    expect(controller.busy, false);
  });
  test(
      'failed offline acknowledgment closes connection and reports uncertainty',
      () async {
    await start();
    socket.respond =
        (_, __) async => throw const SocketFailure('No acknowledgment');
    await controller.goOffline();
    expect(controller.online, false);
    expect(socket.isConnected, false);
    expect(controller.error, contains('Connection closed'));
  });
  test('foreground location updates go through acknowledged operations',
      () async {
    await start();
    gps.updates.add(GpsPoint(31.01, 74.02));
    await flushPresence();
    expect(socket.calls.last['event'], 'mechanic:update_location');
    expect(socket.calls.last['data'], {'lat': 31.01, 'lng': 74.02});
    expect(controller.location?.lat, 31.01);
  });
  test('heartbeat reacquires GPS and handles revoked permission', () async {
    await start();
    await controller.checkLocation();
    expect(gps.reads, 2);
    gps.failure = const LocationFailure('Permission revoked');
    await controller.checkLocation();
    expect(controller.online, false);
    expect(controller.wantsOnline, false);
    expect(gps.updates.hasListener, false);
  });
  test('disabled services or invalid updates stop availability', () async {
    await start();
    gps.services.add(false);
    await flushPresence();
    expect(controller.online, false);
    expect(controller.error, contains('disabled'));
    await controller.toggle();
    gps.updates.add(GpsPoint(0, 0));
    await flushPresence();
    expect(controller.online, false);
    expect(socket.isConnected, false);
  });
  test(
      'disconnect retains intent; reconnect rechecks approval and uses fresh GPS once',
      () async {
    await start();
    socket.loseConnection();
    expect(controller.online, false);
    expect(controller.wantsOnline, true);
    expect(gps.updates.hasListener, false);
    gps.point = GpsPoint(31.05, 74.03);
    socket.reconnect();
    await flushPresence();
    expect(controller.online, true);
    expect(gps.reads, 2);
    expect(gps.subscriptions, 2);
    expect(socket.calls.last['data'], {'lat': 31.05, 'lng': 74.03});
    socket.fire('connect');
    await flushPresence();
    // Repeated connect notifications while already available must not duplicate restoration.
    expect(socket.calls.where((c) => c['event'] == 'mechanic:go_online'),
        hasLength(2));
  });
  test('offline intent is never restored on reconnect', () async {
    await start();
    await controller.goOffline();
    socket.loseConnection();
    socket.reconnect();
    await flushPresence();
    expect(controller.online, false);
    expect(socket.calls.where((c) => c['event'] == 'mechanic:go_online'),
        hasLength(1));
  });
  test('background stops subscriptions and foreground restores with fresh GPS',
      () async {
    await start();
    controller.setForeground(false);
    expect(controller.online, false);
    expect(controller.wantsOnline, true);
    expect(gps.updates.hasListener, false);
    gps.point = GpsPoint(31.08, 74);
    controller.setForeground(true);
    await flushPresence();
    expect(controller.online, true);
    expect(controller.location?.lat, 31.08);
  });
  test(
      'late online acknowledgment after backgrounding never restores availability',
      () async {
    await controller.initialize();
    final ack = Completer<Map<String, dynamic>>();
    socket.respond = (_, __) => ack.future;
    final pending = controller.toggle();
    await flushPresence();
    controller.setForeground(false);
    ack.complete({
      'mechanicId': 'mechanic-1',
      'isOnline': true,
      'lat': 31,
      'lng': 74,
      'serviceRadius': 15
    });
    await pending;
    expect(controller.online, false);
    expect(gps.subscriptions, 0);
  });
  test(
      'logout and identity switch clear old intent, feed and location subscription',
      () async {
    await start();
    socket.fire('job:new_request', requestJson());
    socket.disconnect();
    expect(controller.wantsOnline, false);
    expect(controller.online, false);
    expect(controller.jobs, isEmpty);
    expect(gps.updates.hasListener, false);
    socket.connect('different-account-token');
    await flushPresence();
    expect(controller.online, false);
  });
  test('rejected authentication and exhausted reconnect attempts stop retrying',
      () async {
    await start();
    socket.fire('auth:error', {'status': 401});
    socket.reconnect();
    await flushPresence();
    expect(controller.online, false);
    expect(controller.wantsOnline, false);
    expect(controller.error, contains('sign in'));
    await controller.toggle();
    socket.fire('connection:failed');
    expect(controller.wantsOnline, false);
  });
  test('replacement/revocation notification removes local presence', () async {
    await start();
    socket.fire('mechanic:availability',
        {'isOnline': false, 'reason': 'Session replaced'});
    expect(controller.online, false);
    expect(controller.wantsOnline, false);
    expect(controller.error, 'Session replaced');
  });
  test(
      'duplicate job events deduplicate by saved ID and missing IDs are ignored',
      () async {
    await start();
    socket.fire('job:new_request', requestJson());
    socket.fire('job:new_request', requestJson());
    socket.fire('job:new_request', {'description': 'No ID'});
    expect(controller.jobs, hasLength(1));
    expect(controller.jobs.single.jobId, 'job-1');
    expect(controller.jobs.single.toJson()['location'], {'lat': 31, 'lng': 74});
  });
  test(
      'incoming request during reconnect feed loading survives and deduplicates',
      () async {
    final snapshot = Completer<List<dynamic>>();
    feed = () => snapshot.future;
    await controller.initialize();
    await controller.toggle();
    socket.fire('job:new_request', requestJson('during'));
    socket.fire('job:new_request', requestJson('same'));
    snapshot.complete([requestJson('same')]);
    await flushPresence();
    expect(
        controller.jobs.map((j) => j.jobId), containsAll(['during', 'same']));
    expect(controller.jobs, hasLength(2));
  });
  test('failed feed refresh preserves received requests', () async {
    await start();
    socket.fire('job:new_request', requestJson());
    feed = () async => throw Exception('Offline');
    await controller.refreshRequests();
    expect(controller.jobs, hasLength(1));
    expect(controller.feedError, isNotNull);
    controller.decline('job-1');
    expect(controller.jobs, isEmpty);
  });
  test('missing profile or session blocks online registration', () async {
    profileError = const SocketFailure('Unavailable');
    await start();
    expect(controller.online, false);
    expect(socket.calls, isEmpty);
    profileError = null;
    token = null;
    await start();
    expect(controller.online, false);
    expect(socket.calls, isEmpty);
  });
  test('job parser never fabricates distance, creation time or saved ID', () {
    final job = JobRequest.fromJson({'jobId': 'saved-id'});
    expect(job.distance, null);
    expect(job.distanceLabel, 'Distance unavailable');
    expect(job.timeAgo, 'Time unavailable');
    expect(() => JobRequest.fromJson({}), throwsFormatException);
  });
}
