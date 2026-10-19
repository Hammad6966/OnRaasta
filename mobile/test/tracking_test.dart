import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onraasta/models/job_location.dart';
import 'package:onraasta/providers/assignment_controller.dart';
import 'package:onraasta/providers/mechanic_presence_controller.dart';
import 'package:onraasta/providers/job_location_controller.dart';
import 'package:onraasta/providers/job_tracking_publisher.dart';
import 'package:onraasta/services/foreground_location.dart';
import 'package:onraasta/services/job_location_service.dart';
import 'package:onraasta/services/socket_service.dart';
import 'assignment_fixtures.dart';
import 'bidding_fixtures.dart';
import 'presence_fixtures.dart';

Map<String, dynamic> observation(
        {String job = 'job-1',
        String mechanic = 'mechanic-1',
        double lat = 31,
        double lng = 74,
        DateTime? observed}) =>
    {
      'jobId': job,
      'mechanicId': mechanic,
      'lat': lat,
      'lng': lng,
      'accuracy': 12,
      'observedAt': (observed ?? DateTime.now()).toUtc().toIso8601String(),
      'receivedAt': DateTime.now().toUtc().toIso8601String(),
    };
Future<Map<String, dynamic>> acknowledge(
        String event, Map<String, dynamic> data) async =>
    {
      'accepted': true,
      'location': {
        ...data,
        'mechanicId': 'mechanic-1',
        'receivedAt': DateTime.now().toUtc().toIso8601String()
      }
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'canonical observation requires real IDs, coordinates, accuracy and timestamp',
      () {
    expect(JobLocation.parse(observation()).lat, 31);
    for (final change in [
      {'lat': 91},
      {'lng': double.nan},
      {'lat': 0, 'lng': 0},
      {'accuracy': 101},
      {'accuracy': -1},
      {'observedAt': 'invalid'},
      {'jobId': null}
    ]) {
      expect(() => JobLocation.parse({...observation(), ...change}),
          throwsFormatException);
    }
  });
  test(
      'latest authorized API parses absent, valid and malformed snapshots using the saved Job ID',
      () async {
    final adapter = BiddingAdapter(),
        dio = Dio(BaseOptions(
            baseUrl: 'https://fixture.invalid',
            headers: {'Authorization': 'Bearer fixture'}));
    dio.httpClientAdapter = adapter;
    final service = JobLocationService(client: dio);
    adapter.respond = (_) async => apiResponse(
        {'jobId': 'job-1', 'trackingAllowed': true, 'location': observation()});
    expect((await service.latest('job-1')).location!.jobId, 'job-1');
    expect(adapter.requests.single.path, '/jobs/job-1/location');
    expect(adapter.requests.single.headers['Authorization'], 'Bearer fixture');
    adapter.respond = (_) async => apiResponse(
        {'jobId': 'job-1', 'trackingAllowed': true, 'location': null});
    expect((await service.latest('job-1')).location, isNull);
    adapter.respond = (_) async => apiResponse(
        {'jobId': 'other', 'trackingAllowed': true, 'location': observation()});
    await expectLater(service.latest('job-1'), throwsFormatException);
  });
  group('mechanic foreground publisher', () {
    late FakePresenceSocket socket;
    late FakeForegroundLocation gps;
    late JobTrackingPublisher publisher;
    String status = 'en_route';
    bool approved = true;
    setUp(() {
      status = 'en_route';
      approved = true;
      socket = FakePresenceSocket()
        ..connected = true
        ..accessToken = 'fixture';
      socket.respond = acknowledge;
      gps = FakeForegroundLocation()
        ..point = GpsPoint(31, 74,
            accuracy: 12,
            observedAt: DateTime.now().subtract(const Duration(seconds: 30)));
      publisher = JobTrackingPublisher(
          socket: socket,
          gps: gps,
          token: () async => 'fixture',
          profile: () async => mechanicProfile(approved: approved),
          assignments: () async => [assignment(status: status)]);
    });
    tearDown(() async {
      publisher.dispose();
      await gps.close();
    });
    test(
        'publishes only an authenticated en-route assignment with real timestamp and accuracy',
        () async {
      await publisher.reconcile();
      expect(publisher.sharing('job-1'), true);
      final call = socket.calls.single;
      expect(call['event'], 'job:mechanic_location');
      expect(call['data']['jobId'], 'job-1');
      expect(call['data']['lat'], 31);
      expect(call['data']['accuracy'], 12);
      expect(call['data'].containsKey('mechanicId'), false);
      expect(DateTime.tryParse(call['data']['observedAt']), isNotNull);
    });
    test('sharing is not active before server acknowledgment', () async {
      final ack = Completer<Map<String, dynamic>>();
      socket.respond = (_, __) => ack.future;
      final pending = publisher.reconcile();
      await flushPresence();
      expect(publisher.sharing('job-1'), false);
      ack.complete(await acknowledge(
          'job:mechanic_location', socket.calls.single['data']));
      await pending;
      expect(publisher.sharing('job-1'), true);
    });
    test(
        'duplicate, unchanged and too-frequent observations produce no extra events',
        () async {
      await publisher.reconcile();
      await publisher.publish(gps.point!);
      await publisher.publish(GpsPoint(31, 74,
          observedAt: DateTime.now().subtract(const Duration(seconds: 10))));
      await publisher.publish(GpsPoint(31.0005, 74,
          observedAt: gps.point!.observedAt.add(const Duration(seconds: 1))));
      expect(socket.calls.length, 1);
      await publisher.publish(GpsPoint(31.0005, 74,
          observedAt: gps.point!.observedAt.add(const Duration(seconds: 15))));
      expect(socket.calls.length, 2);
    });
    test('permission denial shows an error, never substituted coordinates',
        () async {
      gps.failure = const LocationFailure('Location permission denied');
      await publisher.reconcile();
      expect(publisher.sharing('job-1'), false);
      expect(socket.calls, isEmpty);
      expect(publisher.message('job-1'), contains('permission denied'));
    });
    test('invalid, stale and inaccurate GPS is rejected locally', () async {
      gps.point = GpsPoint(0, 0);
      await publisher.reconcile();
      expect(socket.calls, isEmpty);
      gps.point = GpsPoint(31, 74, accuracy: 101);
      await publisher.reconcile();
      expect(socket.calls, isEmpty);
      gps.point = GpsPoint(31, 74,
          observedAt: DateTime.now().subtract(const Duration(minutes: 2)));
      await publisher.reconcile();
      expect(socket.calls, isEmpty);
    });
    test('unapproved mechanic does not start GPS or publish', () async {
      approved = false;
      await publisher.reconcile();
      expect(gps.reads, 0);
      expect(socket.calls, isEmpty);
      expect(publisher.error, contains('Approval'));
    });
    for (final stage in [
      'accepted',
      'arrived',
      'in_progress',
      'completed',
      'cancelled'
    ]) {
      test('$stage does not publish', () async {
        status = stage;
        await publisher.reconcile();
        expect(socket.calls, isEmpty);
        expect(gps.reads, 0);
      });
    }
    test('disabled GPS or revoked permission stops only the job publisher',
        () async {
      await publisher.reconcile();
      gps.services.add(false);
      await flushPresence();
      expect(publisher.sharing('job-1'), false);
      expect(socket.isConnected, true);
      expect(publisher.message('job-1'), contains('disabled'));
    });
    test(
        'background stops subscriptions and resume rechecks assignment before any publication',
        () async {
      await publisher.reconcile();
      publisher.setForeground(false);
      await flushPresence();
      expect(gps.updates.hasListener, false);
      expect(publisher.sharing('job-1'), false);
      status = 'arrived';
      publisher.setForeground(true);
      await flushPresence();
      expect(socket.calls.length, 1);
      expect(publisher.sharing('job-1'), false);
    });
    test(
        'reconnect rechecks the job and fresh GPS, and restores sharing without navigation',
        () async {
      await publisher.reconcile();
      socket.loseConnection();
      expect(publisher.sharing('job-1'), false);
      gps.point = GpsPoint(31.0005, 74);
      socket.reconnect();
      await flushPresence();
      expect(publisher.sharing('job-1'), true);
      expect(socket.calls.last['data']['lat'], 31.0005);
    });
    test('logout ignores a delayed acknowledgment and cancels subscriptions',
        () async {
      final ack = Completer<Map<String, dynamic>>();
      socket.respond = (_, __) => ack.future;
      final read = publisher.reconcile();
      await flushPresence();
      socket.disconnect();
      ack.complete(await acknowledge('', socket.calls.single['data']));
      await read;
      expect(publisher.sharing('job-1'), false);
      expect(gps.updates.hasListener, false);
    });
    test(
        'confirmed HTTP arrival stops sharing even if its status socket event is missed',
        () async {
      await publisher.reconcile();
      publisher.observeAssignment(assignment(status: 'arrived'));
      await publisher.publish(GpsPoint(31.001, 74));
      expect(publisher.sharing('job-1'), false);
      expect(socket.calls.length, 1);
      expect(gps.updates.hasListener, false);
    });
    test(
        'temporary throttling keeps the stream for the next real observation, without retry timers',
        () async {
      socket.respond =
          (_, __) async => throw const SocketFailure('Too frequent', 429);
      await publisher.reconcile();
      expect(publisher.sharing('job-1'), false);
      expect(gps.updates.hasListener, true);
      socket.respond = acknowledge;
      await publisher.publish(GpsPoint(31.0005, 74));
      expect(publisher.sharing('job-1'), true);
    });
    test('repeated reconcile never duplicates active stream listeners',
        () async {
      await publisher.reconcile();
      await publisher.reconcile();
      final before = socket.calls.length;
      gps.updates.add(GpsPoint(31.001, 74));
      await flushPresence();
      expect(socket.calls.length, before + 1);
    });
  });
  test(
      'GPS stream is shared between consumers and stops when the final consumer leaves',
      () async {
    final source = FakeForegroundLocation(),
        shared = SharedForegroundLocation(source);
    int seen = 0;
    final a = shared.positions().listen((_) {
          seen++;
        }),
        b = shared.positions().listen((_) {
          seen++;
        });
    await flushPresence();
    expect(source.subscriptions, 1);
    source.updates.add(GpsPoint(31, 74));
    await flushPresence();
    expect(seen, 2);
    await a.cancel();
    expect(source.updates.hasListener, true);
    await b.cancel();
    await flushPresence();
    expect(source.updates.hasListener, false);
    final c = shared.positions().listen((_) {
      seen++;
    });
    await flushPresence();
    expect(source.subscriptions, 2);
    await c.cancel();
    await source.close();
  });
  test(
      'R04 availability and job tracking share the native GPS stream and isolate job errors',
      () async {
    final source = FakeForegroundLocation(),
        shared = SharedForegroundLocation(source);
    final socket = FakePresenceSocket();
    final availabilityAck = socket.respond;
    socket.respond = (event, data) => event == 'job:mechanic_location'
        ? acknowledge(event, data)
        : availabilityAck(event, data);
    final presence = MechanicPresenceController(
        socket: socket,
        gps: shared,
        token: () async => 'fixture',
        profile: () async => mechanicProfile(),
        loadRequests: () async => []);
    final publisher = JobTrackingPublisher(
        socket: socket,
        gps: shared,
        token: () async => 'fixture',
        profile: () async => mechanicProfile(),
        assignments: () async => [assignment(status: 'en_route')]);
    await presence.initialize();
    await presence.toggle();
    await flushPresence();
    await publisher.reconcile();
    await flushPresence();
    expect(source.subscriptions, 1);
    expect(presence.online, true);
    socket.fire('security:error', {
      'event': 'job:mechanic_location',
      'status': 409,
      'message': 'Job changed'
    });
    expect(presence.online, true);
    publisher.dispose();
    presence.dispose();
    await source.close();
  });
  test('geographic distance uses Haversine without claiming a road route', () {
    expect(distanceMeters(31, 74, 31, 74), 0);
    expect(distanceMeters(31, 74, 31.01, 74), closeTo(1112, 1));
  });
  group('driver tracking state', () {
    late FakePresenceSocket socket;
    late AssignmentDetailController detail;
    late JobLocationController controller;
    DateTime now = DateTime.now();
    String status = 'en_route';
    JobLocationSnapshot? snapshot;
    setUp(() {
      now = DateTime.now();
      status = 'en_route';
      socket = FakePresenceSocket()..connected = true;
      snapshot = JobLocationSnapshot('job-1', true, null);
      detail = AssignmentDetailController(
          booking: assignment(status: status),
          socket: socket,
          token: () async => null,
          load: (_) async => assignment(status: status));
      controller = JobLocationController(
          assignment: detail,
          socket: socket,
          load: (_) async => snapshot!,
          clock: () => now);
    });
    tearDown(() {
      controller.dispose();
      detail.dispose();
    });
    test(
        'absence is honest and first/later authorized observations initialize and update real coordinates',
        () async {
      await detail.reload();
      await flushPresence();
      expect(controller.location, isNull);
      expect(controller.label, contains('Waiting'));
      socket.fire('job:mechanic_location',
          observation(observed: now.subtract(const Duration(seconds: 2))));
      expect(controller.location!.lat, 31);
      socket.fire(
          'job:mechanic_location',
          observation(
              lat: 31.001, observed: now.subtract(const Duration(seconds: 1))));
      expect(controller.location!.lat, 31.001);
      expect(detail.booking.job['status'], 'en_route');
    });
    test('foreign Job/mechanic and invalid coordinates are ignored', () async {
      await detail.reload();
      await flushPresence();
      for (final point in [
        observation(job: 'other'),
        observation(mechanic: 'other'),
        {...observation(), 'lat': 91}
      ]) {
        socket.fire('job:mechanic_location', point);
      }
      expect(controller.location, isNull);
    });
    test('older/duplicate observations never rewind movement', () async {
      await detail.reload();
      await flushPresence();
      socket.fire(
          'job:mechanic_location', observation(lat: 31.001, observed: now));
      socket.fire('job:mechanic_location',
          observation(observed: now.subtract(const Duration(seconds: 5))));
      socket.fire(
          'job:mechanic_location', observation(lat: 31.002, observed: now));
      expect(controller.location!.lat, 31.001);
    });
    test(
        'freshness expires without moving the marker, and disconnect shows offline',
        () async {
      await detail.reload();
      await flushPresence();
      socket.fire('job:mechanic_location', observation(observed: now));
      expect(controller.label, contains('Recent location'));
      now = now.add(const Duration(seconds: 61));
      expect(controller.label, contains('stale'));
      expect(controller.location!.lat, 31);
      socket.loseConnection();
      expect(controller.label, contains('Offline'));
    });
    test(
        'reconnect recovers the persisted latest location after assignment reauthorization',
        () async {
      await detail.reload();
      await flushPresence();
      socket.loseConnection();
      snapshot = JobLocationSnapshot('job-1', true,
          JobLocation.parse(observation(lat: 31.002, observed: now)));
      socket.reconnect();
      await flushPresence();
      expect(controller.location!.lat, 31.002);
    });
    test('API snapshot cannot replace a newer socket observation while loading',
        () async {
      await detail.reload();
      await flushPresence();
      final pending = Completer<JobLocationSnapshot>();
      final other = JobLocationController(
          assignment: detail,
          socket: socket,
          load: (_) => pending.future,
          clock: () => now);
      final recovery = other.recover();
      socket.fire(
          'job:mechanic_location', observation(lat: 31.002, observed: now));
      pending.complete(JobLocationSnapshot(
          'job-1',
          true,
          JobLocation.parse(observation(
              observed: now.subtract(const Duration(seconds: 5))))));
      await recovery;
      expect(other.location!.lat, 31.002);
      other.dispose();
    });
    test(
        'arrival and terminal states clear coordinates and never trigger status changes from GPS',
        () async {
      await detail.reload();
      await flushPresence();
      socket.fire('job:mechanic_location', observation(observed: now));
      status = 'arrived';
      await detail.reload();
      expect(controller.location, isNull);
      socket.fire('job:mechanic_location', observation(lat: 31.002));
      expect(controller.location, isNull);
      expect(detail.booking.job['status'], 'arrived');
    });
    test(
        'logout/account switch clears the old point and ignores delayed old-session relays',
        () async {
      await detail.reload();
      await flushPresence();
      socket.fire('job:mechanic_location', observation(observed: now));
      socket.disconnect();
      expect(controller.location, isNull);
      socket.fire('job:mechanic_location', observation(lat: 31.002));
      expect(controller.location, isNull);
    });
    test(
        'background hides live state until resume and persisted reconciliation',
        () async {
      await detail.reload();
      await flushPresence();
      socket.fire('job:mechanic_location', observation(observed: now));
      controller.setForeground(false);
      expect(controller.location, isNull);
      expect(controller.label, contains('paused'));
      snapshot = JobLocationSnapshot('job-1', true, null);
      controller.setForeground(true);
      await detail.reload();
      await flushPresence();
      expect(controller.location, isNull);
    });
    test(
        'HTTP access denial clears the marker and blocks late old relays until fresh assignment authorization',
        () async {
      await detail.reload();
      await flushPresence();
      socket.fire('job:mechanic_location', observation(observed: now));
      final protected = JobLocationController(
          assignment: detail,
          socket: socket,
          clock: () => now,
          load: (_) async => throw DioException(
              requestOptions: RequestOptions(path: '/jobs/job-1/location'),
              response: Response(
                  requestOptions: RequestOptions(path: '/jobs/job-1/location'),
                  statusCode: 403)));
      await protected.recover();
      socket.fire(
          'job:mechanic_location', observation(lat: 31.002, observed: now));
      expect(protected.location, isNull);
      expect(protected.label, contains('access unavailable'));
      protected.dispose();
    });
    test(
        'manual retry reuses the current authenticated socket and reloads the latest authorized point',
        () async {
      final current = AssignmentDetailController(
          booking: assignment(status: 'en_route'),
          socket: socket,
          token: () async => 'current-access',
          load: (_) async => assignment(status: 'en_route'));
      final view = JobLocationController(
          assignment: current,
          socket: socket,
          clock: () => now,
          load: (_) async => JobLocationSnapshot(
              'job-1', true, JobLocation.parse(observation(observed: now))));
      socket.loseConnection();
      await view.retry();
      await flushPresence();
      expect(socket.accessToken, 'current-access');
      expect(view.location!.lat, 31);
      view.dispose();
      current.dispose();
    });
  });
}
