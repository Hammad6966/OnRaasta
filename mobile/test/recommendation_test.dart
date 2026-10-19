import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onraasta/models/bid_model.dart';
import 'package:onraasta/models/booking_arguments.dart';
import 'package:onraasta/models/recommendation.dart';
import 'package:onraasta/providers/recommendation_controller.dart';
import 'package:onraasta/services/ai_service.dart';
import 'package:onraasta/services/auth_service.dart';
import 'package:onraasta/services/bidding_service.dart';
import 'package:onraasta/features/user/mechanics_found_screen.dart';
import 'package:onraasta/features/user/bidding_routes.dart';
import 'bidding_fixtures.dart';
import 'assignment_fixtures.dart' as assignments;

BidModel bid(
        {String id = 'bid-1',
        String name = 'Real Mechanic',
        double price = 1100.75,
        double? rating = 4.7,
        int? eta = 12,
        String status = 'pending',
        String job = 'job-1'}) =>
    BidModel.fromJson({
      ...bidJson(id: id, job: job, status: status),
      'mechanicId': {
        '_id': id == 'bid-1' ? 'mechanic-1' : 'mechanic-$id',
        'userId': {'_id': 'user-$id', 'name': name},
        'rating': rating,
        'skills': ['Battery']
      },
      'labourCost': price,
      'partsCost': 0,
      'totalCost': price,
      'eta': eta,
    });
Recommendation rankFor(BidModel b, {double skill = 1, double distance = 0}) {
  final components = {
    'skillMatch': skill,
    'distanceScore': (1 - distance / 15).clamp(0, 1).toDouble(),
    'ratingScore': (b.rating ?? 0) / 5,
    'priceScore': (1 - validBidTotal(b)! / 5000000).clamp(0, 1).toDouble()
  };
  final score = 0.35 * components['skillMatch']! +
      0.25 * components['distanceScore']! +
      0.25 * components['ratingScore']! +
      0.15 * components['priceScore']!;
  return Recommendation({
    'bidId': b.bidId,
    'mechanicId': b.mechanicId,
    'totalMinor': validBidTotal(b),
    'score': score,
    'components': components,
    'distanceKm': distance,
    'rating': b.rating,
    'skills': b.skills,
    'matchedSkills': skill == 1 ? ['Battery'] : []
  });
}

RecommendationPage ranking(List<Recommendation> rows,
    {String job = 'job-1', Duration lifetime = const Duration(minutes: 1)}) {
  final sorted = [...rows]..sort((a, b) => b.score.compareTo(a.score) != 0
      ? b.score.compareTo(a.score)
      : a.bidId.compareTo(b.bidId));
  return RecommendationPage(
      jobId: job, rankings: sorted, expiresAt: DateTime.now().add(lifetime));
}

class Ai extends AiService {
  int calls = 0;
  Future<RecommendationPage> Function()? read;
  List<Recommendation> rows = [];
  @override
  Future<RecommendationPage> recommendations(String jobId) async {
    calls++;
    return read == null ? ranking(rows, job: jobId) : await read!();
  }
}

class Offers extends BiddingService {
  List<BidModel> bids = [bid()];
  int accepts = 0, reads = 0;
  @override
  Future<List<BidModel>> loadBids(String jobId) async {
    reads++;
    return bids;
  }

