import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// The Maps plugin's existing platform interface is used only to isolate native UI.
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:onraasta/core/widgets/onraasta_button.dart';
import 'package:onraasta/features/user/mechanics_found_screen.dart';
import 'package:onraasta/features/user/report_breakdown_screen.dart';
import 'package:onraasta/services/api_service.dart';
import 'package:onraasta/services/socket_service.dart';

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

class _ApiAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Future<ResponseBody> Function(RequestOptions)? respond;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return respond!(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(dynamic body, {int status = 201}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ApiAdapter adapter;
  late HttpClientAdapter originalAdapter;
  late GoogleMapsFlutterPlatform originalMaps;
  late GoRouter router;
  Map<String, dynamic>? receivedJob;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test-token'});
    originalAdapter = ApiService.instance.dio.httpClientAdapter;
    adapter = _ApiAdapter();
    ApiService.instance.dio.httpClientAdapter = adapter;
    originalMaps = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = _MapPlatform();
    receivedJob = null;
    router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ReportBreakdownScreen()),
      GoRoute(
        path: '/mechanics-found',
        builder: (_, state) {
          receivedJob = state.extra as Map<String, dynamic>;
          return const Scaffold(body: Text('Mechanics destination'));
        },
      ),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold()),
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'getCurrentPosition'
          ? {
              'latitude': 33.6844,
              'longitude': 73.0479,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'accuracy': 10.0,
              'altitude': 0.0,
              'altitude_accuracy': 0.0,
              'heading': 0.0,
              'heading_accuracy': 0.0,
              'speed': 0.0,
              'speed_accuracy': 0.0,
              'is_mocked': true,
            }
          : 2, // Controlled foreground permission and device position; no native GPS.
    );
    // Supply font assets in memory so button rendering never fetches fonts.
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
    router.dispose();
    SocketService().disconnect();
    ApiService.instance.dio.httpClientAdapter = originalAdapter;
    GoogleMapsFlutterPlatform.instance = originalMaps;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/geolocator'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  Future<VoidCallback> openReport(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    // Three characters avoid scheduling an unrelated diagnosis request.
    await tester.enterText(find.byType(TextField), 'SOS');
    return tester
        .widget<OnRaastaButton>(find.byType(OnRaastaButton))
        .onPressed!;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  Future<void> waitForRequest(WidgetTester tester) async {
    for (var i = 0; i < 10 && adapter.requests.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('passes the complete saved job and real ID to the route',
      (tester) async {
    final savedJob = {
      '_id': 'saved-job-id',
      'description': 'SOS',
      'location': {'lat': 33.6844, 'lng': 73.0479},
      'aiDiagnosis': {'fault_class': 'dead_battery'},
      'vehicleId': 'saved-vehicle-id',
      'photos': ['https://example.test/photo.png'],
    };
    adapter.respond =
        (_) async => _jsonResponse({'success': true, 'data': savedJob});
    final submit = await openReport(tester);
    submit();
    await tester.pumpAndSettle();
    expect(receivedJob, savedJob);
    expect(find.text('Mechanics destination'), findsOneWidget);
    expect(adapter.requests.single.path, '/jobs');
    expect(adapter.requests.single.data['description'], 'SOS');
    expect(adapter.requests.single.data['location']['lat'], 33.6844);
    expect(adapter.requests.single.data, contains('aiDiagnosis'));
    await finish(tester);
  });

  final invalidJobs = <String, dynamic>{
    'missing ID': <String, dynamic>{},
    'empty ID': {'_id': ''},
    'whitespace ID': {'_id': '   '},
    'non-string ID': {'_id': 12},
    'missing job': null,
    'list instead of job': <dynamic>[],
  };
  for (final entry in invalidJobs.entries) {
    testWidgets('rejects ${entry.key} without navigating', (tester) async {
      adapter.respond =
          (_) async => _jsonResponse({'success': true, 'data': entry.value});
      (await openReport(tester))();
      await tester.pumpAndSettle();
      expect(receivedJob, isNull);
      expect(
          find.text(
              'The server returned an invalid job. Unable to find mechanics.'),
          findsOneWidget);
      expect(
          tester.widget<OnRaastaButton>(find.byType(OnRaastaButton)).isLoading,
          isFalse);
      await finish(tester);
    });
  }

  for (final body in <dynamic>[
    null,
    'not an object',
    <dynamic>[],
    {
      'data': {'_id': 'id'}
    }
  ]) {
    testWidgets('rejects malformed envelope ${jsonEncode(body)}',
        (tester) async {
      adapter.respond = (_) async => _jsonResponse(body);
      (await openReport(tester))();
      await tester.pumpAndSettle();
      expect(receivedJob, isNull);
      expect(
          find.text('Failed to create job. Please try again.'), findsOneWidget);
      await finish(tester);
    });
  }

  testWidgets('shows unsuccessful response message without navigating',
      (tester) async {
    adapter.respond = (_) async =>
        _jsonResponse({'success': false, 'message': 'Request rejected'});
    (await openReport(tester))();
    await tester.pumpAndSettle();
    expect(receivedJob, isNull);
    expect(find.text('Request rejected'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('handles failed backend and malformed error message',
      (tester) async {
    adapter.respond =
        (_) async => _jsonResponse({'message': <String>[]}, status: 500);
    (await openReport(tester))();
    await tester.pumpAndSettle();
    expect(receivedJob, isNull);
    expect(
        find.text('Failed to create job. Please try again.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('blocks repeat submission before and during the request',
      (tester) async {
    final response = Completer<ResponseBody>();
    adapter.respond = (_) => response.future;
    final submit = await openReport(tester);
    submit();
    submit(); // Includes the asynchronous secure-storage lookup window.
    await waitForRequest(tester);
    expect(adapter.requests, hasLength(1));
    expect(tester.widget<OnRaastaButton>(find.byType(OnRaastaButton)).isLoading,
        isTrue);
    submit();
    await tester.pump();
    expect(adapter.requests, hasLength(1));
    response.complete(_jsonResponse({
      'success': true,
      'data': {'_id': 'saved-id'}
    }));
    await tester.pumpAndSettle();
    expect(receivedJob?['_id'], 'saved-id');
    await finish(tester);
  });

  testWidgets('allows retry after a network failure', (tester) async {
    adapter.respond = (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
    final submit = await openReport(tester);
    submit();
    await tester.pumpAndSettle();
    expect(receivedJob, isNull);
    expect(
        find.text('Failed to create job. Please try again.'), findsOneWidget);
    expect(tester.widget<OnRaastaButton>(find.byType(OnRaastaButton)).isLoading,
        isFalse);
    adapter.respond = (_) async => _jsonResponse({
          'success': true,
          'data': {'_id': 'retry-job-id'}
        });
    submit();
    await tester.pumpAndSettle();
    expect(adapter.requests, hasLength(2));
    expect(receivedJob?['_id'], 'retry-job-id');
    await finish(tester);
  });

  testWidgets('handles a non-JSON backend error without navigating',
      (tester) async {
    adapter.respond = (_) async => ResponseBody.fromString('Unavailable', 503);
    (await openReport(tester))();
    await tester.pumpAndSettle();
    expect(receivedJob, isNull);
    expect(
        find.text('Failed to create job. Please try again.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Mechanics Found fetches bids using the saved job ID',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    adapter.respond =
        (_) async => _jsonResponse({'success': true, 'data': []}, status: 200);
    await tester.pumpWidget(const MaterialApp(
      home: MechanicsFoundScreen(job: {'_id': 'actual-saved-id'}),
    ));
    await waitForRequest(tester);
    expect(adapter.requests.single.path, '/bids');
    expect(
        adapter.requests.single.queryParameters, {'jobId': 'actual-saved-id'});
    await tester.pump(const Duration(milliseconds: 500));
    SocketService().disconnect();
    await finish(tester);
  });
  testWidgets('missing GPS never saves fallback map coordinates as a breakdown',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/geolocator'),
            (_) async => 0);
    final submit = await openReport(tester);
    submit();
    await tester.pumpAndSettle();
    expect(adapter.requests, isEmpty);
    expect(receivedJob, isNull);
    expect(find.textContaining('A current GPS location is required'),
        findsOneWidget);
    expect(find.text('Retry GPS location'), findsOneWidget);
    await finish(tester);
  });
}
