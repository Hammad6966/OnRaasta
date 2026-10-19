import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onraasta/models/booking_arguments.dart';
import 'package:onraasta/providers/review_form_controller.dart';
import 'package:onraasta/services/review_service.dart';
import 'package:onraasta/services/api_service.dart';
import 'package:onraasta/features/user/rate_review_screen.dart';
import 'package:onraasta/features/user/bidding_routes.dart';
import 'package:onraasta/features/user/mechanic_profile_view.dart';
import 'package:onraasta/features/mechanic/mechanic_ratings_screen.dart';
import 'package:onraasta/models/bid_model.dart';
import 'package:onraasta/core/widgets/mechanic_reviews_panel.dart';
import 'package:onraasta/core/widgets/onraasta_button.dart';
import 'assignment_fixtures.dart' as fixtures;
import 'bidding_fixtures.dart';

Map<String, dynamic> reviewPage(
        {int page = 1, bool empty = false, bool more = false}) =>
    {
      'mechanicId': 'mechanic-1',
      'rating': empty ? 0 : 4.0,
      'reviewCount': empty ? 0 : 1,
      'page': page,
      'limit': 10,
      'hasMore': more,
      'distribution': {'1': 0, '2': 0, '3': 0, '4': empty ? 0 : 1, '5': 0},
      'reviews': empty
          ? []
          : [
              {
                'stars': 4,
                'tags': ['Professional'],
                'comment': 'Real persisted review',
                'createdAt': '2026-10-17T10:00:00.000Z'
              }
            ],
    };

class FakeReviews extends ReviewService {
  AcceptedBooking saved = fixtures.assignment(status: 'completed');
  int reads = 0, posts = 0;
  Future<void> Function()? onSubmit;
  Future<AcceptedBooking> Function()? onLoad;
  @override
  Future<AcceptedBooking> assignment(String id) async {
    reads++;
    return onLoad == null ? saved : await onLoad!();
  }

  @override
  Future<void> submit(String jobId, String mechanicId, int stars,
      List<String> tags, String comment) async {
    posts++;
    await onSubmit?.call();
  }
}

ReviewFormController form(ReviewService s,
        {String job = 'job-1',
        String mechanic = 'mechanic-1',
        String bid = 'bid-1'}) =>
    ReviewFormController(
        jobId: job, mechanicId: mechanic, bidId: bid, service: s);
