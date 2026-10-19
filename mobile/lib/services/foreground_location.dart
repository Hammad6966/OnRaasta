import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationFailure implements Exception {
  final String message;
  const LocationFailure(this.message);
}

class GpsPoint {
  final double lat, lng;
  final DateTime observedAt;
  final double? accuracy;
  GpsPoint(this.lat, this.lng, {DateTime? observedAt, this.accuracy})
      : observedAt = observedAt ?? DateTime.now();
  bool get valid =>
      lat.isFinite &&
      lng.isFinite &&
      lat.abs() <= 90 &&
      lng.abs() <= 180 &&
      !(lat == 0 && lng == 0);
  bool get fresh =>
      valid &&
      DateTime.now().difference(observedAt).abs() < const Duration(seconds: 60);
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

abstract class ForegroundLocation {
  Future<GpsPoint> current();
  Stream<GpsPoint> positions();
  Stream<bool> serviceChanges();
}

class DeviceForegroundLocation implements ForegroundLocation {
  static final ForegroundLocation shared =
      SharedForegroundLocation(DeviceForegroundLocation());
  @override
  Future<GpsPoint> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
          'Location services are disabled. Enable GPS in device settings.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationFailure(
          'Location permission is required. Allow location access in app settings.');
    }
    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15));
      final point = GpsPoint(position.latitude, position.longitude,
          observedAt: position.timestamp, accuracy: position.accuracy);
      if (!point.fresh) {
        throw const LocationFailure(
            'GPS did not return a valid fresh position. Please retry outdoors.');
      }
      return point;
    } on LocationFailure {
      rethrow;
    } catch (_) {
      throw const LocationFailure(
          'Unable to acquire GPS. Check location access and retry.');
    }
  }

  @override
  Stream<GpsPoint> positions() {
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 25,
            intervalDuration: const Duration(seconds: 10))
        : const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 25);
    return Geolocator.getPositionStream(locationSettings: settings).map(
        (position) => GpsPoint(position.latitude, position.longitude,
            observedAt: position.timestamp, accuracy: position.accuracy));
  }

  @override
  Stream<bool> serviceChanges() => Geolocator.getServiceStatusStream()
      .map((status) => status == ServiceStatus.enabled);
}

/// Reference-counted native streams. No listeners means no GPS subscription.
class SharedForegroundLocation implements ForegroundLocation {
  final ForegroundLocation source;
  late final _SharedStream<GpsPoint> _positions;
  late final _SharedStream<bool> _services;
  Future<GpsPoint>? _current;
  SharedForegroundLocation(this.source) {
    _positions = _SharedStream(source.positions);
    _services = _SharedStream(source.serviceChanges);
  }
  @override
  Future<GpsPoint> current() async {
    final pending = _current ??= source.current();
    try {
      return await pending;
    } finally {
      if (identical(_current, pending)) _current = null;
    }
  }

  @override
  Stream<GpsPoint> positions() => _positions.controller.stream;
  @override
  Stream<bool> serviceChanges() => _services.controller.stream;
}

class _SharedStream<T> {
  final Stream<T> Function() source;
  late final StreamController<T> controller;
  StreamSubscription<T>? _subscription;
  Future<void> _stopped = Future.value();
  int _generation = 0;
  _SharedStream(this.source) {
    controller =
        StreamController<T>.broadcast(onListen: _listen, onCancel: _cancel);
  }
  void _listen() async {
    final generation = ++_generation;
    await _stopped;
    if (generation != _generation || !controller.hasListener) return;
    try {
      _subscription = source().listen(controller.add,
          onError: controller.addError,
          onDone: () => controller.addError(const LocationFailure(
              'GPS stream ended. Retry foreground location.')));
    } catch (error, stack) {
      controller.addError(error, stack);
    }
  }

  void _cancel() {
    ++_generation;
    final old = _subscription;
    _subscription = null;
    _stopped = old?.cancel() ?? Future.value();
  }
}
