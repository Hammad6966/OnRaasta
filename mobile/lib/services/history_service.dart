import 'package:dio/dio.dart';
import '../models/history_models.dart';
import '../models/bid_model.dart';
import 'api_service.dart';

class HistoryService {
  HistoryService({this.client});
  static final instance = HistoryService();
  final Dio? client;
  Dio get dio => client ?? ApiService.instance.dio;
  Future<HistoryPage> fetch(
      {bool mechanic = false,
      bool earnings = false,
      int page = 1,
      String? status,
      String? from,
      String? to}) async {
    final response = await dio.get(
        earnings
            ? '/mechanics/earnings'
            : mechanic
                ? '/mechanics/history'
                : '/jobs',
        queryParameters: {
          'page': page,
          'limit': 20,
          if (status != null) 'status': status,
          if (from != null) 'from': from,
          if (to != null) 'to': to,
        });
    return HistoryPage.parse(response.data, earnings: earnings);
  }

  Future<Map<String, dynamic>> detail(String id) async {
    final response = await dio.get('/jobs/$id');
    final envelope = objectMap(response.data),
        job = objectMap(objectMap(response.data)['data']);
    if (envelope['success'] != true || objectId(job['_id']) != id) {
      throw const FormatException('Job could not be verified');
    }
    return job;
  }
}
