import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
// Existing plugin platform interface isolates permission/GPS behavior.
// ignore: depend_on_referenced_packages
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:onraasta/services/foreground_location.dart';

class _LocationPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  int requests = 0, reads = 0;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    reads++;
    return Position(
        latitude: 31,
        longitude: 74,
        timestamp: DateTime.now(),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0);
  }
}

void main() {
  late GeolocatorPlatform original;
  late _LocationPlatform platform;
  setUp(() {
    original = GeolocatorPlatform.instance;
    platform = _LocationPlatform();
    GeolocatorPlatform.instance = platform;
  });
  tearDown(() => GeolocatorPlatform.instance = original);
  test('disabled services produce clear instructions without acquiring GPS',
      () async {
    platform.enabled = false;
    await expectLater(
        DeviceForegroundLocation().current(),
        throwsA(isA<LocationFailure>()
            .having((e) => e.message, 'message', contains('Enable GPS'))));
    expect(platform.reads, 0);
  });
  test('denied permission never yields fallback coordinates', () async {
    platform.permission = LocationPermission.denied;
    await expectLater(
        DeviceForegroundLocation().current(), throwsA(isA<LocationFailure>()));
    expect(platform.requests, 1);
    expect(platform.reads, 0);
  });
  test('permanently denied permission points to settings without reprompting',
      () async {
    platform.permission = LocationPermission.deniedForever;
    await expectLater(
        DeviceForegroundLocation().current(),
        throwsA(isA<LocationFailure>()
            .having((e) => e.message, 'message', contains('settings'))));
    expect(platform.requests, 0);
    expect(platform.reads, 0);
  });
  test('foreground permission returns real platform coordinates', () async {
    final point = await DeviceForegroundLocation().current();
    expect(point.lat, 31);
    expect(point.lng, 74);
    expect(point.fresh, true);
    expect(platform.reads, 1);
  });
}