  @override
  Future<AcceptedBooking?> accept(BidSelection selection) async {
    accepts++;
    return assignments.assignment();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Ai ai;
  late AuthService auth;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ai = Ai();
    auth = AuthService.forTesting(Dio());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final name = utf8.decode(message!.buffer.asUint8List());
      if (name == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage({
          'DMSans-Medium.ttf': [
            {'asset': 'DMSans-Medium.ttf'}
          ]
        });
      }
      return ByteData(0);
    });
  });
  tearDown(() {
    auth.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });
  RecommendationController controller(
          {Duration debounce = const Duration(days: 1)}) =>
      RecommendationController(
          jobId: 'job-1',
          load: ai.recommendations,
          auth: auth,
          debounce: debounce);
  test('recommended order follows server factors rather than highest rating',
      () {
    final skilled = bid(id: 'skill', rating: 1),
        rated = bid(id: 'rating', rating: 5);
    final ranks =
        ranking([rankFor(skilled), rankFor(rated, skill: 0)]).rankings;
    expect(sortedOffers([rated, skilled], 0, ranks).first.bidId, 'skill');
  });
  test('cheapest uses exact paisa with deterministic ties and unknowns last',
      () {
    final a = bid(id: 'a', price: 500.01),
        b = bid(id: 'b', price: 500),
        tie = bid(id: 'c', price: 500);
    final bad = BidModel.fromJson({...bidJson(id: 'bad'), 'totalCost': 0});
    expect(sortedOffers([a, tie, bad, b], 1).map((b) => b.bidId),
        ['b', 'c', 'a', 'bad']);
  });
  test('fastest keeps missing ETA after known values and stable ties', () {
    expect(
        sortedOffers([
          bid(id: 'z', eta: null),
          bid(id: 'b', eta: 8),
          bid(id: 'a', eta: 8)
        ], 2)
            .map((b) => b.bidId),
        ['a', 'b', 'z']);
  });
  test('fallback is stable bid ID order, never a fabricated rating ranking',
      () {
    expect(
        sortedOffers([bid(id: 'z', rating: 5), bid(id: 'a', rating: 1)], 0)
            .first
            .bidId,
        'a');
  });
  test('price helper rejects excess precision and component mismatch', () {
    expect(validBidTotal(bid(price: 500.01)), 50001);
    expect(validBidTotal(bid(price: 500.001)), isNull);
    expect(validBidTotal(BidModel.fromJson({...bidJson(), 'totalCost': 500})),
        isNull);
  });
  test('ranking maps exact bid/mechanic/price only', () async {
    final b = bid();
    final c = controller();
    addTearDown(c.dispose);
    c.updateBids([b]);
    ai.rows = [rankFor(b)];
    await c.refresh();
    expect(c.rankings.single.bidId, b.bidId);
    expect(c.rankings.single.distanceKm, 0);
    c.updateBids([bid(price: 1200)]);
    expect(c.rankings, isEmpty);
  });
  test('foreign job rankings are rejected without changing saved identity',
      () async {
    final c = controller();
    addTearDown(c.dispose);
    c.updateBids([bid()]);
    ai.read = () async => ranking([rankFor(bid())], job: 'foreign');
    await c.refresh();
    expect(c.jobId, 'job-1');
    expect(c.rankings, isEmpty);
    expect(c.error, isNotNull);
  });
  test('unknown bid IDs never create invented offer cards', () async {
    final c = controller();
    addTearDown(c.dispose);
    c.updateBids([bid()]);
    ai.rows = [rankFor(bid(id: 'foreign-bid'))];
    await c.refresh();
    expect(c.rankings, isEmpty);
  });
  test('expired snapshot is unavailable instead of claiming live eligibility',
      () async {
    final c = controller();
    addTearDown(c.dispose);
    c.updateBids([bid()]);
    ai.read = () async =>
        ranking([rankFor(bid())], lifetime: const Duration(seconds: -1));
    await c.refresh();
    expect(c.rankings, isEmpty);
    expect(c.error, isNotNull);
  });
  test('snapshot expiry clears prior score without inventing movement or rank',
      () async {
    final c = controller();
    addTearDown(c.dispose);
    c.updateBids([bid()]);
    ai.read = () async =>
        ranking([rankFor(bid())], lifetime: const Duration(milliseconds: 20));
    await c.refresh();
    expect(c.rankings, hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(c.rankings, isEmpty);
    expect(c.error, contains('expired'));
  });
  test('rapid live bid arrivals coalesce into one new ranking request',
      () async {
    final c = controller(debounce: const Duration(milliseconds: 5));
    addTearDown(c.dispose);
    c.updateBids([bid()]);
    c.updateBids([bid(), bid(id: 'second')]);
    c.updateBids([bid(), bid(id: 'second'), bid(id: 'third')]);
    ai.rows = [
      rankFor(bid()),
      rankFor(bid(id: 'second')),
      rankFor(bid(id: 'third'))
    ];
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(ai.calls, 1);
    expect(c.rankings.length, 3);
    c.updateBids([bid(), bid(id: 'second'), bid(id: 'third')]);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(ai.calls, 1);
  });
  test('new candidates invalidate old asynchronous response', () async {
    final old = Completer<RecommendationPage>(),
        fresh = Completer<RecommendationPage>();
    var reads = 0;
    ai.read = () => reads++ == 0 ? old.future : fresh.future;
    final c = controller();
    addTearDown(c.dispose);
    c.updateBids([bid()]);
    final first = c.refresh();
    c.updateBids([bid(), bid(id: 'new')]);
    final second = c.refresh();
    fresh.complete(ranking([rankFor(bid(id: 'new'))]));
    await second;
    old.complete(ranking([rankFor(bid())]));
    await first;
    expect(c.rankings.single.bidId, 'new');
  });
  test(
      'duplicate explicit refresh while request pending does not duplicate HTTP',
      () async {
    final gate = Completer<RecommendationPage>();
    ai.read = () => gate.future;
    final c = controller();
    addTearDown(c.dispose);
    c.updateBids([bid()]);
    final first = c.refresh();
    await c.refresh();
    expect(ai.calls, 1);
    gate.complete(ranking([rankFor(bid())]));
    await first;
  });
  test('temporary scorer failure leaves real bids usable and supports retry',
      () async {
    final b = bid();
    final c = controller();
    addTearDown(c.dispose);
    c.updateBids([b]);
    ai.read = () async =>
        throw const BidFlowException('Recommendations unavailable', 503);
    await c.refresh();
    expect(c.rankings, isEmpty);
    expect(b.canAccept, true);
    ai.read = null;
    ai.rows = [rankFor(b)];
    await c.refresh();
    expect(c.error, isNull);
    expect(c.rankings.single.bidId, b.bidId);
  });
  test('logout ignores late ranking and clears account-bound state', () async {
    final gate = Completer<RecommendationPage>();
    ai.read = () => gate.future;
    final c = controller();
    addTearDown(c.dispose);
    c.updateBids([bid()]);
    final pending = c.refresh();
    await auth.clearTokens();
    gate.complete(ranking([rankFor(bid())]));
    await pending;
    expect(c.rankings, isEmpty);
    expect(c.loading, false);
  });
  for (final code in [401, 403, 404, 409, 503]) {
    test(
        'private recommendation HTTP $code is recoverable and no successful rank is invented',
        () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://fixture.test'));
      final adapter = BiddingAdapter();
      dio.httpClientAdapter = adapter;
      adapter.respond = (_) async =>
          ResponseBody.fromString('{"success":false}', code, headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
      await expectLater(
          AiService(client: dio).recommendations('job-1'),
          throwsA(isA<BidFlowException>()
              .having((e) => e.statusCode, 'HTTP status', code)));
      expect(adapter.requests.single.path, '/jobs/job-1/recommendations');
      expect(adapter.requests.single.queryParameters, isEmpty);
    });
  }
  test('invalid score units cannot become recommendations', () {
    expect(
        () => Recommendation({
              'bidId': 'bid-1',
              'mechanicId': 'mechanic-1',
              'totalMinor': 50000,
              'score': 9
            }),
        throwsFormatException);
  });
  test(
      'route keys isolate different saved jobs without changing navigation structure',
      () {
    expect(mechanicsFoundPage({'_id': 'one'}).key, const ValueKey('one'));
    expect(mechanicsFoundPage({'_id': 'two'}).key, const ValueKey('two'));
  });
  Future<void> open(WidgetTester tester, Offers offers) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MechanicsFoundScreen(job: savedJob(), bidding: offers, ai: ai)));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Recommended renders server order, real distance and rules explanation',
      (tester) async {
    final offers = Offers()
      ..bids = [
        bid(id: 'high-rating', name: 'High Rating', rating: 5),
        bid(id: 'skilled', name: 'Skilled Mechanic', rating: 1)
      ];
    ai.rows = [rankFor(offers.bids[0], skill: 0), rankFor(offers.bids[1])];
    await open(tester, offers);
    expect(tester.getTopLeft(find.text('Skilled Mechanic')).dy,
        lessThan(tester.getTopLeft(find.text('High Rating')).dy));
    expect(find.textContaining('rules score'), findsWidgets);
    expect(
        find.textContaining('straight-line (presence snapshot)'), findsWidgets);
    await finish(tester);
  });
  testWidgets('tab switches preserve offers and do not refetch rankings',
      (tester) async {
    final offers = Offers()
      ..bids = [
        bid(id: 'price', name: 'Cheapest Offer', price: 500, eta: 20),
        bid(id: 'eta', name: 'Fastest Offer', price: 1500, eta: 2)
      ];
    ai.rows = offers.bids.map(rankFor).toList();
    await open(tester, offers);
    final calls = ai.calls;
    await tester.tap(find.text('Cheapest'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Cheapest Offer')).dy,
        lessThan(tester.getTopLeft(find.text('Fastest Offer')).dy));
    await tester.tap(find.text('Fastest'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Fastest Offer')).dy,
        lessThan(tester.getTopLeft(find.text('Cheapest Offer')).dy));
    expect(ai.calls, calls);
    await finish(tester);
  });
  testWidgets('service unavailable keeps offers visible and a retry path',
      (tester) async {
    final offers = Offers();
    ai.read = () async => throw const BidFlowException(
        'Recommendations unavailable. Offers shown in bid ID order.', 503);
    await open(tester, offers);
    expect(find.text('Real Mechanic'), findsOneWidget);
    expect(find.text('Accept Bid'), findsOneWidget);
    expect(find.text('Retry Ranking'), findsOneWidget);
    expect(find.textContaining('rules score'), findsNothing);
    ai.read = null;
    ai.rows = [rankFor(offers.bids.single)];
    await tester.tap(find.text('Retry Ranking'));
    await tester.pumpAndSettle();
    expect(find.textContaining('rules score'), findsOneWidget);
    await finish(tester);
  });
  testWidgets(
      'fallback does not block typed profile navigation or successful acceptance',
      (tester) async {
    final offers = Offers();
    ai.read = () async =>
        throw const BidFlowException('Recommendations unavailable', 503);
    BidSelection? profile;
    AcceptedBooking? accepted;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) =>
              MechanicsFoundScreen(job: savedJob(), bidding: offers, ai: ai)),
      GoRoute(
          path: '/mechanic-profile',
          builder: (_, state) {
            profile = state.extra as BidSelection;
            return const Scaffold(body: Text('Profile destination'));
          }),
      GoRoute(
          path: '/live-tracking',
          builder: (_, state) {
            accepted = state.extra as AcceptedBooking;
            return const Scaffold(body: Text('Tracking destination'));
          })
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View Profile'));
    await tester.pumpAndSettle();
    expect(profile!.bid.bidId, 'bid-1');
    expect(profile!.job['_id'], 'job-1');
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept Bid'));
    await tester.pumpAndSettle();
    expect(offers.accepts, 1);
    expect(accepted!.jobId, 'job-1');
    expect(accepted!.bid.bidId, 'bid-1');
    await finish(tester);
    router.dispose();
  });
  test('assignment/status invalidation immediately discards old rankings',
      () async {
    final c = controller();
    addTearDown(c.dispose);
    c.updateBids([bid()]);
    ai.rows = [rankFor(bid())];
    await c.refresh();
    expect(c.rankings, isNotEmpty);
    c.invalidate();
    expect(c.rankings, isEmpty);
    expect(c.error, contains('changed'));
  });
}
