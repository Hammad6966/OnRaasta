import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onraasta/services/api_service.dart';
import 'package:onraasta/services/foreground_location.dart';
import 'package:onraasta/services/mechanic_service.dart';
import 'package:onraasta/services/socket_service.dart';
import 'bidding_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter original;
  late BiddingAdapter adapter;
  Map<String, dynamic> eligible() => {
        '_id': 'real-mechanic',
        'userId': {'_id': 'real-user', 'name': 'Actual Mechanic'},
        'lat': 31.01,
        'lng': 74,
        'distance': 1.11,
        'serviceRadius': 5,
        'isApproved': true,
        'isOnline': true
      };
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    original = ApiService.instance.dio.httpClientAdapter;
    adapter = BiddingAdapter();
    ApiService.instance.dio.httpClientAdapter = adapter;
  });
  tearDown(() => ApiService.instance.dio.httpClientAdapter = original);
  test(
      'profile authentication errors request sign-in instead of claiming reconnect recovery',
      () async {
    adapter.respond =
        (_) async => apiResponse(null, status: 401, success: false);
    await expectLater(
        MechanicService.instance.profile(),
        throwsA(isA<SocketFailure>()
            .having((error) => error.status, 'status', 401)
            .having((error) => error.message, 'message', contains('sign in'))));
  });
  test('nearby uses actual driver coordinates and real distance/profile IDs',
      () async {
    adapter.respond = (_) async => apiResponse([eligible()]);
    final result = await MechanicService.instance.nearby(GpsPoint(31, 74));
    expect(adapter.requests.single.queryParameters, {'lat': 31.0, 'lng': 74.0});
    expect(result.single['_id'], 'real-mechanic');
    expect(result.single['distance'], 1.11);
  });
  test('invalid, unavailable and out-of-radius mechanics never become markers',
      () async {
    adapter.respond = (_) async => apiResponse([
          eligible(),
          eligible()..['isApproved'] = false,
          eligible()..['isOnline'] = false,
          eligible()..['distance'] = 6,
          eligible()..remove('lat'),
          eligible()..['lng'] = 999,
          eligible()..remove('_id'),
          eligible()..remove('distance'),
          {'lat': 0, 'lng': 0}
        ]);
    expect(
        await MechanicService.instance.nearby(GpsPoint(31, 74)), hasLength(1));
  });
  test('empty nearby result is legitimate and malformed response is an error',
      () async {
    adapter.respond = (_) async => apiResponse([]);
    expect(await MechanicService.instance.nearby(GpsPoint(31, 74)), isEmpty);
    adapter.respond = (_) async => apiResponse({'not': 'list'});
    await expectLater(MechanicService.instance.nearby(GpsPoint(31, 74)),
        throwsA(isA<SocketFailure>()));
  });
  test('network failures and invalid driver GPS do not produce fake results',
      () async {
    adapter.respond =
        (_) async => apiResponse(null, status: 503, success: false);
    await expectLater(MechanicService.instance.nearby(GpsPoint(31, 74)),
        throwsA(isA<DioException>()));
    await expectLater(MechanicService.instance.nearby(GpsPoint(0, 0)),
        throwsA(isA<LocationFailure>()));
    expect(adapter.requests, hasLength(1));
  });
}
