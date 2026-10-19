import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onraasta/services/auth_service.dart';
import 'package:onraasta/services/api_service.dart';
import 'package:onraasta/services/socket_service.dart';
import 'package:onraasta/features/auth/splash_screen.dart';
import 'bidding_fixtures.dart';

String access(
        {int seconds = 1800,
        String marker = 'old',
        String id = 'driver-1',
        String role = 'user'}) =>
    'fixture.${base64Url.encode(utf8.encode(jsonEncode({
          'id': id,
          'role': role,
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds,
          'marker': marker
        })))}.signature';
Map<String, dynamic> credentials(
        {String id = 'driver-1',
        String role = 'user',
        String marker = 'new'}) =>
    {
      'success': true,
      'accessToken': access(marker: marker, id: id, role: role),
      'refreshToken': 'rotated-$marker',
      'user': {
        'id': id,
        'role': role,
        'name': 'Persisted person',
        'phone': 'fixture-phone'
      }
    };
ResponseBody reply(Object? body, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
void seed(
    {String? token,
    String role = 'user',
    String id = 'driver-1',
    bool refresh = true}) {
  FlutterSecureStorage.setMockInitialValues({
    'access_token': token ?? access(),
    'user_id': id,
    'user_role': role,
    if (refresh) 'refresh_token': 'refresh-old',
    'server_ip': '127.0.0.1',
    'theme_mode': 'dark'
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthService auth;
  late ApiService api;
  late BiddingAdapter raw, http;
  late String old;
  setUp(() {
    old = access();
    seed(token: old);
    raw = BiddingAdapter();
    http = BiddingAdapter();
    final transport = Dio();
    transport.httpClientAdapter = raw;
    auth = AuthService.forTesting(transport);
    api = ApiService.forTesting(auth);
    api.dio.httpClientAdapter = http;
    raw.respond = (r) async => reply(credentials());
    http.respond = (r) async => reply({'success': true});
  });
  tearDown(() {
    SocketService().recoverCredentials = null;
    SocketService().disconnect();
    auth.dispose();
    api.dio.close();
    auth.transport.close();
  });
  test('valid access uses secure storage and does not refresh', () async {
    await api.dio.get('/jobs');
    expect(http.requests.single.headers['Authorization'], 'Bearer $old');
    expect(raw.requests, isEmpty);
  });
  test('expired access is refreshed before a new mutation is sent', () async {
    seed(token: access(seconds: -1));
    await api.dio.post('/jobs', data: {'description': 'Real request'});
    expect(raw.requests.single.path, '/auth/refresh');
    expect(raw.requests.single.data, {'refreshToken': 'refresh-old'});
    expect(http.requests.length, 1);
    expect(http.requests.single.headers['Authorization'],
        'Bearer ${(await auth.snapshot())['accessToken']}');
  });
  test('many concurrent expired-token requests share exactly one refresh',
      () async {
    final pending = Completer<ResponseBody>();
    raw.respond = (r) => pending.future;
    http.respond = (r) async => r.headers['Authorization'] == 'Bearer $old'
        ? reply({'success': false, 'code': 'ACCESS_TOKEN_EXPIRED'}, status: 401)
        : reply({'success': true});
    final requests = List.generate(5, (_) => api.dio.get('/jobs'));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      if (raw.requests.isNotEmpty) break;
    }
    expect(raw.requests.length, 1);
    pending.complete(reply(credentials()));
    await Future.wait(requests);
    expect(raw.requests.length, 1);
    expect(http.requests.length, 10);
  });
  test('a late stale 401 reuses tokens from the completed refresh', () async {
    final delayed = Completer<ResponseBody>();
    var calls = 0;
    http.respond = (r) async {
      if (r.headers['Authorization'] != 'Bearer $old') {
        return reply({'success': true});
      }
      if (++calls == 1) return delayed.future;
      return reply({'success': false, 'code': 'ACCESS_TOKEN_EXPIRED'},
          status: 401);
    };
    final first = api.dio.get('/jobs');
    await Future<void>.delayed(Duration.zero);
    await api.dio.get('/jobs');
    delayed.complete(reply({'code': 'ACCESS_TOKEN_EXPIRED'}, status: 401));
    await first;
    expect(raw.requests.length, 1);
  });
  test('retry is bounded to once', () async {
    http.respond =
        (r) async => reply({'code': 'ACCESS_TOKEN_EXPIRED'}, status: 401);
    await expectLater(api.dio.get('/jobs'), throwsA(isA<DioException>()));
    expect(http.requests.length, 2);
    expect(raw.requests.length, 1);
  });
  test(
      'network failure during refresh preserves credentials and supports manual retry',
      () async {
    seed(token: access(seconds: -1));
    raw.respond = (r) async => throw DioException(
        requestOptions: r, type: DioExceptionType.connectionError);
    await expectLater(api.dio.get('/jobs'), throwsA(isA<DioException>()));
    expect((await auth.snapshot())['refreshToken'], 'refresh-old');
    expect(http.requests, isEmpty);
    raw.respond = (r) async => reply(credentials());
    await api.dio.get('/jobs');
    expect(http.requests.length, 1);
  });
  for (final code in [400, 401, 403, 409]) {
    test('refresh rejection $code clears secure session and identity',
        () async {
      raw.respond = (r) async => reply({'success': false}, status: code);
      await expectLater(auth.refresh(), throwsA(isA<SessionFailure>()));
      expect(await auth.getUserId(), null);
      expect(await auth.getUserRole(), null);
      expect(auth.status, SessionStatus.signedOut);
      expect(
          await const FlutterSecureStorage().read(key: 'access_token'), null);
    });
  }
  test(
      'malformed refresh success does not replay an old refresh token endlessly',
      () async {
    raw.respond = (r) async =>
        reply({'success': true, 'accessToken': 'missing-other-fields'});
    await expectLater(auth.refresh(), throwsA(isA<SessionFailure>()));
    expect((await auth.snapshot())['refreshToken'], null);
  });
  test('HTTP authentication failures never refresh recursively', () async {
    http.respond = (r) async => reply({'success': false}, status: 401);
    await expectLater(
        api.dio.post('/auth/login', data: {}), throwsA(isA<DioException>()));
    expect(raw.requests, isEmpty);
    expect((await auth.snapshot())['accessToken'], old);
  });
  test('generic 401 clears identity; ordinary ownership 403 preserves it',
      () async {
    http.respond = (r) async => reply({'success': false}, status: 403);
    await expectLater(
        api.dio.get('/jobs/foreign'), throwsA(isA<DioException>()));
    expect((await auth.snapshot())['accessToken'], old);
    http.respond = (r) async => reply({'success': false}, status: 401);
    await expectLater(api.dio.get('/jobs'), throwsA(isA<DioException>()));
    expect((await auth.snapshot())['accessToken'], null);
    expect(raw.requests, isEmpty);
  });
  test(
      'suspension/role-change account error clears session, unlike domain forbidden',
      () async {
    http.respond =
        (r) async => reply({'code': 'ACCOUNT_UNAVAILABLE'}, status: 403);
    await expectLater(api.dio.get('/jobs'), throwsA(isA<DioException>()));
    expect(auth.status, SessionStatus.signedOut);
    expect(await auth.getUserId(), null);
  });
  test('ambiguous mutation timeout is never replayed', () async {
    http.respond = (r) async => throw DioException(
        requestOptions: r, type: DioExceptionType.receiveTimeout);
    await expectLater(api.dio.post('/jobs', data: {'description': 'Original'}),
        throwsA(isA<DioException>()));
    expect(http.requests.length, 1);
    expect(raw.requests, isEmpty);
  });
  test('mutation retries once only for explicit pre-handler expiry rejection',
      () async {
    http.respond = (r) async => r.extra['authRetried'] == true
        ? reply({
            'success': true,
            'data': {'_id': 'saved-job'}
          })
        : reply({'code': 'ACCESS_TOKEN_EXPIRED'}, status: 401);
    final r = await api.dio.post('/jobs', data: {'description': 'Preserved'});
    expect(r.data['data']['_id'], 'saved-job');
    expect(http.requests.length, 2);
    expect(http.requests.last.data, {'description': 'Preserved'});
  });
  test('multipart bodies are not replayed automatically', () async {
    http.respond =
        (r) async => reply({'code': 'ACCESS_TOKEN_EXPIRED'}, status: 401);
    await expectLater(
        api.dio.post('/jobs', data: FormData.fromMap({'comment': 'Body'})),
        throwsA(isA<DioException>()));
    expect(http.requests.length, 1);
  });
  for (final role in ['user', 'mechanic']) {
    test('startup validates and restores $role identity', () async {
      seed(token: old, role: role);
      raw.respond = (r) async => reply({
            'success': true,
            'user': {'id': 'driver-1', 'role': role, 'name': 'Verified'}
          });
      expect(await auth.recover(), SessionStatus.authenticated);
      expect(auth.role, role);
      expect(raw.requests.single.path, '/auth/session');
    });
  }
  test(
      'startup refreshes expired or missing access credentials before validating',
      () async {
    for (final token in [access(seconds: -1), '']) {
      seed(token: token);
      raw.requests.clear();
      raw.respond = (r) async => reply(r.path == '/auth/refresh'
          ? credentials()
          : {'success': true, 'user': credentials()['user']});
      expect(await auth.recover(), SessionStatus.authenticated);
      expect(
          raw.requests.map((r) => r.path), ['/auth/refresh', '/auth/session']);
    }
  });
  test('offline startup keeps credentials without claiming server validation',
      () async {
    raw.respond = (r) async => throw DioException(
        requestOptions: r, type: DioExceptionType.connectionError);
    expect(await auth.recover(), SessionStatus.offline);
    expect(auth.role, null);
    expect((await auth.snapshot())['refreshToken'], 'refresh-old');
  });
  test('startup rejects changed server account identity or role', () async {
    raw.respond = (r) async => reply({
          'success': true,
          'user': {'id': 'another-person', 'role': 'mechanic'}
        });
    expect(await auth.recover(), SessionStatus.signedOut);
    expect(await auth.getUserId(), null);
  });
  test('login stores one canonical secure snapshot and compatibility mirrors',
      () async {
    raw.respond = (r) async =>
        reply(r.path == '/auth/logout' ? {'success': true} : credentials());
    await auth.authenticate(
        '/auth/login', {'phone': 'fixture', 'password': 'fixture'});
    final stored = await const FlutterSecureStorage().read(key: 'auth_session');
    expect(jsonDecode(stored!)['refreshToken'], 'rotated-new');
    expect(await auth.getUserId(), 'driver-1');
    expect(await const FlutterSecureStorage().read(key: 'user_name'),
        'Persisted person');
  });
  test('late refresh after logout cannot restore old identity', () async {
    final delayed = Completer<ResponseBody>();
    raw.respond = (r) => delayed.future;
    final refresh = auth.refresh();
    final failed = expectLater(refresh, throwsA(isA<SessionFailure>()));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      if (raw.requests.isNotEmpty) break;
    }
    await auth.clearTokens();
    delayed.complete(reply(credentials()));
    await failed;
    expect(await auth.getUserId(), null);
    expect((await auth.snapshot())['refreshToken'], null);
  });
  test('account switching discards previous login response', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final first = Completer<ResponseBody>();
    raw.respond = (r) async => r.data['phone'] == 'first'
        ? await first.future
        : reply(
            credentials(id: 'second-id', role: 'mechanic', marker: 'second'));
    final pending = auth.authenticate('/auth/login', {'phone': 'first'});
    final failed = expectLater(pending, throwsA(isA<SessionFailure>()));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      if (raw.requests.isNotEmpty) break;
    }
    await auth.authenticate('/auth/login', {'phone': 'second'});
    first.complete(reply(credentials(id: 'first-id')));
    await failed;
    expect(await auth.getUserId(), 'second-id');
    expect(await auth.getUserRole(), 'mechanic');
  });
  test('late protected responses cannot populate an account switched session',
      () async {
    final delayed = Completer<ResponseBody>();
    http.respond = (r) => delayed.future;
    final pending = api.dio.get('/jobs');
    final failed = expectLater(pending, throwsA(isA<DioException>()));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      if (http.requests.isNotEmpty) break;
    }
    raw.respond = (r) async => reply(r.path == '/auth/logout'
        ? {'success': true}
        : credentials(id: 'other-person', role: 'mechanic'));
    await auth.authenticate('/auth/login', {});
    delayed.complete(reply({
      'success': true,
      'data': ['old-private-job']
    }));
    await failed;
    expect(await auth.getUserId(), 'other-person');
  });
  test(
      'logout revokes best-effort, clears tokens and preserves non-auth preferences offline',
      () async {
    var ended = 0;
    void listener(dynamic _) {
      ended++;
    }

    SocketService().on('session:ended', listener);
    raw.respond = (r) async => throw DioException(
        requestOptions: r, type: DioExceptionType.connectionError);
    await auth.logout();
    SocketService().off('session:ended', listener);
    expect(ended, 1);
    expect(await auth.getUserId(), null);
    expect(raw.requests.single.path, '/auth/logout');
    expect(await const FlutterSecureStorage().read(key: 'theme_mode'), 'dark');
    expect(
        await const FlutterSecureStorage().read(key: 'server_ip'), '127.0.0.1');
  });
  test('refresh never accepts another account identity from its response',
      () async {
    raw.respond = (r) async => reply(credentials(id: 'foreign'));
    await expectLater(auth.refresh(), throwsA(isA<SessionFailure>()));
    expect(await auth.getUserId(), null);
  });
  testWidgets(
      'offline splash offers retry/sign-in and never opens protected screens',
      (tester) async {
    raw.respond = (r) async => throw DioException(
        requestOptions: r, type: DioExceptionType.connectionError);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      if (utf8.decode(message!.buffer.asUint8List()) == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage({
          for (final font in [
            'DMSans-Regular.ttf',
            'DMSans-Medium.ttf',
            'Syne-ExtraBold.ttf'
          ])
            font: [
              {'asset': font}
            ]
        });
      }
      return ByteData(0);
    });
    final router = GoRouter(initialLocation: '/splash', routes: [
      GoRoute(path: '/splash', builder: (c, s) => SplashScreen(auth: auth)),
      GoRoute(
          path: '/user-home', builder: (c, s) => const Text('Protected home')),
      GoRoute(path: '/login', builder: (c, s) => const Text('Sign in'))
    ]);
    addTearDown(router.dispose);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null));
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Retry session recovery'), findsOneWidget);
    expect(find.text('Sign in instead'), findsOneWidget);
    expect(find.text('Protected home'), findsNothing);
    raw.respond =
        (r) async => reply({'success': true, 'user': credentials()['user']});
    await tester.tap(find.text('Retry session recovery'));
    await tester.pumpAndSettle();
    expect(auth.status, SessionStatus.authenticated);
    expect(find.text('Protected home'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('simultaneous login intents allow only the newest account to persist',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    raw.respond = (r) async =>
        reply(credentials(id: r.data['phone'] as String, role: 'mechanic'));
    final first = auth.authenticate('/auth/login', {'phone': 'first-id'});
    final failed = expectLater(first, throwsA(isA<SessionFailure>()));
    final last = auth.authenticate('/auth/login', {'phone': 'last-id'});
    await failed;
    await last;
    expect(await auth.getUserId(), 'last-id');
  });
  test('a late previous-account 401 never clears newly signed-in credentials',
      () async {
    final hold = Completer<ResponseBody>();
    http.respond = (r) => hold.future;
    final previous = api.dio.get('/jobs');
    final failed = expectLater(previous, throwsA(isA<DioException>()));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      if (http.requests.isNotEmpty) break;
    }
    raw.respond = (r) async => reply(r.path == '/auth/logout'
        ? {'success': true}
        : credentials(id: 'new-person'));
    await auth.authenticate('/auth/login', {});
    hold.complete(reply({'success': false}, status: 401));
    await failed;
    expect(await auth.getUserId(), 'new-person');
    expect(auth.status, SessionStatus.authenticated);
  });

  test(
      'logout hides old credentials immediately while secure deletion is pending',
      () async {
    final ending = auth.clearTokens();
    expect(auth.isClearing, true);
    expect(await auth.getAccessToken(), null);
    expect(await auth.getUserId(), null);
    await ending;
    expect(auth.isClearing, false);
    expect((await auth.snapshot())['refreshToken'], null);
  });
  test(
      'late anonymous 401 during pending login cannot clear its committed identity',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final login = Completer<ResponseBody>(),
        anonymous = Completer<ResponseBody>();
    raw.respond = (r) => login.future;
    http.respond = (r) => anonymous.future;
    final signing = auth.authenticate('/auth/login', {});
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
      if (raw.requests.isNotEmpty) break;
    }
    final pending = api.dio.get('/jobs');
    final failed = expectLater(pending, throwsA(isA<DioException>()));
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
      if (http.requests.isNotEmpty) break;
    }
    login.complete(reply(credentials()));
    await signing;
    anonymous.complete(reply({'success': false}, status: 401));
    await failed;
    expect(await auth.getUserId(), 'driver-1');
    expect(auth.status, SessionStatus.authenticated);
  });
}
