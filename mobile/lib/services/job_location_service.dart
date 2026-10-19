import 'package:dio/dio.dart';
import '../models/bid_model.dart';
import '../models/job_location.dart';
import 'api_service.dart';

class JobLocationSnapshot {
  final String jobId;
  final bool allowed;
  final JobLocation? location;
  JobLocationSnapshot(this.jobId, this.allowed, this.location);
}

class JobLocationService {
  static final instance = JobLocationService();
  final Dio? client;
  JobLocationService({this.client});
  Future<JobLocationSnapshot> latest(String id) async {
    final response =
        await (client ?? ApiService.instance.dio).get('/jobs/$id/location');
    final envelope = objectMap(response.data),
        data = objectMap(envelope['data']);
    if (envelope['success'] != true ||
        objectId(data['jobId']) != id ||
        data['trackingAllowed'] is! bool) {
      throw const FormatException('Invalid tracking snapshot');
    }
    final point =
        data['location'] == null ? null : JobLocation.parse(data['location']);
    if (point != null && point.jobId != id) {
      throw const FormatException('Unrelated job location');
    }
    return JobLocationSnapshot(id, data['trackingAllowed'] == true, point);
  }
}
