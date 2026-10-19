import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// Existing Maps platform interface avoids native rendering in controlled tests.
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:onraasta/features/user/live_tracking_screen.dart';
import 'package:onraasta/features/mechanic/active_job_screen.dart';
import 'package:onraasta/providers/assignment_controller.dart';
import 'package:onraasta/providers/job_location_controller.dart';
import 'package:onraasta/providers/job_tracking_publisher.dart';
import 'package:onraasta/services/job_location_service.dart';
import 'package:onraasta/services/foreground_location.dart';
import 'assignment_fixtures.dart';
import 'presence_fixtures.dart';
import 'tracking_test.dart' show observation, acknowledge;

class _Maps extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(int id, PlatformViewCreatedCallback created,
          {required MapWidgetConfiguration widgetConfiguration,
          MapConfiguration mapConfiguration = const MapConfiguration(),
          MapObjects mapObjects = const MapObjects()}) =>
      const SizedBox();
}

void main() {
  late GoogleMapsFlutterPlatform original;
  late FakePresenceSocket socket;
  late AssignmentDetailController detail;
  late JobLocationController tracking;
  DateTime now = DateTime.now();
  String status = 'en_route';
  setUp(() {
    original = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = _Maps();
    socket = FakePresenceSocket()..connected = true;
    now = DateTime.now();
    status = 'en_route';
    detail = AssignmentDetailController(
        booking: assignment(status: status),
        socket: socket,
        token: () async => null,
        load: (_) async => assignment(status: status));
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
    GoogleMapsFlutterPlatform.instance = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });
  Future<void> open(WidgetTester tester) async {
    tracking = JobLocationController(
        assignment: detail,
        socket: socket,
        load: (_) async => JobLocationSnapshot('job-1', true, null),
        clock: () => now);

    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: LiveTrackingScreen(
            booking: assignment(status: 'en_route'),
            controller: detail,
            locationController: tracking)));
    await tester.pumpAndSettle();
  }

  GoogleMap map(WidgetTester tester) =>
      tester.widget<GoogleMap>(find.byType(GoogleMap));
  testWidgets(
      'first real observation adds mechanic marker; later point moves it without moving breakdown or inventing a route',
      (tester) async {
    await open(tester);
    expect(map(tester).markers.length, 1);
    expect(
        find.textContaining('Waiting for mechanic location'), findsOneWidget);
    final originalCamera = map(tester).initialCameraPosition;
    socket.fire('job:mechanic_location',
        observation(observed: now.subtract(const Duration(seconds: 2))));
    await tester.pump();
    expect(
        map(tester)
            .markers
            .singleWhere((m) => m.markerId.value == 'mechanic')
            .position,
        const LatLng(31, 74));
    socket.fire(
        'job:mechanic_location',
        observation(
            lat: 31.001, observed: now.subtract(const Duration(seconds: 1))));
    await tester.pump();
    expect(
        map(tester)
            .markers
            .singleWhere((m) => m.markerId.value == 'mechanic')
            .position,
        const LatLng(31.001, 74));
    expect(
        map(tester)
            .markers
            .singleWhere((m) => m.markerId.value == 'user')
            .position,
        const LatLng(33.7, 73.1));
    expect(map(tester).initialCameraPosition, originalCamera);
    expect(map(tester).polylines, isEmpty);
    expect(detail.booking.job['status'], 'en_route');
    expect(find.text('Mechanic ETA estimate'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('wrong-job and malformed events never add a mechanic marker',
      (tester) async {
    await open(tester);
    socket.fire('job:mechanic_location', observation(job: 'other'));
    socket.fire('job:mechanic_location', {...observation(), 'lat': 91});
    await tester.pump();
    expect(map(tester).markers.length, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'freshness timer changes warning text, never generates movement or arrival',
      (tester) async {
    await open(tester);
    socket.fire('job:mechanic_location', observation(observed: now));
    await tester.pump();
    expect(find.textContaining('Recent location'), findsOneWidget);
    now = now.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 15));
    expect(find.textContaining('Location stale'), findsOneWidget);
    expect(
        map(tester)
            .markers
            .singleWhere((m) => m.markerId.value == 'mechanic')
            .position,
        const LatLng(31, 74));
    expect(detail.booking.job['status'], 'en_route');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'confirmed arrival clears location marker while R06 status remains authoritative',
      (tester) async {
    await open(tester);
    socket.fire('job:mechanic_location', observation(observed: now));
    await tester.pump();
    status = 'arrived';
    socket.fire('job:status_changed', {'jobId': 'job-1', 'status': 'arrived'});
    await tester.pumpAndSettle();
    expect(detail.booking.job['status'], 'arrived');
    expect(map(tester).markers.length, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'mechanic sharing banner waits for acknowledgment and keeps explicit arrival action',
      (tester) async {
    final gps = FakeForegroundLocation()..point = GpsPoint(31, 74);
    final ack = Completer<Map<String, dynamic>>();
    socket.respond = (_, __) => ack.future;
    socket.accessToken = 'fixture';
    final publisher = JobTrackingPublisher(
        socket: socket,
        gps: gps,
        token: () async => 'fixture',
        profile: () async => mechanicProfile(),
        assignments: () async => [assignment(status: 'en_route')]);
    final start = publisher.reconcile();
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: ActiveJobScreen(
            booking: assignment(status: 'en_route'),
            controller: detail,
            tracking: publisher)));
    await tester.pump();
    expect(find.textContaining('Waiting for GPS sharing'), findsOneWidget);
    expect(find.textContaining("I've Arrived"), findsOneWidget);
    ack.complete(await acknowledge('', socket.calls.single['data']));
    await start;
    await tester.pump();
    expect(find.textContaining('Location sharing confirmed'), findsOneWidget);
    expect(detail.booking.job['status'], 'en_route');
    await tester.pumpWidget(const SizedBox());
    publisher.dispose();
    await gps.close();
  });
}
