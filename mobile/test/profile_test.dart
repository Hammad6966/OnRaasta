import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onraasta/providers/profile_controller.dart';
import 'package:onraasta/services/profile_service.dart';
import 'package:onraasta/services/media_service.dart';
import 'package:onraasta/services/auth_service.dart';
import 'package:onraasta/features/user/user_profile_screen.dart';
import 'package:onraasta/features/mechanic/mechanic_profile_edit.dart';
import 'package:onraasta/features/mechanic/document_upload_screen.dart';
import 'package:onraasta/core/widgets/profile_edit_dialog.dart';
import 'bidding_fixtures.dart';

Map<String, dynamic> account() => {
      '_id': 'driver-1',
      'name': 'Persisted Driver',
      'phone': '3001234567',
      'email': 'contact@example.test',
      'isVerified': true,
      'emergencyContacts': <dynamic>[]
    };

class UnavailableMedia extends MediaService {
  @override
  Future<Map<String, dynamic>> documents() async => throw Exception('offline');
}

class Profiles extends ProfileService {
  Map<String, dynamic> saved = account();
  Map<String, dynamic> details = {
    '_id': 'mechanic-1',
    'skills': ['Battery'],
    'serviceRadius': 15,
    'shopAddress': 'Actual workshop',
    'isApproved': true
  };
  final cars = <Map<String, dynamic>>[];
  int reads = 0, writes = 0;
  Future<Map<String, dynamic>> Function()? read;
  Future<dynamic> Function(String, String, Map<String, dynamic>?)? write;
  @override
  Future<Map<String, dynamic>> profile() async {
    reads++;
    return read == null ? Map.of(saved) : await read!();
  }

