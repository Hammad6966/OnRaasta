import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// Existing platform interface keeps widget tests independent of native maps.
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:onraasta/features/mechanic/mechanic_home_screen.dart';
import 'package:onraasta/providers/mechanic_presence_controller.dart';
import 'presence_fixtures.dart';
import 'package:onraasta/providers/assignment_controller.dart';

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
  late FakeForegroundLocation gps;
  late MechanicPresenceController presence;
  bool approved = true;
  setUp(() {
    original = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = _Maps();
    socket = FakePresenceSocket();
    gps = FakeForegroundLocation();
    approved = true;
    presence = MechanicPresenceController(
        socket: socket,
        gps: gps,
        token: () async => 'fixture-access-token',
        profile: () async => mechanicProfile(approved: approved),
        loadRequests: () async => []);
  });
  tearDown(() async {
    GoogleMapsFlutterPlatform.instance = original;
    await gps.close();
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MechanicHomeScreen(
            presence: presence,
            assignments: AssignmentInboxController(
                socket: socket,
                loadActive: () async => [],
                loadOne: (_) async =>
                    throw StateError('No assignment fixture')))));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets(
      'pending approval is visible and fallback map viewport is not a GPS marker',
      (tester) async {
    approved = false;
    await open(tester);
    expect(find.textContaining('awaiting approval'), findsOneWidget);
    expect(tester.widget<GoogleMap>(find.byType(GoogleMap)).markers, isEmpty);
    expect(find.text("You're Offline"), findsOneWidget);
    await finish(tester);
  });
  testWidgets(
      'screen stays offline until acknowledgment and displays location errors',
      (tester) async {
    await open(tester);
    final ack = Completer<Map<String, dynamic>>();
    socket.respond = (_, __) => ack.future;
    final pending = presence.toggle();
    await tester.pump();
    expect(find.text("You're Offline"), findsOneWidget);
    ack.complete({
      'mechanicId': 'mechanic-1',
      'isOnline': true,
      'lat': 31,
      'lng': 74,
      'serviceRadius': 15
    });
    await pending;
    await tester.pumpAndSettle();
    expect(find.text("You're Online"), findsOneWidget);
    expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .markers
            .single
            .position,
        const LatLng(31, 74));
    gps.services.add(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Location services disabled'), findsOneWidget);
    expect(find.text("You're Offline"), findsOneWidget);
    await finish(tester);
  });
  testWidgets(
      'request feed deduplicates and navigates using the original saved Job ID',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? received;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => MechanicHomeScreen(
              presence: presence,
              assignments: AssignmentInboxController(
                  socket: socket,
                  loadActive: () async => [],
                  loadOne: (_) async =>
                      throw StateError('No assignment fixture')))),
      GoRoute(
          path: '/new-request-detail',
          builder: (_, state) {
            received = state.extra as Map<String, dynamic>;
            return const Scaffold(body: Text('Request detail'));
          })
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await presence.toggle();
    await tester.pumpAndSettle();
    socket.fire('job:new_request', requestJson('real-saved-job'));
    socket.fire('job:new_request', requestJson('real-saved-job'));
    await tester.pumpAndSettle();
    expect(find.text('2.3 km away'), findsOneWidget);
    await tester.tap(find.text('View →'));
    await tester.pumpAndSettle();
    expect(received?['jobId'], 'real-saved-job');
    expect(received?['location'], {'lat': 31, 'lng': 74});
    await finish(tester);
  });
}
