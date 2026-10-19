import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onraasta/models/booking_arguments.dart';
import 'package:onraasta/providers/assignment_controller.dart';
import 'package:onraasta/services/api_service.dart';
import 'package:onraasta/services/assignment_service.dart';
import 'assignment_fixtures.dart';
import 'bidding_fixtures.dart';
import 'presence_fixtures.dart';

AcceptedBooking saved(String status, int version) {
  final json = assignmentJson(status: status);
  (json['job'] as Map)['statusVersion'] = version;
  return AcceptedBooking.fromAssignment(json);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePresenceSocket socket;
  late AssignmentDetailController detail;
  late BiddingAdapter adapter;
  late HttpClientAdapter original;
  setUp(() {
    socket = FakePresenceSocket();
    adapter = BiddingAdapter();
    FlutterSecureStorage.setMockInitialValues(
        {'access_token': 'fixture-access'});
    original = ApiService.instance.dio.httpClientAdapter;
    ApiService.instance.dio.httpClientAdapter = adapter;
  });
  tearDown(() {
    detail.dispose();
    ApiService.instance.dio.httpClientAdapter = original;
  });
  test(
      'matching events trigger reads; foreign and malformed events never change status',
      () async {
    int reads = 0;
    String status = 'accepted';
    detail = AssignmentDetailController(
        booking: saved('accepted', 0),
        socket: socket,
        token: () async => null,
        load: (_) async {
          reads++;
          return saved(status, reads);
        });
    socket.fire(
        'job:status_changed', {'jobId': 'foreign', 'status': 'completed'});
    socket.fire('job:status_changed', {'jobId': 'job-1', 'status': 'fake'});
    await flushPresence();
    expect(reads, 0);
    socket
        .fire('job:status_changed', {'jobId': 'job-1', 'status': 'completed'});
    await flushPresence();
    expect(reads, 1);
    expect(detail.booking.job['status'], 'accepted');
    status = 'en_route';
    socket.fire('job:status_changed',
        {'jobId': 'job-1', 'status': 'en_route', 'version': 2});
    await flushPresence();
    expect(detail.booking.job['status'], 'en_route');
  });
  test(
      'duplicate and older confirmed versions are ignored, never regress completed state',
      () async {
    int reads = 0;
    detail = AssignmentDetailController(
        booking: saved('completed', 4),
        socket: socket,
        token: () async => null,
        load: (_) async {
          reads++;
          return saved('completed', 4);
        });
    for (final version in [4, 1, 3, 4]) {
      socket.fire('job:status_changed',
          {'jobId': 'job-1', 'status': 'arrived', 'version': version});
    }
    await flushPresence();
    expect(reads, 0);
    expect(detail.booking.job['status'], 'completed');
  });
  test(
      'out-of-order unversioned events refetch current database state rather than applying payload status',
      () async {
    detail = AssignmentDetailController(
        booking: saved('arrived', 2),
        socket: socket,
        token: () async => null,
        load: (_) async => saved('completed', 4));
    socket.fire('job:status_changed', {'jobId': 'job-1', 'status': 'en_route'});
    await flushPresence();
    expect(detail.booking.job['status'], 'completed');
    await detail.reload();
    expect(detail.booking.job['statusVersion'], 4);
  });
  test('stale HTTP snapshot cannot overwrite a newer persisted version',
      () async {
    detail = AssignmentDetailController(
        booking: saved('completed', 4),
        socket: socket,
        token: () async => null,
        load: (_) async => saved('arrived', 2));
    await detail.reload();
    expect(detail.booking.job['status'], 'completed');
    expect(detail.booking.job['statusVersion'], 4);
  });
  test(
      'bursts during an in-flight read reconcile again and preserve latest status',
      () async {
    final pending = Completer<AcceptedBooking>();
    int reads = 0;
    detail = AssignmentDetailController(
        booking: saved('accepted', 0),
        socket: socket,
        token: () async => null,
        load: (_) => ++reads == 1
            ? pending.future
            : Future.value(saved('in_progress', 3)));
    socket.fire('job:status_changed',
        {'jobId': 'job-1', 'status': 'en_route', 'version': 1});
    socket.fire('job:status_changed',
        {'jobId': 'job-1', 'status': 'arrived', 'version': 2});
    socket.fire('job:status_changed',
        {'jobId': 'job-1', 'status': 'in_progress', 'version': 3});
    pending.complete(saved('en_route', 1));
    await flushPresence();
    expect(reads, 2);
    expect(detail.booking.job['status'], 'in_progress');
  });
  test(
      'reconnection recovers completed work and rejoins saved room without navigation side effects',
      () async {
    detail = AssignmentDetailController(
        booking: saved('arrived', 2),
        socket: socket,
        token: () async => 'fixture',
        load: (_) async => saved('completed', 4));
    socket.loseConnection();
    expect(detail.roomError, isNotNull);
    socket.reconnect();
    await flushPresence();
    expect(detail.booking.job['status'], 'completed');
    expect(socket.calls.single['data'], {'room': 'job_job-1'});
  });
  test('status listener cleanup retains another screen listener', () async {
    detail = AssignmentDetailController(
        booking: assignment(),
        socket: socket,
        token: () async => null,
        load: (_) async => assignment());
    final other = AssignmentDetailController(
        booking: assignment(),
        socket: socket,
        token: () async => null,
        load: (_) async => assignment());
    expect(socket.listeners['job:status_changed']!.length, 2);
    other.dispose();
    expect(socket.listeners['job:status_changed']!.length, 1);
  });
  test(
      'confirmed authenticated mutation sends expected snapshot and agreed amounts never change',
      () async {
    String status = 'accepted';
    int version = 0;
    detail = AssignmentDetailController(
        booking: saved(status, version),
        socket: socket,
        token: () async => null,
        load: (_) async => saved(status, version));
    adapter.respond = (request) async {
      status = 'en_route';
      version = 1;
      return ResponseBody.fromString(
          '{"success":true,"job":{"_id":"job-1","acceptedBidId":"bid-1","mechanicId":"mechanic-1","status":"en_route","statusVersion":1}}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
    };
    await detail.reload();
    await detail.updateStatus('en_route');
    expect(detail.booking.job['status'], 'en_route');
    expect(detail.booking.bid.totalCost, 1100.75);
    final r = adapter.requests.single;
    expect(r.headers['Authorization'], 'Bearer fixture-access');
    expect(r.data, {
      'status': 'en_route',
      'expectedStatus': 'accepted',
      'expectedVersion': 0
    });
  });
  test(
      'duplicate mutation taps issue one PATCH and never optimistically advance status',
      () async {
    final pending = Completer<ResponseBody>();
    detail = AssignmentDetailController(
        booking: saved('accepted', 0),
        socket: socket,
        token: () async => null,
        load: (_) async => saved('accepted', 0));
    adapter.respond = (_) => pending.future;
    await detail.reload();
    final first = detail.updateStatus('en_route');
    await detail.updateStatus('en_route');
    await flushPresence();
    expect(adapter.requests.length, 1);
    expect(detail.booking.job['status'], 'accepted');
    pending.complete(apiResponse({}, success: false, status: 409));
    await first;
    expect(detail.booking.job['status'], 'accepted');
    expect(detail.error, contains('not confirmed'));
  });
  for (final code in [401, 403, 404, 409, 500]) {
    test('mutation HTTP $code is actionable and never apparent success',
        () async {
      detail = AssignmentDetailController(
          booking: saved('accepted', 0),
          socket: socket,
          token: () async => null,
          load: (_) async => saved(
              code == 409 ? 'en_route' : 'accepted', code == 409 ? 1 : 0));
      adapter.respond =
          (_) async => apiResponse({}, success: false, status: code);
      await detail.reload();
      await detail.updateStatus('arrived');
      if (code == 401) {
        expect(detail.accessDenied, true);
      } else {
        expect(detail.error, contains('not confirmed'));
      }
      expect(detail.booking.bid.totalCost, 1100.75);
      expect(
          detail.booking.job['status'], code == 409 ? 'en_route' : 'accepted');
    });
  }
  test('assignment inbox removes terminal jobs via canonical status read',
      () async {
    detail = AssignmentDetailController(
        booking: assignment(),
        socket: socket,
        token: () async => null,
        load: (_) async => assignment());
    final inbox = AssignmentInboxController(
        socket: socket,
        loadActive: () async => [assignment()],
        loadOne: (_) async => assignment(status: 'completed'));
    await inbox.refresh();
    socket.fire('job:status_changed',
        {'jobId': 'job-1', 'status': 'completed', 'version': 4});
    await flushPresence();
    expect(inbox.bookings, isEmpty);
    inbox.dispose();
  });
  test(
      'completion arriving during an earlier inbox read is reconciled, never lost',
      () async {
    detail = AssignmentDetailController(
        booking: assignment(),
        socket: socket,
        token: () async => null,
        load: (_) async => assignment());
    final pending = Completer<AcceptedBooking>();
    int reads = 0;
    final inbox = AssignmentInboxController(
        socket: socket,
        loadActive: () async => [assignment()],
        loadOne: (_) => ++reads == 1
            ? pending.future
            : Future.value(saved('completed', 4)));
    await inbox.refresh();
    socket.fire('job:status_changed',
        {'jobId': 'job-1', 'status': 'arrived', 'version': 2});
    socket.fire('job:status_changed',
        {'jobId': 'job-1', 'status': 'completed', 'version': 4});
    pending.complete(saved('arrived', 2));
    await flushPresence();
    expect(reads, 2);
    expect(inbox.bookings, isEmpty);
    inbox.dispose();
  });
  test(
      'failed reconciliation keeps saved identity and price while exposing retry',
      () async {
    detail = AssignmentDetailController(
        booking: assignment(),
        socket: socket,
        token: () async => null,
        load: (_) async => throw const AssignmentFailure('Connection lost'));
    socket
        .fire('job:status_changed', {'jobId': 'job-1', 'status': 'completed'});
    await flushPresence();
    expect(detail.jobId, 'job-1');
    expect(detail.booking.bid.totalCost, 1100.75);
    expect(detail.verified, false);
    expect(detail.error, 'Connection lost');
  });
  test(
      'closed restart recovery is distinct from active jobs and stale lists cannot reopen it',
      () async {
    detail = AssignmentDetailController(
        booking: assignment(),
        socket: socket,
        token: () async => null,
        load: (_) async => assignment());
    adapter.respond =
        (_) async => apiResponse([assignmentJson(status: 'completed')]);
    final recovered =
        await AssignmentService(client: ApiService.instance.dio).recover();
    expect(
        adapter.requests.single.path, '/jobs/assignments?includeClosed=true');
    bool stale = false;
    final inbox = AssignmentInboxController(
        socket: socket,
        loadActive: () async => stale ? [assignment()] : recovered,
        loadOne: (_) async => assignment());
    await inbox.refresh();
    expect(inbox.bookings, isEmpty);
    expect(inbox.recentClosed.single.job['status'], 'completed');
    stale = true;
    await inbox.refresh();
    expect(inbox.bookings, isEmpty);
    expect(inbox.recentClosed.single.jobId, 'job-1');
    inbox.dispose();
  });
  test(
      'conflict followed by a failed reload does not claim fresh state was loaded',
      () async {
    int reads = 0;
    detail = AssignmentDetailController(
        booking: saved('accepted', 0),
        socket: socket,
        token: () async => null,
        load: (_) async {
          if (++reads > 1) {
            throw const AssignmentFailure('offline');
          }
          return saved('accepted', 0);
        });
    adapter.respond = (_) async => apiResponse({}, success: false, status: 409);
    await detail.reload();
    await detail.updateStatus('en_route');
    expect(detail.verified, false);
    expect(detail.error, contains('reload the job'));
    expect(detail.error, isNot(contains('latest state is shown')));
    expect(detail.booking.job['status'], 'accepted');
  });
}