  @override
  Future<Map<String, dynamic>> mechanic() async => Map.of(details);
  @override
  Future<List<Map<String, dynamic>>> vehicles() async => List.of(cars);
  @override
  Future<dynamic> request(String method, String path,
      [Map<String, dynamic>? body]) async {
    writes++;
    if (write != null) return write!(method, path, body);
    if (path == '/users/profile') saved.addAll(body!);
    if (path == '/users/vehicles') cars.add({'_id': 'vehicle-1', ...body!});
    if (path == '/mechanics/profile') {
      details.addAll(body!);
      saved['name'] = body['name'];
    }
    return saved;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Profiles service;
  late AuthService auth;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    service = Profiles();
    auth = AuthService.forTesting(Dio());
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
  tearDown(() {
    auth.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });
  test('real profile and vehicle state loads without local defaults', () async {
    service.cars.add({'_id': 'vehicle-1', 'plate': 'ABC', 'isPrimary': true});
    final c = ProfileController(service: service, auth: auth);
    addTearDown(c.dispose);
    await c.load();
    expect(c.user!['name'], 'Persisted Driver');
    expect(c.vehicles.single['plate'], 'ABC');
    expect(c.error, isNull);
  });
  test('new controller after app restart reloads persisted changes', () async {
    final c = ProfileController(service: service, auth: auth);
    await c.load();
    expect(await c.save('PATCH', '/users/profile', {'name': 'Saved Name'}),
        isTrue);
    c.dispose();
    final restored = ProfileController(service: service, auth: auth);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.user!['name'], 'Saved Name');
  });
  test('concurrent loads are coalesced', () async {
    final gate = Completer<Map<String, dynamic>>();
    service.read = () => gate.future;
    final c = ProfileController(service: service, auth: auth);
    addTearDown(c.dispose);
    final first = c.load();
    await c.load();
    expect(service.reads, 1);
    gate.complete(account());
    await first;
  });
  test('failure and retry retain honest loading/error state', () async {
    service.read = () async => throw Exception('offline');
    final c = ProfileController(service: service, auth: auth);
    addTearDown(c.dispose);
    await c.load();
    expect(c.user, isNull);
    expect(c.error, contains('retry'));
    expect(c.loading, false);
    service.read = null;
    await c.load();
    expect(c.user, isNotNull);
    expect(c.error, isNull);
  });
  test('duplicate saves blocked until confirmed', () async {
    final gate = Completer<dynamic>();
    service.write = (_, __, ___) => gate.future;
    final c = ProfileController(service: service, auth: auth);
    addTearDown(c.dispose);
    await c.load();
    final first = c.save('PATCH', '/users/profile', {'name': 'New'});
    expect(c.saving, true);
    expect(await c.save('PATCH', '/users/profile', {'name': 'New'}), false);
    expect(service.writes, 1);
    expect(c.user!['name'], 'Persisted Driver');
    gate.complete(account());
    expect(await first, true);
    expect(c.saving, false);
  });
  for (final status in [400, 401, 403, 404, 409]) {
    test('save handles HTTP $status without false success', () async {
      service.write = (_, __, ___) async => throw DioException(
          requestOptions: RequestOptions(),
          response: Response(
              requestOptions: RequestOptions(),
              statusCode: status,
              data: {'message': 'Conflict from server'}));
      final c = ProfileController(service: service, auth: auth);
      addTearDown(c.dispose);
      await c.load();
      expect(
          await c.save('PATCH', '/users/profile', {'name': 'Changed'}), false);
      expect(c.error, isNotNull);
      expect(c.user!['name'], 'Persisted Driver');
    });
  }
  test('logout clears cached data and ignores late account response', () async {
    final c = ProfileController(service: service, auth: auth);
    addTearDown(c.dispose);
    await c.load();
    final gate = Completer<Map<String, dynamic>>();
    service.read = () => gate.future;
    final loading = c.load();
    await auth.clearTokens();
    expect(c.user, isNull);
    expect(c.vehicles, isEmpty);
    gate.complete(account());
    await loading;
    expect(c.user, isNull);
  });
  test('late save from old session does not announce mechanic updates',
      () async {
    final gate = Completer<dynamic>();
    service.write = (_, __, ___) => gate.future;
    var signals = 0;
    void changed() {
      signals++;
    }

    ProfileService.mechanicChanges.addListener(changed);
    addTearDown(() => ProfileService.mechanicChanges.removeListener(changed));
    final c = ProfileController(service: service, auth: auth, mechanic: true);
    addTearDown(c.dispose);
    await c.load();
    final save = c.save('PATCH', '/mechanics/profile', {'serviceRadius': 20});
    await auth.clearTokens();
    gate.complete({});
    expect(await save, false);
    expect(signals, 0);
    expect(c.mechanicProfile, isNull);
  });
  test(
      'vehicle service uses established owner-scoped routes and rejects malformed response',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://fixture.test'));
    final adapter = BiddingAdapter();
    dio.httpClientAdapter = adapter;
    adapter.respond = (_) async => ResponseBody.fromString(
            jsonEncode({
              'success': true,
              'data': [
                {'plate': 'ABC'}
              ]
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType]
            });
    final real = ProfileService(dio: dio);
    expect((await real.vehicles()).single['plate'], 'ABC');
    expect(adapter.requests.single.path, '/users/vehicles');
    adapter.respond = (_) async =>
        ResponseBody.fromString('{"success":true,"data":{}}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
    await expectLater(real.vehicles(), throwsFormatException);
  });
  testWidgets('driver profile loads real data and honest empty state',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: UserProfileScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Persisted Driver'), findsOneWidget);
    expect(find.text('Toyota Corolla'), findsNothing);
    expect(find.text('No vehicles saved.'), findsOneWidget);
    expect(find.text('No contacts saved.'), findsOneWidget);
  });
  testWidgets('driver profile loading, failure and retry', (tester) async {
    final gate = Completer<Map<String, dynamic>>();
    service.read = () => gate.future;
    await tester
        .pumpWidget(MaterialApp(home: UserProfileScreen(service: service)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    service.read = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Persisted Driver'), findsOneWidget);
  });
  testWidgets(
      'mechanic form loads persisted values, defaults radius and locks phone',
      (tester) async {
    service.details.remove('serviceRadius');
    await tester.pumpWidget(
        MaterialApp(home: MechanicProfileEditScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Persisted Driver'), findsOneWidget);
    expect(find.text('Actual workshop'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[1].readOnly, true);
    await tester.scrollUntilVisible(find.byType(Slider), 250,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 15);
  });
  testWidgets('manual account revocation is distinct from document status',
      (tester) async {
    service.details['isApproved'] = false;
    service.details['accountApprovalStatus'] = 'revoked';
    service.details['documents'] = {'status': 'pending'};
    await tester.pumpWidget(
        MaterialApp(home: MechanicProfileEditScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Approval rejected or revoked - contact support'),
        findsOneWidget);
    expect(find.text('Pending approval'), findsNothing);
    expect(find.text('Documents & Verification'), findsOneWidget);
  });
  testWidgets('mechanic save persists actual entered values', (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: MechanicProfileEditScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Updated Mechanic');
    await tester.scrollUntilVisible(find.text('Save Changes'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(service.saved['name'], 'Updated Mechanic');
    expect(service.details['serviceRadius'], 15);
    expect(service.writes, 1);
  });
  testWidgets(
      'save dialog keeps input and disables repeated submission on network failure',
      (tester) async {
    final gate = Completer<String?>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (c) => TextButton(
                onPressed: () => editProfileFields(c,
                        title: 'Edit', values: {'Name': ''}, save: (_) {
                      calls++;
                      return gate.future;
                    }),
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Retain Me');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Saving...'), findsOneWidget);
    expect(calls, 1);
    gate.complete('Network unavailable. Retry.');
    await tester.pumpAndSettle();
    expect(find.text('Retain Me'), findsOneWidget);
    expect(find.text('Network unavailable. Retry.'), findsOneWidget);
  });
  testWidgets(
      'unavailable documents backend cannot report fake upload or success',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: DocumentUploadScreen(service: UnavailableMedia())));
    await tester.pumpAndSettle();
    expect(find.text('Reload documents'), findsOneWidget);
    expect(find.text('Documents submitted for review.'), findsNothing);
    expect(find.text('Submit for review'), findsNothing);
    expect(find.text('Uploaded'), findsNothing);
  });
  testWidgets('driver account edit waits for backend and reloads saved name',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: UserProfileScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Saved Driver');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved Driver'), findsOneWidget);
    expect(service.saved['name'], 'Saved Driver');
    expect(service.writes, 1);
  });
  testWidgets('vehicle dialog creates a persisted vehicle and refreshes card',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: UserProfileScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Add Vehicle'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Add Vehicle'));
    await tester.pumpAndSettle();
    final inputs = find.byType(TextField);
    await tester.enterText(inputs.at(0), 'Suzuki');
    await tester.enterText(inputs.at(1), 'Alto');
    await tester.enterText(inputs.at(2), 'ABC-123');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.cars.single['plate'], 'ABC-123');
    expect(find.text('Suzuki Alto'), findsOneWidget);
  });
  testWidgets(
      'emergency contact dialog persists a private contact without claiming dispatch',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: UserProfileScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Add Emergency Contact'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Add Emergency Contact'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Family Contact');
    await tester.enterText(find.byType(TextField).at(1), '+923001234567');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((service.saved['emergencyContacts'] as List).single['name'],
        'Family Contact');
    expect(find.text('Family Contact'), findsOneWidget);
    expect(find.textContaining('alerts are not enabled'), findsOneWidget);
  });
  test('malformed profile identity is rejected by the shared API service',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://fixture.test'));
    final adapter = BiddingAdapter();
    dio.httpClientAdapter = adapter;
    adapter.respond = (_) async =>
        ResponseBody.fromString('{"success":true,"data":{}}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
    await expectLater(
        ProfileService(dio: dio).profile(), throwsFormatException);
  });
}