AcceptedBooking reviewed() {
  final json = fixtures.assignmentJson(status: 'completed');
  (json['job'] as Map)['review'] = {
    'stars': 4,
    'comment': 'Saved',
    'createdAt': '2026-10-17T10:00:00.000Z'
  };
  return AcceptedBooking.fromAssignment(json);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(
        {'access_token': 'fixture-access'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final name = utf8.decode(message!.buffer.asUint8List());
      if (name == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage({
          for (final font in [
            'DMSans-Regular.ttf',
            'DMSans-Medium.ttf',
            'DMSans-SemiBold.ttf',
            'Syne-Bold.ttf',
            'Syne-SemiBold.ttf'
          ])
            font: [
              {'asset': font}
            ]
        });
      }
      return ByteData(0);
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', null));
  test('authoritative completed booking enables exact job review', () async {
    final s = FakeReviews();
    final f = form(s);
    expect(f.canSubmit, false);
    await f.reload();
    expect(f.canSubmit, true);
    expect(f.booking!.jobId, 'job-1');
    expect(f.booking!.bid.mechanicName, 'Ali Khan');
    expect(await f.submit(5, ['Professional'], 'Great'), true);
    expect(s.reads, 2);
    expect(f.alreadyReviewed, true);
    f.dispose();
  });
  for (final status in [
    'accepted',
    'en_route',
    'arrived',
    'in_progress',
    'cancelled'
  ]) {
    test('$status never permits reviewing', () async {
      final s = FakeReviews()..saved = fixtures.assignment(status: status);
      final c = form(s);
      await c.reload();
      expect(c.canSubmit, false);
      expect(await c.submit(5, [], ''), false);
      expect(s.posts, 0);
      c.dispose();
    });
  }
  test('assignment identity mismatch and missing identifiers fail closed',
      () async {
    for (final args in [
      {'job': 'other-job'},
      {'mechanic': 'other-mechanic'},
      {'bid': 'other-bid'},
      {'job': ''}
    ]) {
      final c = form(FakeReviews(),
          job: args['job'] ?? 'job-1',
          mechanic: args['mechanic'] ?? 'mechanic-1',
          bid: args['bid'] ?? 'bid-1');
      await c.reload();
      expect(c.canSubmit, false);
      expect(c.error, isNotNull);
      c.dispose();
    }
  });
  test('duplicate submission prevented until confirmed response', () async {
    final hold = Completer<void>(), s = FakeReviews();
    s.onSubmit = () => hold.future;
    final c = form(s);
    await c.reload();
    final pending = c.submit(5, [], '');
    await Future<void>.delayed(Duration.zero);
    expect(c.submitting, true);
    expect(c.submitted, false);
    expect(await c.submit(5, [], ''), false);
    expect(s.posts, 1);
    hold.complete();
    expect(await pending, true);
    expect(c.submitted, true);
    c.dispose();
  });
  test('completion is rechecked at submission time', () async {
    final s = FakeReviews();
    final f = form(s);
    await f.reload();
    s.saved = fixtures.assignment(status: 'cancelled');
    expect(await f.submit(5, [], ''), false);
    expect(s.posts, 0);
    expect(f.canSubmit, false);
    f.dispose();
  });
  test('already reviewed jobs remain unavailable after reopening', () async {
    final s = FakeReviews()..saved = reviewed();
    final f = form(s);
    await f.reload();
    expect(f.alreadyReviewed, true);
    expect(f.canSubmit, false);
    expect(await f.submit(5, [], ''), false);
    f.dispose();
  });
  test('409 reloads existing review without false new submission success',
      () async {
    final s = FakeReviews();
    s.onSubmit = () async {
      s.saved = reviewed();
      throw const ReviewFailure('Already reviewed', 409);
    };
    final c = form(s);
    await c.reload();
    expect(await c.submit(5, [], ''), false);
    expect(c.alreadyReviewed, true);
    expect(c.submitted, false);
    expect(c.error, null);
    c.dispose();
  });
  test('network failure preserves retry eligibility and never reports success',
      () async {
    final s = FakeReviews();
    s.onSubmit = () async => throw const ReviewFailure('Network error');
    final c = form(s);
    await c.reload();
    expect(await c.submit(5, ['Friendly'], 'Keep my input'), false);
    expect(c.submitted, false);
    expect(c.canSubmit, true);
    s.onSubmit = null;
    expect(await c.submit(5, ['Friendly'], 'Keep my input'), true);
    c.dispose();
  });
  test('stars and oversized comments rejected before request', () async {
    final s = FakeReviews();
    final f = form(s);
    await f.reload();
    expect(await f.submit(0, [], ''), false);
    expect(await f.submit(6, [], ''), false);
    expect(await f.submit(4, [], 'x' * 301), false);
    expect(s.posts, 0);
    f.dispose();
  });
  test('malformed navigation or noncompleted booking is rejected safely', () {
    for (final value in [
      null,
      {},
      {'jobId': 'wrong'},
      fixtures.assignment(status: 'cancelled'),
      fixtures.assignment(status: 'in_progress')
    ]) {
      expect(rateReviewPage(value), isA<InvalidBiddingArgumentsPage>());
    }
    final page = rateReviewPage(fixtures.assignment(status: 'completed'))
        as RateReviewScreen;
    expect(page.bid['jobId'], 'job-1');
    expect(page.bid['mechanicId'], 'mechanic-1');
    expect(page.bid['bidId'], 'bid-1');
  });
  group('shared authenticated API', () {
    late BiddingAdapter a;
    late HttpClientAdapter old;
    setUp(() {
      a = BiddingAdapter();
      old = ApiService.instance.dio.httpClientAdapter;
      ApiService.instance.dio.httpClientAdapter = a;
    });
    tearDown(() => ApiService.instance.dio.httpClientAdapter = old);
    test(
        'submission uses access_token interceptor and only supported review fields',
        () async {
      a.respond = (o) async => apiResponse({
            'jobId': 'job-1',
            'mechanicId': 'mechanic-1',
            'review': {'stars': 5, 'createdAt': '2026-10-17T10:00:00Z'},
            'reputation': {'rating': 5, 'reviewCount': 1}
          });
      await ReviewService.instance
          .submit('job-1', 'mechanic-1', 5, ['Friendly'], ' Good ');
      final r = a.requests.single;
      expect(r.headers['Authorization'], 'Bearer fixture-access');
      expect(r.path, '/jobs/job-1/review');
      expect(r.data, {
        'stars': 5,
        'tags': ['Friendly'],
        'comment': 'Good'
      });
    });
    for (final code in [400, 401, 403, 404, 409, 500]) {
      test('HTTP $code produces actionable failure', () async {
        a.respond = (o) async => apiResponse({}, status: code, success: false);
        await expectLater(
            ReviewService.instance.submit('job-1', 'mechanic-1', 5, [], ''),
            throwsA(
                isA<ReviewFailure>().having((e) => e.status, 'status', code)));
      });
    }
    test('malformed success cannot confirm a review', () async {
      for (final data in [
        {},
        {'jobId': 'foreign-job'},
        {'review': 'malformed'}
      ]) {
        a.respond = (o) async => apiResponse(data);
        await expectLater(
            ReviewService.instance.submit('job-1', 'mechanic-1', 5, [], ''),
            throwsA(isA<ReviewFailure>()));
      }
    });
    test('real review page parses distribution and bounded pagination',
        () async {
      a.respond = (o) async => apiResponse(reviewPage(page: 2));
      final p = await ReviewService.instance.reviews('mechanic-1', page: 2);
      expect(p.count, 1);
      expect(p.rating, 4);
      expect(p.distribution[4], 1);
      expect(p.reviews.single['comment'], 'Real persisted review');
      expect(
          a.requests.single.uri.queryParameters, {'page': '2', 'limit': '10'});
    });
    test(
        'zero review page is honest and wrong mechanic/malformed summary rejected',
        () async {
      a.respond = (o) async => apiResponse(reviewPage(empty: true));
      final p = await ReviewService.instance.reviews('mechanic-1');
      expect(p.rating, 0);
      expect(p.reviews, isEmpty);
      for (final data in [
        reviewPage()..['mechanicId'] = 'other',
        reviewPage()..['reviewCount'] = 55,
        {}
      ]) {
        a.respond = (o) async => apiResponse(data);
        await expectLater(ReviewService.instance.reviews('mechanic-1'),
            throwsA(isA<ReviewFailure>()));
      }
    });
  });
  testWidgets(
      'review form shows verification, real name, retry and retained text',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = FakeReviews();
    s.onSubmit = () async => throw const ReviewFailure('Network unavailable');
    final c = form(s);
    await tester.pumpWidget(MaterialApp(
        home: RateReviewScreen(bid: const {
      'jobId': 'job-1',
      'mechanicId': 'mechanic-1',
      'bidId': 'bid-1'
    }, controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('Ali Khan'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.star_border_rounded).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Keep my comments');
    await tester.pump();
    await tester.ensureVisible(find.text('Submit Review'));
    await tester.tap(find.text('Submit Review'));
    await tester.pumpAndSettle();
    expect(s.posts, 1);
    expect(find.text('Keep my comments'), findsOneWidget);
    expect(c.submitted, false);
    expect(find.text('Network unavailable'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'review form waits for authoritative read and indicates already reviewed',
      (tester) async {
    final pending = Completer<AcceptedBooking>(), s = FakeReviews();
    s.onLoad = () => pending.future;
    final c = form(s);
    await tester.pumpWidget(
        MaterialApp(home: RateReviewScreen(bid: const {}, controller: c)));
    await tester.pump();
    expect(
        tester.widget<OnRaastaButton>(find.byType(OnRaastaButton)).isDisabled,
        true);
    pending.complete(reviewed());
    await tester.pumpAndSettle();
    expect(find.text('Review submitted'), findsOneWidget);
    expect(
        tester.widget<OnRaastaButton>(find.byType(OnRaastaButton)).isDisabled,
        true);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'shared ratings panel loads real cards, empty state, errors and retry',
      (tester) async {
    final adapter = BiddingAdapter(), dio = Dio();
    dio.httpClientAdapter = adapter;
    final service = ReviewService(client: dio);
    adapter.respond = (o) async => apiResponse(reviewPage(empty: true));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: MechanicReviewsPanel(
                    mechanicId: 'mechanic-1', service: service)))));
    await tester.pumpAndSettle();
    expect(find.text('No verified reviews yet.'), findsOneWidget);
    expect(find.text('0 verified reviews'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    adapter.respond = (o) async => apiResponse({}, status: 500, success: false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: MechanicReviewsPanel(
                    mechanicId: 'mechanic-1', service: service)))));
    await tester.pumpAndSettle();
    expect(find.text('Retry reviews'), findsOneWidget);
    adapter.respond = (o) async => apiResponse(reviewPage());
    await tester.tap(find.text('Retry reviews'));
    await tester.pumpAndSettle();
    expect(find.text('Verified customer'), findsOneWidget);
    expect(find.text('Real persisted review'), findsOneWidget);
    expect(find.text('2026-10-17'), findsOneWidget);
    expect(find.text('Hamza K.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    dio.close();
  });
  testWidgets('server confirmed success returns to existing driver home',
      (tester) async {
    final s = FakeReviews();
    final f = form(s);
    final router = GoRouter(initialLocation: '/review', routes: [
      GoRoute(
          path: '/review',
          builder: (context, state) =>
              RateReviewScreen(bid: const {}, controller: f)),
      GoRoute(
          path: '/user-home',
          builder: (context, state) =>
              const Scaffold(body: Text('Driver home')))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_border_rounded).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit Review'));
    await tester.tap(find.text('Submit Review'));
    await tester.pumpAndSettle();
    expect(find.text('Driver home'), findsOneWidget);
    expect(s.posts, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'driver profile displays real reputation and reviews without changing selected bid',
      (tester) async {
    final adapter = BiddingAdapter(),
        old = ApiService.instance.dio.httpClientAdapter;
    ApiService.instance.dio.httpClientAdapter = adapter;
    addTearDown(() => ApiService.instance.dio.httpClientAdapter = old);
    adapter.respond = (o) async => apiResponse(o.path.contains('/reviews')
        ? reviewPage()
        : [bidJson(populated: true)]);
    await tester.pumpWidget(MaterialApp(
        home: MechanicProfileView(
            selection: BidSelection(
                job: savedJob(),
                bid: BidModel.fromJson(bidJson(populated: true))))));
    await tester.pumpAndSettle();
    expect(find.text('Real persisted review'), findsOneWidget);
    expect(find.text('1 verified reviews'), findsOneWidget);
    expect(find.text('4.7'), findsNothing);
    expect(find.text('4.0'), findsWidgets);
    expect(find.textContaining('Accept This Bid'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'mechanic ratings resolves own profile and removes fabricated identities',
      (tester) async {
    final adapter = BiddingAdapter(),
        old = ApiService.instance.dio.httpClientAdapter;
    ApiService.instance.dio.httpClientAdapter = adapter;
    addTearDown(() => ApiService.instance.dio.httpClientAdapter = old);
    adapter.respond = (o) async => apiResponse(o.path == '/mechanics/profile'
        ? {'_id': 'mechanic-1', 'isApproved': true}
        : reviewPage(empty: true));
    await tester.pumpWidget(const MaterialApp(home: MechanicRatingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('My Ratings'), findsOneWidget);
    expect(find.text('No verified reviews yet.'), findsOneWidget);
    expect(find.text('Hamza K.'), findsNothing);
    expect(adapter.requests.map((o) => o.path), contains('/mechanics/profile'));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('load more uses next page and retains existing review cards',
      (tester) async {
    final adapter = BiddingAdapter(), dio = Dio();
    dio.httpClientAdapter = adapter;
    adapter.respond = (o) async {
      final second = o.uri.queryParameters['page'] == '2';
      final json = reviewPage(page: second ? 2 : 1, more: !second);
      json['reviewCount'] = 2;
      json['distribution'] = {'1': 0, '2': 0, '3': 0, '4': 2, '5': 0};
      (json['reviews'] as List).single['comment'] =
          second ? 'Second persisted review' : 'First persisted review';
      return apiResponse(json);
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: MechanicReviewsPanel(
                    mechanicId: 'mechanic-1',
                    service: ReviewService(client: dio))))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Load more reviews'));
    await tester.tap(find.text('Load more reviews'));
    await tester.pumpAndSettle();
    expect(find.text('First persisted review'), findsOneWidget);
    expect(find.text('Second persisted review'), findsOneWidget);
    expect(find.text('Load more reviews'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    dio.close();
  });
}
