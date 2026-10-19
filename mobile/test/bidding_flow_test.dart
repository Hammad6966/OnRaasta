import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onraasta/models/bid_model.dart';
import 'package:onraasta/models/booking_arguments.dart';
import 'package:onraasta/providers/job_provider.dart';
import 'package:onraasta/services/api_service.dart';
import 'package:onraasta/services/bidding_service.dart';
import 'bidding_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Shared bid parsing and navigation', () {
    test(
        'overflowing or nonfinite malformed prices never crash or enable acceptance',
        () {
      final enormous = BidModel.fromJson(bidJson()
        ..addAll(
            {'labourCost': 1e308, 'partsCost': 1e308, 'totalCost': 1e308}));
      expect(enormous.canAccept, false);
      final nonfinite =
          BidModel.fromJson(bidJson()..['totalCost'] = double.nan);
      expect(nonfinite.totalCost, null);
      expect(nonfinite.canAccept, false);
    });
    test('populated mechanic preserves distinct profile and user identities',
        () {
      final bid = BidModel.fromJson(bidJson(populated: true));
      expect([bid.bidId, bid.jobId, bid.mechanicId, bid.mechanicUserId],
          ['bid-1', 'job-1', 'mechanic-1', 'mechanic-user-1']);
      expect(bid.mechanicName, 'Ali Khan');
      expect(bid.skills, ['Battery', 'Electrical']);
      expect(bid.rating, 4.7);
      expect(bid.totalJobs, 21);
      expect(bid.isApproved, true);
      expect(
          [bid.labourCost, bid.partsCost, bid.totalCost, bid.eta, bid.status],
          [900.5, 200.25, 1100.75, 12, 'pending']);
    });
    test('socket payload uses the same parser', () {
      final bid = BidModel.fromJson(socketBid());
      expect(bid.bidId, 'bid-1');
      expect(bid.jobId, 'job-1');
      expect(bid.mechanicName, 'Ali Khan');
      expect(bid.rating, 4.7);
      expect(bid.isNew, true);
      expect(bid.mechanicUserId, null);
    });
    test('missing optional and malformed optional values are honest', () {
      final bid = BidModel.fromJson({
        'bidId': 'b',
        'jobId': 'j',
        'mechanicId': 'm',
        'skills': [3, 'Battery'],
        'rating': 'bad',
        'eta': 1.5
      });
      expect(bid.rating, null);
      expect(bid.eta, null);
      expect(bid.isApproved, null);
      expect(bid.skills, ['Battery']);
      expect(bid.totalCost, null);
      expect(bid.canAccept, false);
      expect(bid.mechanicName, 'Name unavailable');
      expect(bid.reviewCount, null);
    });
    for (final field in ['_id', 'jobId', 'mechanicId']) {
      test('missing $field is rejected', () {
        expect(() => BidModel.fromJson(bidJson()..remove(field)),
            throwsFormatException);
      });
    }
    test('profile payload preserves full job and selected bid', () {
      final selection =
          BidSelection(job: savedJob(), bid: BidModel.fromJson(bidJson()));
      expect(BidSelection.tryParse(selection), same(selection));
      expect(selection.job['photos'], savedJob()['photos']);
      expect(selection.job['vehicleId'], 'vehicle-1');
      expect(
          BidSelection.tryParse({'job': savedJob(), 'bid': bidJson()})
              ?.bid
              .bidId,
          'bid-1');
    });
    test('foreign or malformed navigation cannot create a booking', () {
      for (final extra in [
        null,
        'bad',
        5,
        {},
        {'job': savedJob(), 'bid': bidJson(job: 'foreign')}
      ]) {
        expect(BidSelection.tryParse(extra), null);
        expect(AcceptedBooking.tryParse(extra), null);
      }
      expect(AcceptedBooking.tryParse({'job': savedJob(), 'bid': bidJson()}),
          null);
    });
    test('confirmed booking preserves all IDs and exact prices', () {
      final booking = AcceptedBooking(
          job: savedJob(accepted: true),
          bid: BidModel.fromJson(bidJson(status: 'accepted')));
      expect(booking.bid.jobId, booking.job['_id']);
      expect(booking.bid.bidId, booking.job['acceptedBidId']);
      expect(booking.bid.mechanicId, booking.job['mechanicId']);
      expect(booking.bid.priceLabel, 'PKR 1100.75');
      expect(AcceptedBooking.tryParse(booking), same(booking));
    });
    test('inconsistent assignment or price cannot navigate', () {
      expect(
          () => AcceptedBooking(
              job: savedJob(accepted: true)..['mechanicId'] = 'foreign',
              bid: BidModel.fromJson(bidJson(status: 'accepted'))),
          throwsFormatException);
      expect(
          () => AcceptedBooking(
              job: savedJob(accepted: true),
              bid: BidModel.fromJson(
                  bidJson(status: 'accepted')..['totalCost'] = 1)),
          throwsFormatException);
    });
  });

  group('Bid discovery reconciliation', () {
    test('API/socket dedup and enrichment', () async {
      final state = JobBidsController(
          jobId: 'job-1',
          load: (_) async => [BidModel.fromJson(bidJson(populated: true))]);
      addTearDown(state.dispose);
      state.receive(socketBid());
      await state.refresh();
      state.receive(socketBid());
      expect(state.bids, hasLength(1));
      expect(state.bids.single.mechanicUserId, 'mechanic-user-1');
    });
    test('foreign jobs and malformed payloads ignored', () async {
      final state = JobBidsController(
          jobId: 'job-1',
          load: (_) async => [BidModel.fromJson(bidJson(job: 'foreign'))]);
      addTearDown(state.dispose);
      state.receive(socketBid(job: 'foreign'));
      state.receive('bad');
      await state.refresh();
      expect(state.bids, isEmpty);
    });
    test('incoming bids before and during first load survive the snapshot',
        () async {
      final response = Completer<List<BidModel>>();
      final state =
          JobBidsController(jobId: 'job-1', load: (_) => response.future);
      addTearDown(state.dispose);
      state.receive(socketBid(id: 'before'));
      final request = state.refresh();
      state.receive(socketBid(id: 'during'));
      response.complete([]);
      await request;
      expect(state.bids.map((b) => b.bidId), containsAll(['before', 'during']));
      expect(state.loading, false);
    });
    test('request failure preserves incoming offers and reports error',
        () async {
      final state = JobBidsController(
          jobId: 'job-1',
          load: (_) async => throw const BidFlowException('Offline'));
      addTearDown(state.dispose);
      state.receive(socketBid());
      await state.refresh();
      expect(state.bids, hasLength(1));
      expect(state.error, 'Offline');
      expect(state.loading, false);
    });
    test('older HTTP requests cannot overwrite newer refreshes', () async {
      final first = Completer<List<BidModel>>(),
          second = Completer<List<BidModel>>();
      var calls = 0;
      final state = JobBidsController(
          jobId: 'job-1',
          load: (_) => calls++ == 0 ? first.future : second.future);
      addTearDown(state.dispose);
      final a = state.refresh(), b = state.refresh();
      second.complete([BidModel.fromJson(bidJson(status: 'accepted'))]);
      await b;
      first.complete([BidModel.fromJson(bidJson())]);
      await a;
      expect(state.bids.single.status, 'accepted');
    });
    test('status reconciliation does not regress accepted or declined offers',
        () async {
      final state = JobBidsController(
          jobId: 'job-1',
          load: (_) async => [BidModel.fromJson(bidJson(status: 'declined'))]);
      addTearDown(state.dispose);
      state.receive(socketBid());
      await state.refresh();
      state.receive(socketBid());
      expect(state.bids.single.status, 'declined');
    });
    test(
        'late socket bid enriches without replacing newer terminal HTTP status',
        () async {
      final response = Completer<List<BidModel>>();
      final state =
          JobBidsController(jobId: 'job-1', load: (_) => response.future);
      addTearDown(state.dispose);
      final request = state.refresh();
      state.receive(socketBid());
      response.complete(
          [BidModel.fromJson(bidJson(populated: true, status: 'accepted'))]);
      await request;
      expect(state.bids.single.status, 'accepted');
      expect(state.bids.single.mechanicUserId, 'mechanic-user-1');
    });
    test('disposed controller ignores a late request', () async {
      final response = Completer<List<BidModel>>();
      final state =
          JobBidsController(jobId: 'job-1', load: (_) => response.future);
      final request = state.refresh();
      state.dispose();
      response.complete([]);
      await request;
    });
  });

  group('Authenticated acceptance', () {
    late BiddingAdapter adapter;
    late BiddingService service;
    late HttpClientAdapter original;
    final selection = BidSelection(
        job: savedJob(), bid: BidModel.fromJson(bidJson(populated: true)));
    setUp(() {
      FlutterSecureStorage.setMockInitialValues(
          {'access_token': 'test-access-token'});
      original = ApiService.instance.dio.httpClientAdapter;
      adapter = BiddingAdapter();
      ApiService.instance.dio.httpClientAdapter = adapter;
      service = BiddingService(dio: ApiService.instance.dio);
      adapter.respond = (request) async => apiResponse(request.method == 'PATCH'
          ? bidJson(status: 'accepted')
          : savedJob(accepted: true));
    });
    tearDown(() {
      ApiService.instance.dio.httpClientAdapter = original;
    });
    test('bid listing uses the saved job ID and filters foreign records',
        () async {
      adapter.respond = (_) async =>
          apiResponse([bidJson(populated: true), bidJson(job: 'foreign')]);
      final bids = await service.loadBids('job-1');
      expect(bids, hasLength(1));
      expect(bids.single.mechanicId, 'mechanic-1');
      expect(adapter.requests.single.queryParameters, {'jobId': 'job-1'});
      expect(adapter.requests.single.headers['Authorization'],
          'Bearer test-access-token');
    });
    test('malformed listing reports failure instead of an invented empty list',
        () async {
      adapter.respond = (_) async => apiResponse({'not': 'a list'});
      await expectLater(
          service.loadBids('job-1'), throwsA(isA<BidFlowException>()));
    });
    test('job confirmation failure can recover without repeating acceptance',
        () async {
      adapter.respond = (r) async => r.method == 'PATCH'
          ? apiResponse(bidJson(status: 'accepted'))
          : apiResponse(null, status: 503, success: false);
      await expectLater(
          service.accept(selection), throwsA(isA<BidFlowException>()));
      adapter.respond = (r) async => apiResponse(r.path == '/bids'
          ? [bidJson(populated: true, status: 'accepted')]
          : savedJob(accepted: true));
      final refreshed = (await service.loadBids('job-1')).single;
      final booking =
          await service.accept(BidSelection(job: savedJob(), bid: refreshed));
      expect(booking?.bid.bidId, 'bid-1');
      expect(adapter.requests.where((r) => r.method == 'PATCH'), hasLength(1));
    });
    test('a different accepted assignment never enters tracking', () async {
      adapter.respond = (r) async => apiResponse(r.method == 'PATCH'
          ? bidJson(status: 'accepted')
          : (savedJob(accepted: true)..['acceptedBidId'] = 'other-bid'));
      await expectLater(
          service.accept(selection), throwsA(isA<BidFlowException>()));
    });
    test('uses secure access token and confirms authoritative job and costs',
        () async {
      final booking = (await service.accept(selection))!;
      expect(adapter.requests.map((r) => r.path),
          ['/bids/bid-1/accept', '/jobs/job-1']);
      expect(
          adapter.requests.every(
              (r) => r.headers['Authorization'] == 'Bearer test-access-token'),
          true);
      expect(booking.bid.mechanicName, 'Ali Khan');
      expect(booking.bid.totalCost, 1100.75);
      expect(booking.job['aiDiagnosis'], savedJob()['aiDiagnosis']);
    });
    test('uses server-confirmed prices rather than the displayed old price',
        () async {
      adapter.respond = (request) async => apiResponse(request.method == 'PATCH'
          ? (bidJson(status: 'accepted')
            ..addAll({'labourCost': 1000, 'partsCost': 300, 'totalCost': 1300}))
          : savedJob(accepted: true));
      final booking = (await service.accept(selection))!;
      expect([
        booking.bid.labourCost,
        booking.bid.partsCost,
        booking.bid.totalCost
      ], [
        1000,
        300,
        1300
      ]);
    });
    test('duplicate accept calls cause one PATCH', () async {
      final response = Completer<ResponseBody>();
      adapter.respond = (r) => r.method == 'PATCH'
          ? response.future
          : Future.value(apiResponse(savedJob(accepted: true)));
      final first = service.accept(selection);
      expect(await service.accept(selection), null);
      response.complete(apiResponse(bidJson(status: 'accepted')));
      await first;
      expect(adapter.requests.where((r) => r.method == 'PATCH'), hasLength(1));
    });
    for (final status in [401, 403, 404, 409]) {
      test('HTTP $status is a controlled failure and releases the guard',
          () async {
        adapter.respond =
            (_) async => apiResponse(null, status: status, success: false);
        await expectLater(
            service.accept(selection),
            throwsA(isA<BidFlowException>()
                .having((e) => e.statusCode, 'status', status)));
        expect(
            adapter.requests.where((r) => r.path.startsWith('/jobs')), isEmpty);
        await expectLater(
            service.accept(selection), throwsA(isA<BidFlowException>()));
        expect(adapter.requests, hasLength(2));
      });
    }
    for (final status in ['declined', 'expired']) {
      test('$status bid cannot be accepted', () async {
        await expectLater(
            service.accept(BidSelection(
                job: savedJob(),
                bid: BidModel.fromJson(bidJson(status: status)))),
            throwsA(isA<BidFlowException>()));
        expect(adapter.requests, isEmpty);
      });
    }
    test('accepted bid resumes via authenticated reads without another PATCH',
        () async {
      adapter.respond = (r) async => apiResponse(r.path == '/bids'
          ? [bidJson(populated: true, status: 'accepted')]
          : savedJob(accepted: true));
      final booking = await service.accept(BidSelection(
          job: savedJob(),
          bid: BidModel.fromJson(bidJson(status: 'accepted'))));
      expect(booking?.bid.bidId, 'bid-1');
      expect(adapter.requests.every((r) => r.method == 'GET'), true);
    });
    for (final body in [
      null,
      'malformed',
      {},
      {'success': false},
      {'success': true, 'data': {}},
      {
        'success': true,
        'data': bidJson(status: 'accepted')..remove('totalCost')
      },
      {'success': true, 'data': bidJson(job: 'foreign', status: 'accepted')}
    ]) {
      test('malformed acceptance $body never navigates', () async {
        // Use a typed response to exercise malformed envelopes without relying on JSON decoding.
        final dio = Dio()
          ..interceptors.add(InterceptorsWrapper(
              onRequest: (options, handler) => handler
                  .resolve(Response(requestOptions: options, data: body))));
        await expectLater(BiddingService(dio: dio).accept(selection),
            throwsA(isA<BidFlowException>()));
      });
    }
  });
}
