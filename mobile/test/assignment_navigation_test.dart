import 'dart:async';
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
import 'package:onraasta/core/widgets/assignment_panel.dart';
import 'package:onraasta/core/widgets/onraasta_button.dart';
import 'package:onraasta/features/mechanic/active_job_screen.dart';
import 'package:onraasta/features/mechanic/submit_bid_screen.dart';
import 'package:onraasta/features/user/bidding_routes.dart';
import 'package:onraasta/features/user/live_tracking_screen.dart';
import 'package:onraasta/providers/assignment_controller.dart';
import 'package:onraasta/services/api_service.dart';
import 'package:onraasta/services/assignment_service.dart';
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
      'Active Job uses accepted status, saved customer and agreed component prices, never default en_route',
      (tester) async {
    final controller = detail();
    await open(
        tester, ActiveJobScreen(booking: assignment(), controller: controller));
    expect(find.text('Start travel'), findsOneWidget);
    expect(find.text('Saved Customer'), findsOneWidget);
    expect(find.byKey(const Key('agreed-total')), findsOneWidget);
    expect(find.text('PKR 1100.75'), findsOneWidget);
    expect(controller.booking.job['status'], 'accepted');
    expect(adapter.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'failed authoritative Active Job read retains job but disables mutations and supports retry',
      (tester) async {
    bool fail = true;
    final controller = detail(load: (_) async {
      if (fail) throw const AssignmentFailure('Offline, retry');
      return assignment();
    });
    await open(
        tester, ActiveJobScreen(booking: assignment(), controller: controller));
    expect(find.text('Offline, retry'), findsOneWidget);
    expect(find.text('Start travel'), findsNothing);
    expect(controller.jobId, 'job-1');
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Start travel'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('forbidden recovery hides private customer details',
      (tester) async {
    final controller = detail(
        load: (_) async => throw const AssignmentFailure('Forbidden', 403));
    await open(
        tester, ActiveJobScreen(booking: assignment(), controller: controller));
    expect(find.text('Saved Customer'), findsNothing);
    expect(find.text('Forbidden'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'driver tracking reloads same saved job, confirmed price and persisted state without simulated progress',
      (tester) async {
    final controller = detail(load: (_) async => assignment(status: 'arrived'));
    await open(tester,
        LiveTrackingScreen(booking: assignment(), controller: controller));
    expect(controller.booking.job['status'], 'arrived');
    expect(find.byKey(const Key('confirmed-total')), findsOneWidget);
    expect(find.text('PKR 1100.75'), findsOneWidget);
    expect(find.text('Live location unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'assignment list shows multiple records, deduplicates hints and opens only on explicit tap',
      (tester) async {
    int opens = 0;
    final inbox = AssignmentInboxController(
        socket: socket,
        loadActive: () async => [assignment(), assignment(id: 'job-2')],
        loadOne: (_) async => assignment());
    await inbox.refresh();
    await open(
        tester,
        Scaffold(
            body: AssignmentPanel(controller: inbox, onOpen: (_) => opens++)));
    expect(find.byKey(const Key('assignment-job-1')), findsOneWidget);
    expect(find.byKey(const Key('assignment-job-2')), findsOneWidget);
    socket.fire('job:assigned', assignmentHint());
    socket.reconnect();
    await tester.pumpAndSettle();
    expect(opens, 0);
    expect(inbox.bookings.length, 2);
    await tester.tap(find.byKey(const Key('assignment-job-1')));
    expect(opens, 1);
    await tester.pumpWidget(const SizedBox());
    inbox.dispose();
  });
  for (final extra in [
    null,
    'bad',
    {},
    {
      'job': {'_id': 'job-1'}
    }
  ]) {
    testWidgets('invalid active booking navigation is safe: $extra',
        (tester) async {
      await open(tester, activeJobPage(extra));
      expect(find.byType(InvalidBiddingArgumentsPage), findsOneWidget);
    });
  }
  testWidgets('malformed opportunity route arguments show recoverable page',
      (tester) async {
    await open(tester, opportunityPage('bad', submit: true));
    expect(find.byType(InvalidBiddingArgumentsPage), findsOneWidget);
  });
  Future<void> bidForm(WidgetTester tester) async {
    await open(tester, SubmitBidScreen(job: savedJob()));
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), '900');
    await tester.enterText(fields.at(1), '200');
    await tester.enterText(fields.at(2), '12');
  }

  testWidgets(
      'assigned job preflight blocks an already-open bid form without POST',
      (tester) async {
    int reads = 0;
    adapter.respond =
        (_) async => apiResponse({'jobId': 'job-1', 'isOpen': ++reads == 1});
    await bidForm(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Bid'));
    await tester.pumpAndSettle();
    expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    expect(find.text('This job is no longer accepting bids.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'bid conflict is visible, not successful navigation, and authenticated request uses real job',
      (tester) async {
    adapter.respond = (request) async => request.method == 'POST'
        ? apiResponse({}, status: 409, success: false)
        : apiResponse({'jobId': 'job-1', 'isOpen': true});
    await bidForm(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Bid'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot accept another bid'), findsOneWidget);
    final post = adapter.requests.singleWhere((r) => r.method == 'POST');
    expect(post.data['jobId'], 'job-1');
    expect(post.headers['Authorization'], 'Bearer fixture-access');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'duplicate submit taps issue only one bid while request is pending',
      (tester) async {
    final pending = Completer<ResponseBody>();
    adapter.respond = (request) async => request.method == 'POST'
        ? await pending.future
        : apiResponse({'jobId': 'job-1', 'isOpen': true});
    await bidForm(tester);
    final button = find.widgetWithText(ElevatedButton, 'Submit Bid');
    final submit = tester.widget<ElevatedButton>(button).onPressed!;
    submit();
    submit();
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(adapter.requests.where((r) => r.method == 'POST').length, 1);
    pending.complete(apiResponse({}, status: 409, success: false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'status writes do not optimistically progress when backend rejects mutation',
      (tester) async {
    adapter.respond = (_) async => apiResponse({}, status: 409, success: false);
    final controller = detail();
    await open(
        tester, ActiveJobScreen(booking: assignment(), controller: controller));
    await tester.tap(find.widgetWithText(OnRaastaButton, 'Start travel'));
    await tester.pumpAndSettle();
    expect(controller.booking.job['status'], 'accepted');
    expect(find.textContaining('not confirmed'), findsOneWidget);
    expect(adapter.requests.single.path, '/jobs/job-1/status');
    await tester.pumpWidget(const SizedBox());
  });
}
