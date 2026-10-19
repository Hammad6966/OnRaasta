import 'package:dio/dio.dart';
import '../models/bid_model.dart';
import 'api_service.dart';
import 'foreground_location.dart';
import 'socket_service.dart';

class MechanicService {
  static final instance = MechanicService();
  Future<Object?> _get(String path, [Map<String, dynamic>? query]) async {
    final Response<dynamic> response;
    try {
      response =
          await ApiService.instance.dio.get(path, queryParameters: query);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const SocketFailure(
            'Session expired. Please sign in again.', 401);
      }
      if (error.response?.statusCode == 403) {
        throw const SocketFailure(
            'Mechanic access denied. Check account approval and status.', 403);
      }
      rethrow;
    }
    final envelope = objectMap(response.data);
    if (envelope['success'] != true) {
      throw const SocketFailure(
          'Server returned invalid mechanic information.');
    }
    return envelope['data'];
  }

  Future<Map<String, dynamic>> profile() async {
    final data = objectMap(await _get('/mechanics/profile'));
    if (objectId(data['_id']) == null || data['isApproved'] is! bool) {
      throw const SocketFailure('Mechanic profile is unavailable.');
    }
    return data;
  }

  Future<List<dynamic>> requests() async {
    final data = await _get('/mechanics/requests');
    if (data is! List) {
      throw const SocketFailure('Invalid nearby requests response.');
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> nearby(GpsPoint point) async {
    if (!point.valid) {
      throw const LocationFailure(
          'Valid location is required for nearby discovery.');
    }
    final data = await _get('/mechanics/nearby', point.toJson());
    if (data is! List) {
      throw const SocketFailure('Invalid nearby mechanics response.');
    }
    final result = <Map<String, dynamic>>[];
    for (final raw in data) {
      final item = objectMap(raw);
      final lat = finiteNumber(item['lat']),
          lng = finiteNumber(item['lng']),
          distance = finiteNumber(item['distance']),
          radius = finiteNumber(item['serviceRadius']);
      if (objectId(item['_id']) == null ||
          lat == null ||
          lng == null ||
          !GpsPoint(lat, lng).valid ||
          distance == null ||
          distance < 0 ||
          radius == null ||
          radius < 1 ||
          radius > 100 ||
          distance > radius ||
          item['isApproved'] != true ||
          item['isOnline'] != true) {
        continue;
      }
      result.add(item);
    }
    return result;
  }
}
