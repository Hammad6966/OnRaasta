import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// Existing Maps platform interface isolates native map rendering in widget tests.
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:onraasta/core/widgets/onraasta_button.dart';
import 'package:onraasta/features/user/bidding_routes.dart';
import 'package:onraasta/features/user/mechanic_profile_view.dart';
import 'package:onraasta/features/user/mechanics_found_screen.dart';
import 'package:onraasta/models/bid_model.dart';
import 'package:onraasta/models/booking_arguments.dart';
import 'package:onraasta/services/api_service.dart';
import 'package:onraasta/services/socket_service.dart';
import 'bidding_fixtures.dart';

class _MapPlatform extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) =>
      const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BiddingAdapter adapter;
  late HttpClientAdapter originalAdapter;
  late GoogleMapsFlutterPlatform originalMaps;
  GoRouter? router;
  AcceptedBooking? received;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(
        {}); // No network socket in these UI fixtures.
    originalAdapter = ApiService.instance.dio.httpClientAdapter;
    adapter = BiddingAdapter();
    ApiService.instance.dio.httpClientAdapter = adapter;
    originalMaps = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = _MapPlatform();
    received = null;
    adapter.respond = (request) async => apiResponse(request.path == '/bids'
        ? [bidJson(populated: true)]
        : request.method == 'PATCH'
            ? bidJson(status: 'accepted')
            : savedJob(accepted: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final name = utf8.decode(message!.buffer.asUint8List());
      if (name == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage({
          'DMSans-Medium.ttf': [
            {'asset': 'DMSans-Medium.ttf'}
          ],
        });
      }
      return ByteData(0);
    });
  });
  tearDown(() {
    router?.dispose();
    router = null;
    SocketService().disconnect();
    ApiService.instance.dio.httpClientAdapter = originalAdapter;
    GoogleMapsFlutterPlatform.instance = originalMaps;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  Future<void> open(WidgetTester tester) async {
    // Ahem test fonts have wider metrics than the app fonts. This suite checks
    // navigation and data contracts, independent of native font rendering.
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => mechanicsFoundPage(savedJob())),
      GoRoute(
          path: '/mechanic-profile',
          builder: (_, state) => mechanicProfilePage(state.extra)),
      GoRoute(
          path: '/live-tracking',
          builder: (_, state) {
            received = AcceptedBooking.tryParse(state.extra);
            return liveTrackingPage(state.extra);
          }),
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('Sign in again'))),
      GoRoute(
          path: '/user-home',
          builder: (_, __) => const Scaffold(body: Text('Home'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  Finder button(String label) => find.widgetWithText(OnRaastaButton, label);

  testWidgets(
      'opens typed profile, displays real data and returns to original bids',
      (tester) async {
    await open(tester);
    await tester.tap(button('View Profile'));
    await tester.pumpAndSettle();
    final page =
        tester.widget<MechanicProfileView>(find.byType(MechanicProfileView));
    expect(page.selection.bid.bidId, 'bid-1');
    expect(page.selection.job['_id'], 'job-1');
    expect(find.text('Ali Khan'), findsOneWidget);
    expect(find.text('4.7'), findsOneWidget);
    // R08 loads reviews separately; this legacy fixture has no review response.
    expect(find.text('Retry reviews'), findsOneWidget);
    expect(find.text('Years Exp'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Workshop address'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    router!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(MechanicsFoundScreen), findsOneWidget);
    expect(find.text('1 bid received'), findsOneWidget);
    await finish(tester);
  });

  for (final fromProfile in [false, true]) {
    testWidgets(
        '${fromProfile ? 'Profile' : 'Discovery'} accepts once and hands confirmed booking to tracking',
        (tester) async {
      await open(tester);
      if (fromProfile) {
        await tester.tap(button('View Profile'));
        await tester.pumpAndSettle();
      }
      final response = Completer<ResponseBody>();
      adapter.respond = (r) => r.method == 'PATCH'
          ? response.future
          : Future.value(apiResponse(savedJob(accepted: true)));
      final accept = tester
          .widget<OnRaastaButton>(
              button(fromProfile ? 'Accept This Bid →' : 'Accept Bid'))
          .onPressed!;
      accept();
      accept();
      await tester.pump();
      expect(received, null);
      response.complete(apiResponse(bidJson(status: 'accepted')));
      await tester.pumpAndSettle();
      expect(adapter.requests.where((r) => r.method == 'PATCH'), hasLength(1));
      expect(received?.job['_id'], 'job-1');
      expect(received?.bid.bidId, 'bid-1');
      expect(received?.bid.mechanicId, 'mechanic-1');
      expect([
        received?.bid.labourCost,
        received?.bid.partsCost,
        received?.bid.totalCost
      ], [
        900.5,
        200.25,
        1100.75
      ]);
      expect(find.byKey(const Key('confirmed-total')), findsOneWidget);
      expect(find.text('Live location unavailable'), findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      expect(find.text('Booking Confirmed'),
          findsOneWidget); // No fake arrival/navigation.
      await finish(tester);
    });
  }

  for (final fromProfile in [false, true]) {
    for (final status in [401, 403, 404, 409]) {
      testWidgets(
          '${fromProfile ? 'Profile' : 'Discovery'} handles HTTP $status without broken navigation',
          (tester) async {
        await open(tester);
        if (fromProfile) {
          await tester.tap(button('View Profile'));
          await tester.pumpAndSettle();
        }
        adapter.respond = (r) async => r.method == 'PATCH'
            ? apiResponse(null, status: status, success: false)
            : apiResponse([bidJson(populated: true, status: 'declined')]);
        await tester
            .tap(button(fromProfile ? 'Accept This Bid →' : 'Accept Bid'));
        await tester.pumpAndSettle();
        expect(received, null);
        if (status == 401) {
          expect(find.text('Sign in again'), findsOneWidget);
        } else {
          expect(button('declined'), findsOneWidget);
          expect(tester.widget<OnRaastaButton>(button('declined')).onPressed,
              null);
        }
        expect(tester.takeException(), null);
        await finish(tester);
      });
    }
  }

  testWidgets('loading, empty, failure and retry states are visible',
      (tester) async {
    final response = Completer<ResponseBody>();
    adapter.respond = (_) => response.future;
    router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => mechanicsFoundPage(savedJob()))
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    response.complete(apiResponse([]));
    await tester.pumpAndSettle();
    expect(find.textContaining('No bids yet'), findsOneWidget);
    adapter.respond =
        (_) async => apiResponse(null, status: 500, success: false);
    await tester.tap(find.text('Refresh bids'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to reach'), findsOneWidget);
    adapter.respond = (_) async => apiResponse([bidJson(populated: true)]);
    await tester.tap(find.text('Refresh bids'));
    await tester.pumpAndSettle();
    expect(find.text('Ali Khan'), findsOneWidget);
    adapter.respond =
        (_) async => apiResponse(null, status: 500, success: false);
    await tester.tap(find.byTooltip('Refresh bids'));
    await tester.pumpAndSettle();
    expect(find.text('Ali Khan'), findsOneWidget);
    expect(find.textContaining('Unable to reach'), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
      'unavailable recommendations use ID fallback while real price and ETA sorting remain intact',
      (tester) async {
    adapter.respond =
        (request) async => request.path.endsWith('/recommendations')
            ? apiResponse(null, status: 503, success: false)
            : apiResponse([
                bidJson(id: 'slow')
                  ..addAll({
                    'mechanicName': 'Slow costly',
                    'rating': 4.8,
                    'labourCost': 2000,
                    'partsCost': 0,
                    'totalCost': 2000,
                    'eta': 30
                  }),
                bidJson(id: 'fast')
                  ..addAll({
                    'mechanicName': 'Fast premium',
                    'rating': 4.3,
                    'labourCost': 1000,
                    'partsCost': 0,
                    'totalCost': 1000,
                    'eta': 3
                  }),
                bidJson(id: 'cheap')
                  ..addAll({
                    'mechanicName': 'Cheap unrated',
                    'labourCost': 500,
                    'partsCost': 0,
                    'totalCost': 500,
                    'eta': null
                  }),
              ]);
    await open(tester);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Cheap unrated')).dy,
        lessThan(tester.getTopLeft(find.text('Fast premium')).dy));
    expect(find.textContaining('bid ID order'), findsOneWidget);
    await tester.tap(find.text('Cheapest'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Cheap unrated')).dy,
        lessThan(tester.getTopLeft(find.text('Fast premium')).dy));
    await tester.tap(find.text('Fastest'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Fast premium')).dy,
        lessThan(tester.getTopLeft(find.text('Slow costly')).dy));
    expect(find.text('ETA unavailable'), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
      'profile conflict refresh wins over an older pending profile load',
      (tester) async {
    await open(tester);
    final oldResponse = Completer<ResponseBody>();
    adapter.respond = (_) => oldResponse.future;
    await tester.tap(button('View Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    adapter.respond = (r) async => r.method == 'PATCH'
        ? apiResponse(null, status: 409, success: false)
        : apiResponse([bidJson(populated: true, status: 'declined')]);
    await tester.tap(button('Accept This Bid →'));
    await tester.pump(const Duration(milliseconds: 500));
    oldResponse.complete(apiResponse([bidJson(populated: true)]));
    await tester.pumpAndSettle();
    expect(button('declined'), findsOneWidget);
    expect(tester.widget<OnRaastaButton>(button('declined')).onPressed, null);
    expect(received, null);
    await finish(tester);
  });

  testWidgets(
      'missing optional profile data never fabricates reviews or verification',
      (tester) async {
    final minimal = {
      '_id': 'bid-1',
      'jobId': 'job-1',
      'mechanicId': 'mechanic-1',
      'status': 'pending'
    };
    adapter.respond = (_) async => apiResponse([minimal]);
    router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => mechanicProfilePage(
              BidSelection(job: savedJob(), bid: BidModel.fromJson(minimal))))
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Name unavailable'), findsOneWidget);
    expect(find.text('Unrated'), findsOneWidget);
    expect(find.text('Price unavailable'), findsOneWidget);
    // R08 loads reviews separately; this legacy fixture has no review response.
    expect(find.text('Retry reviews'), findsOneWidget);
    expect(tester.takeException(), null);
    await finish(tester);
  });

  testWidgets(
      'all bidding routes reject invalid navigation arguments gracefully',
      (tester) async {
    for (final builder in [
      mechanicsFoundPage,
      mechanicProfilePage,
      liveTrackingPage
    ]) {
      for (final extra in [
        null,
        'bad',
        <String, dynamic>{},
        {
          'job': savedJob(),
          'bid': {'mechanicId': []}
        }
      ]) {
        await tester.pumpWidget(MaterialApp(home: builder(extra)));
        expect(find.byType(InvalidBiddingArgumentsPage), findsOneWidget);
        expect(tester.takeException(), null);
      }
    }
    await finish(tester);
  });
}
