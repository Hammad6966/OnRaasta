import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/bid_model.dart';
import 'api_service.dart';

const supportedMechanicSkills = [
  'Engine Repair',
  'Tyre Change',
  'Battery',
  'Brakes',
  'AC Repair',
  'Electrical',
  'Body Work',
  'Towing',
  'Tyre Specialist',
  'Auto Electrician',
  'Engine Specialist',
  'General Mechanic',
  'Brake Specialist',
  'Transmission Specialist',
  'AC Specialist',
  'Suspension Specialist'
];

class ProfileService {
  ProfileService({Dio? dio}) : _dio = dio;
  static final instance = ProfileService();
  static final mechanicChanges = ChangeNotifier();
  final Dio? _dio;
  Dio get dio => _dio ?? ApiService.instance.dio;
  Future<dynamic> request(String method, String path,
      [Map<String, dynamic>? body]) async {
    final response = await dio.request<dynamic>(path,
        data: body, options: Options(method: method));
    final envelope = objectMap(response.data);
    if (envelope['success'] != true || envelope['data'] == null) {
      throw const FormatException('Invalid profile response');
    }
    return envelope['data'];
  }

  Future<Map<String, dynamic>> _record(String path) async {
    final data = objectMap(await request('GET', path));
    if (objectId(data['_id']) == null) {
      throw const FormatException('Profile identity missing');
    }
    return data;
  }

  Future<Map<String, dynamic>> profile() => _record('/users/profile');
  Future<Map<String, dynamic>> mechanic() => _record('/mechanics/profile');
  Future<List<Map<String, dynamic>>> vehicles() async {
    final data = await request('GET', '/users/vehicles');
    if (data is! List) throw const FormatException('Invalid vehicle response');
    return data.map(objectMap).toList();
  }
}

String profileError(Object error) {
  if (error is DioException) {
    switch (error.response?.statusCode) {
      case 400:
        return objectMap(error.response?.data)['message'] as String? ?? 'Check the entered details and try again.';
      case 413:
        return 'File exceeds 8 MB. Choose a smaller file.';
      case 401:
        return 'Please sign in again.';
      case 403:
        return 'Your account cannot perform this action.';
      case 404:
        return 'This record is no longer available. Reload and retry.';
      case 409:
        return objectMap(error.response?.data)['message'] as String? ??
            'The record changed. Reload and retry.';
    }
  }
  return 'Unable to connect. Your changes have not been saved. Please retry.';
}
