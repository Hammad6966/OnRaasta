import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onraasta/models/booking_arguments.dart';
import 'package:onraasta/providers/assignment_controller.dart';
import 'package:onraasta/providers/opportunity_controller.dart';
import 'package:onraasta/providers/mechanic_presence_controller.dart';
import 'package:onraasta/services/assignment_service.dart';
import 'assignment_fixtures.dart';
import 'bidding_fixtures.dart';
import 'presence_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'canonical assignment retains distinct IDs, persisted status, costs, ETA and job content',
      () {
    final a = assignment();
    expect([a.jobId, a.bid.bidId, a.bid.mechanicId, a.bid.mechanicUserId],
        ['job-1', 'bid-1', 'mechanic-1', 'mechanic-user-1']);
    expect([a.bid.labourCost, a.bid.partsCost, a.bid.totalCost, a.bid.eta],
        [900.5, 200.25, 1100.75, 12]);
    expect(a.driver['name'], 'Saved Customer');
    expect(a.job['photos'], savedJob()['photos']);
    expect(a.job['vehicleId'], 'vehicle-1');
    expect(a.job['status'], 'accepted');
  });
  for (final key in [
    'jobId',
    'acceptedBidId',
    'mechanicId',
    'mechanicUserId',
    'userId',
    'status',
    'totalCost',
    'labourCost',
    'partsCost',
    'eta'
  ]) {
    test('canonical parser rejects mismatched $key', () {
      final json = assignmentJson();
      json[key] = 'wrong';
      expect(() => AcceptedBooking.fromAssignment(json), throwsFormatException);
      expect(AcceptedBooking.tryParse(json), isNull);
    });
  }
  test('terminal assignments retain identity but are not active', () {
    for (final status in ['completed', 'cancelled']) {
      final a = assignment(status: status);
      expect(a.isActive, false);
      expect(a.jobId, 'job-1');
    }
  });
  group('authenticated recovery API', () {
    late BiddingAdapter adapter;
    late AssignmentService service;
    setUp(() {
      adapter = BiddingAdapter();
      final dio = Dio(BaseOptions(
          baseUrl: 'https://fixture.invalid',
          headers: {'Authorization': 'Bearer fixture-access'}))
        ..httpClientAdapter = adapter;
      service = AssignmentService(client: dio);
    });
    test('loads confirmed single job and uses current authenticated client',
        () async {
      adapter.respond = (_) async => apiResponse(assignmentJson());
      final a = await service.load('job-1');
      expect(a.jobId, 'job-1');
      expect(adapter.requests.single.path, '/jobs/job-1/assignment');
      expect(adapter.requests.single.headers['Authorization'],
          'Bearer fixture-access');
    });
    test(
        'restart reads list including multiple actual assignments and excludes completed',
        () async {
      adapter.respond = (_) async => apiResponse([
            assignmentJson(id: 'job-2'),
            assignmentJson(),
            assignmentJson(id: 'job-3', status: 'completed')
          ]);
      expect((await service.active()).map((a) => a.jobId), ['job-1', 'job-2']);
      expect(adapter.requests.single.path, '/jobs/assignments');
    });
    test('empty assignments remain empty', () async {
      adapter.respond = (_) async => apiResponse([]);
      expect(await service.active(), isEmpty);
    });
    test('unrelated saved job and malformed envelope are rejected', () async {
      adapter.respond = (_) async => apiResponse(assignmentJson(id: 'other'));
      await expectLater(
          service.load('job-1'), throwsA(isA<AssignmentFailure>()));
      adapter.respond = (_) async => apiResponse({'bad': true});
      await expectLater(
          service.load('job-1'), throwsA(isA<AssignmentFailure>()));
    });
    for (final status in [401, 403, 404, 409, 500]) {
      test('HTTP $status is recoverable and not apparent success', () async {
        adapter.respond =
            (_) async => apiResponse({}, success: false, status: status);
        await expectLater(
            service.load('job-1'),
            throwsA(isA<AssignmentFailure>()
                .having((e) => e.status, 'status', status)));
      });
    }
    test('opportunity uses actual ID and validates availability response',
        () async {
      adapter.respond =
          (_) async => apiResponse({'jobId': 'job-1', 'isOpen': false});
      expect(await service.isOpen('job-1'), false);
      adapter.respond =
          (_) async => apiResponse({'jobId': 'other', 'isOpen': true});
      await expectLater(
          service.isOpen('job-1'), throwsA(isA<AssignmentFailure>()));
    });
  });
  group('durable assignment inbox', () {
    late FakePresenceSocket socket;
    late AssignmentInboxController inbox;
    setUp(() => socket = FakePresenceSocket());
    tearDown(() => inbox.dispose());
    test(
        'startup and reconnect recover missed notifications without navigation or duplicate assignments',
        () async {
      int reads = 0;
      inbox = AssignmentInboxController(
          socket: socket,
          loadActive: () async {
            reads++;
            return [assignment()];
          },
          loadOne: (_) async => assignment());
      await inbox.refresh();
      socket.reconnect();
      await flushPresence();
      expect(inbox.bookings.single.jobId, 'job-1');
      expect(reads, 2);
      socket.fire('job:assigned', assignmentHint());
      socket.fire('job:assigned', assignmentHint());
      await flushPresence();
      expect(inbox.bookings.length, 1);
    });
    test('notification during initial load wins over stale empty list',
        () async {
      final pending = Completer<List<AcceptedBooking>>();
      inbox = AssignmentInboxController(
          socket: socket,
          loadActive: () => pending.future,
          loadOne: (_) async => assignment());
      final refresh = inbox.refresh();
      socket.fire('job:assigned', assignmentHint());
      await flushPresence();
      pending.complete([]);
      await refresh;
      expect(inbox.bookings.single.jobId, 'job-1');
    });
    test('outdated HTTP list cannot replace newer state', () async {
      final old = Completer<List<AcceptedBooking>>();
      int calls = 0;
      inbox = AssignmentInboxController(
          socket: socket,
          loadActive: () =>
              ++calls == 1 ? old.future : Future.value([assignment()]),
          loadOne: (_) async => assignment());
      final pending = inbox.refresh();
      await inbox.refresh();
      old.complete([]);
      await pending;
      expect(inbox.bookings.length, 1);
    });
    test(
        'network failure preserves confirmed identity; forbidden clears private list',
        () async {
      int mode = 0;
      inbox = AssignmentInboxController(
          socket: socket,
          loadActive: () async {
            if (mode > 0) {
              throw AssignmentFailure('Failed', mode == 2 ? 403 : 500);
            }
            return [assignment()];
          },
          loadOne: (_) async => assignment());
      await inbox.refresh();
      mode = 1;
      await inbox.refresh();
      expect(inbox.bookings.single.jobId, 'job-1');
      expect(inbox.error, isNotNull);
      mode = 2;
      await inbox.refresh();
      expect(inbox.bookings, isEmpty);
    });
    test('logout clears identity and ignores old pending assignment reads',
        () async {
      final pending = Completer<AcceptedBooking>();
      inbox = AssignmentInboxController(
          socket: socket,
          loadActive: () async => [],
          loadOne: (_) => pending.future);
      socket.fire('job:assigned', assignmentHint());
      socket.fire('session:ended');
      pending.complete(assignment());
      await flushPresence();
      expect(inbox.bookings, isEmpty);
    });
    test('malformed/unrelated hint never becomes an assignment', () async {
      int reads = 0;
      inbox = AssignmentInboxController(
          socket: socket,
          loadActive: () async => [],
          loadOne: (_) async {
            reads++;
            return assignment(id: 'other');
          });
      socket.fire('job:assigned', {'jobId': 'job-1'});
      await flushPresence();
      expect(reads, 0);
      socket.fire('job:assigned', assignmentHint());
      await flushPresence();
      expect(inbox.bookings, isEmpty);
      expect(inbox.error, isNotNull);
    });
    test(
        'opportunity invalidation has no private payload and does not erase winner',
        () async {
      final removed = <String>[];
      inbox = AssignmentInboxController(
          socket: socket,
          loadActive: () async => [assignment()],
          loadOne: (_) async => assignment(),
          onUnavailable: removed.add);
      await inbox.refresh();
      expect(
          removed, ['job-1']); // API recovery also removes stale opportunities.
      socket.fire('job:unavailable', {'jobId': 'job-1'});
      expect(removed, ['job-1', 'job-1']);
      expect(inbox.bookings.length, 1);
    });
    test('disposal removes exactly this inbox listeners', () async {
      inbox = AssignmentInboxController(
          socket: socket,
          loadActive: () async => [],
          loadOne: (_) async => assignment());
      void other(dynamic _) {}
      socket.on('job:assigned', other);
      // Separate controller checks cleanup without double-disposing the fixture.
      final another = AssignmentInboxController(
          socket: socket,
          loadActive: () async => [],
          loadOne: (_) async => assignment());
      another.dispose();
      expect(socket.listeners['job:assigned']!.length, 2);
    });
  });
  group('detail recovery', () {
    late FakePresenceSocket socket;
    late AssignmentDetailController detail;
    setUp(() => socket = FakePresenceSocket());
    tearDown(() => detail.dispose());
    test('loads persisted state then joins only saved job room after reconnect',
        () async {
      int reads = 0;
      detail = AssignmentDetailController(
          booking: assignment(),
          socket: socket,
          token: () async => 'fixture',
          load: (_) async {
            reads++;
            return assignment(status: 'arrived');
          });
      await detail.reload();
      expect(detail.booking.job['status'], 'arrived');
      expect(detail.roomError, isNotNull);
      socket.reconnect();
      await flushPresence();
      expect(reads, 2);
      expect(socket.calls.single['data'], {'room': 'job_job-1'});
    });
    test(
        'failure retains saved ID and exact agreed price, retry restores authority',
        () async {
      bool fail = true;
      detail = AssignmentDetailController(
          booking: assignment(),
          socket: socket,
          token: () async => null,
          load: (_) async {
            if (fail) throw const AssignmentFailure('offline');
            return assignment();
          });
      await detail.reload();
      expect(detail.verified, false);
      expect(detail.booking.bid.totalCost, 1100.75);
      expect(detail.jobId, 'job-1');
      fail = false;
      await detail.reload();
      expect(detail.verified, true);
    });
    test(
        'forbidden read hides private details and logout invalidates pending recovery',
        () async {
      detail = AssignmentDetailController(
          booking: assignment(),
          socket: socket,
          token: () async => null,
          load: (_) async => throw const AssignmentFailure('forbidden', 403));
      await detail.reload();
      expect(detail.accessDenied, true);
      expect(detail.verified, false);
    });
    test('unrelated assignment cannot overwrite saved identity', () async {
      detail = AssignmentDetailController(
          booking: assignment(),
          socket: socket,
          token: () async => null,
          load: (_) async => assignment(id: 'other'));
      await detail.reload();
      expect(detail.booking.jobId, 'job-1');
      expect(detail.error, isNotNull);
      expect(detail.verified, false);
    });
    test('logout cancels a pending private assignment reload', () async {
      final pending = Completer<AcceptedBooking>();
      detail = AssignmentDetailController(
          booking: assignment(),
          socket: socket,
          token: () async => null,
          load: (_) => pending.future);
      final read = detail.reload();
      socket.fire('session:ended');
      pending.complete(assignment(status: 'arrived'));
      await read;
      expect(detail.accessDenied, true);
      expect(detail.verified, false);
      expect(detail.booking.job['status'], 'accepted');
    });
  });
  test(
      'assigned opportunities cannot resurrect after racing HTTP or duplicate socket requests',
      () async {
    final socket = FakePresenceSocket(), pending = Completer<bool>();
    final o = OpportunityController(
        jobId: 'job-1', socket: socket, load: (_) => pending.future);
    final read = o.refresh();
    socket.fire('job:unavailable', {'jobId': 'other'});
    expect(o.loading, true);
    socket.fire('job:unavailable', {'jobId': 'job-1'});
    pending.complete(true);
    await read;
    expect(o.canBid, false);
    await o.refresh();
    expect(o.isOpen, false);
    o.dispose();
  });
  test('opportunity errors disable submit and retry confirms open state',
      () async {
    final socket = FakePresenceSocket();
    bool fail = true;
    final o = OpportunityController(
        jobId: 'job-1',
        socket: socket,
        load: (_) async {
          if (fail) throw const AssignmentFailure('offline');
          return true;
        });
    await o.refresh();
    expect(o.canBid, false);
    fail = false;
    await o.refresh();
    expect(o.canBid, true);
    socket.fire('session:ended');
    expect(o.canBid, false);
    o.dispose();
  });
  test('presence request recovery never resurrects an assigned opportunity',
      () async {
    final socket = FakePresenceSocket(), gps = FakeForegroundLocation();
    final p = MechanicPresenceController(
        socket: socket,
        gps: gps,
        token: () async => 'fixture',
        profile: () async => mechanicProfile(),
        loadRequests: () async => [requestJson()]);
    await p.initialize();
    await p.toggle();
    socket.fire('job:new_request', requestJson());
    expect(p.jobs.length, 1);
    p.invalidateOpportunity('job-1');
    socket.fire('job:new_request', requestJson());
    await p.refreshRequests();
    expect(p.jobs, isEmpty);
    p.dispose();
    await gps.close();
  });
}
