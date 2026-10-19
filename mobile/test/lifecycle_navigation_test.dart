import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// Existing platform interface isolates native maps.
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:onraasta/core/widgets/onraasta_button.dart';
import 'package:onraasta/core/widgets/assignment_panel.dart';
import 'package:onraasta/features/mechanic/active_job_screen.dart';
import 'package:onraasta/features/user/bidding_routes.dart';
import 'package:onraasta/features/user/live_tracking_screen.dart';
import 'package:onraasta/features/user/job_in_progress_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:onraasta/providers/assignment_controller.dart';
import 'package:onraasta/services/api_service.dart';
import 'package:onraasta/services/assignment_service.dart';
import 'package:onraasta/models/booking_arguments.dart';
import 'assignment_fixtures.dart';
import 'bidding_fixtures.dart';
import 'presence_fixtures.dart';

class _Maps extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(int id, PlatformViewCreatedCallback created,
          {required MapWidgetConfiguration widgetConfiguration,
          MapConfiguration mapConfiguration = const MapConfiguration(),
          MapObjects mapObjects = const MapObjects()}) =>
      const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePresenceSocket socket;
  late HttpClientAdapter oldAdapter;
  late BiddingAdapter adapter;
  late GoogleMapsFlutterPlatform oldMaps;
  GoRouter? router;
  setUp(() {
    socket = FakePresenceSocket();
    FlutterSecureStorage.setMockInitialValues(
        {'access_token': 'fixture-access'});
    oldAdapter = ApiService.instance.dio.httpClientAdapter;
    adapter = BiddingAdapter();
    ApiService.instance.dio.httpClientAdapter = adapter;
    oldMaps = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = _Maps();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final name = utf8.decode(message!.buffer.asUint8List());
      if (name == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage({
          for (final font in [
            'DMSans-Medium.ttf',
            'DMSans-Regular.ttf',
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
  tearDown(() {
    router?.dispose();
    router = null;
    ApiService.instance.dio.httpClientAdapter = oldAdapter;
    GoogleMapsFlutterPlatform.instance = oldMaps;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });
  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  AssignmentDetailController detail({Future<dynamic> Function(String)? load}) =>
      AssignmentDetailController(
          booking: assignment(),
          socket: socket,
          token: () async => null,
          load: (id) async => load == null ? assignment() : await load(id));
  testWidgets(
      'mechanic displays only next persisted action and never auto advances',
      (tester) async {
    String status = 'accepted';
    final controller = detail(load: (_) async => assignment(status: status));
    await open(
        tester, ActiveJobScreen(booking: assignment(), controller: controller));
    expect(find.text('Start travel'), findsOneWidget);
    expect(adapter.requests, isEmpty);
    status = 'en_route';
    socket.fire('job:status_changed', {'jobId': 'job-1', 'status': 'en_route'});
    await tester.pumpAndSettle();
    expect(find.textContaining("I've Arrived"), findsOneWidget);
    expect(find.text('Start travel'), findsNothing);
    status = 'arrived';
    socket.fire('job:status_changed', {'jobId': 'job-1', 'status': 'arrived'});
    await tester.pumpAndSettle();
    expect(find.textContaining('Start Repair'), findsOneWidget);
    status = 'in_progress';
    socket.fire(
        'job:status_changed', {'jobId': 'job-1', 'status': 'in_progress'});
    await tester.pumpAndSettle();
    expect(find.textContaining('Mark Complete'), findsOneWidget);
    expect(adapter.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'driver tracking navigates once after persisted work started; never on a forged event status alone',
      (tester) async {
    String saved = 'arrived';
    final controller = detail(load: (_) async => assignment(status: saved));
    int visits = 0;
    router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => LiveTrackingScreen(
              booking: assignment(), controller: controller)),
      GoRoute(
          path: '/job-in-progress',
          builder: (_, state) {
            visits++;
            final a = state.extra as AcceptedBooking;
            expect(a.jobId, 'job-1');
            expect(a.bid.totalCost, 1100.75);
            expect(a.job['status'], 'in_progress');
            return const Scaffold(body: Text('Persisted repair'));
          })
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router!));
    await tester.pumpAndSettle();
    socket.fire(
        'job:status_changed', {'jobId': 'other', 'status': 'in_progress'});
    await tester.pumpAndSettle();
    expect(visits, 0);
    socket.fire(
        'job:status_changed', {'jobId': 'job-1', 'status': 'in_progress'});
    await tester.pumpAndSettle();
    expect(visits, 0);
    saved = 'in_progress';
    socket.fire(
        'job:status_changed', {'jobId': 'job-1', 'status': 'in_progress'});
    socket.fire(
        'job:status_changed', {'jobId': 'job-1', 'status': 'in_progress'});
    await tester.pumpAndSettle();
    expect(visits, 1);
    socket.reconnect();
    await tester.pumpAndSettle();
    expect(visits, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'restart into tracking recovers already-completed work into Job In Progress',
      (tester) async {
    final controller =
        detail(load: (_) async => assignment(status: 'completed'));
    int visits = 0;
    router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => LiveTrackingScreen(
              booking: assignment(), controller: controller)),
      GoRoute(
          path: '/job-in-progress',
          builder: (_, state) {
            visits++;
            expect((state.extra as AcceptedBooking).job['status'], 'completed');
            return const Scaffold(body: Text('Completed saved job'));
          })
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router!));
    await tester.pumpAndSettle();
    expect(visits, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'driver repair screen cannot advance stages or review before persisted completion',
      (tester) async {
    String status = 'in_progress';
    final controller = detail(load: (_) async => assignment(status: status));
    await open(tester,
        JobInProgressScreen(booking: assignment(), controller: controller));
    expect(find.text('Repair In Progress'), findsOneWidget);
    expect(find.textContaining('Mark Complete'), findsNothing);
    expect(find.text('Rate Mechanic'), findsNothing);
    final button = tester.widget<OnRaastaButton>(find.byType(OnRaastaButton));
    expect(button.onPressed, isNull);
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.markers.map((m) => m.markerId.value), ['job']);
    expect(map.polylines, isEmpty);
    status = 'completed';
    socket
        .fire('job:status_changed', {'jobId': 'job-1', 'status': 'completed'});
    await tester.pumpAndSettle();
    expect(find.text('Rate Mechanic'), findsOneWidget);
    expect(adapter.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'review navigation rechecks completed state and preserves all assignment IDs/prices',
      (tester) async {
    final controller =
        detail(load: (_) async => assignment(status: 'completed'));
    AcceptedBooking? received;
    router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => JobInProgressScreen(
              booking: assignment(), controller: controller)),
      GoRoute(
          path: '/rate-review',
          builder: (_, state) {
            received = state.extra as AcceptedBooking;
            return const Scaffold(body: Text('Review saved repair'));
          })
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router!));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rate Mechanic'));
    await tester.pumpAndSettle();
    expect(received!.jobId, 'job-1');
    expect(received!.bid.bidId, 'bid-1');
    expect(received!.bid.mechanicId, 'mechanic-1');
    expect(received!.bid.totalCost, 1100.75);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('review is blocked if final completion reload fails',
      (tester) async {
    bool fail = false;
    final controller = detail(load: (_) async {
      if (fail) throw const AssignmentFailure('Offline completion check');
      return assignment(status: 'completed');
    });
    await open(tester,
        JobInProgressScreen(booking: assignment(), controller: controller));
    fail = true;
    await tester.tap(find.text('Rate Mechanic'));
    await tester.pumpAndSettle();
    expect(find.text('Offline completion check'), findsOneWidget);
    expect(controller.verified, false);
    expect(adapter.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'cancelled job shows terminal state and no driver mutation/review',
      (tester) async {
    final controller =
        detail(load: (_) async => assignment(status: 'cancelled'));
    await open(tester,
        JobInProgressScreen(booking: assignment(), controller: controller));
    expect(find.text('Job Cancelled'), findsWidgets);
    expect(tester.widget<OnRaastaButton>(find.byType(OnRaastaButton)).onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'app resume reloads repair state from server without socket history',
      (tester) async {
    int reads = 0;
    final controller = detail(load: (_) async {
      reads++;
      return assignment(status: reads > 1 ? 'completed' : 'in_progress');
    });
    await open(tester,
        JobInProgressScreen(booking: assignment(), controller: controller));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reads, greaterThan(1));
    expect(find.text('Rate Mechanic'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'job-in-progress and review routes reject invalid or uncompleted arguments',
      (tester) async {
    await open(tester, jobInProgressPage({'jobId': 'job-1'}));
    expect(find.byType(InvalidBiddingArgumentsPage), findsOneWidget);
    await open(tester, rateReviewPage(assignment()));
    expect(find.byType(InvalidBiddingArgumentsPage), findsOneWidget);
  });
  testWidgets(
      'recent closed assignments are labeled separately and reopen only on tap',
      (tester) async {
    int opens = 0;
    final inbox = AssignmentInboxController(
        socket: socket,
        loadActive: () async => [assignment(status: 'completed')],
        loadOne: (_) async => assignment(status: 'completed'));
    await inbox.refresh();
    await open(
        tester,
        Scaffold(
            body: AssignmentPanel(
                controller: inbox,
                onOpen: (booking) {
                  expect(booking.job['status'], 'completed');
                  opens++;
                })));
    expect(inbox.bookings, isEmpty);
    expect(find.text('No active assignments.'), findsOneWidget);
    expect(find.textContaining('Closed: Battery failure'), findsOneWidget);
    expect(opens, 0);
    await tester.tap(find.byKey(const Key('assignment-job-1')));
    expect(opens, 1);
    await tester.pumpWidget(const SizedBox());
    inbox.dispose();
  });
}
