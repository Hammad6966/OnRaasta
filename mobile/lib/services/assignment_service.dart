import 'package:dio/dio.dart';
import '../models/bid_model.dart';
import '../models/booking_arguments.dart';
import 'api_service.dart';

class AssignmentFailure implements Exception {
  final String message;
  final int? status;
  const AssignmentFailure(this.message, [this.status]);
}

class AssignmentService {
  static final instance = AssignmentService();
  final Dio? client;
  AssignmentService({this.client});
  Dio get _dio => client ?? ApiService.instance.dio;
  Future<Object?> _get(String path) async {
    try {
      final response = await _dio.get(path);
      final data = objectMap(response.data);
      if (data['success'] != true) {
        throw const AssignmentFailure(
            'Invalid assignment response. Please retry.');
      }
      return data['data'];
    } on DioException catch (error) {
      throw AssignmentFailure(
          switch (error.response?.statusCode) {
            401 => 'Session expired. Please sign in again.',
            403 =>
              'You do not have access to this assignment. Check account approval and ownership.',
            404 => 'The assigned job could not be found.',
            409 =>
              'Assignment records changed or are not confirmed. Please reload.',
            _ => 'Unable to load assignments. Check your connection and retry.',
          },
          error.response?.statusCode);
    }
  }

  Future<AcceptedBooking> load(String jobId) async {
    if (textValue(jobId) == null) {
      throw const AssignmentFailure('Saved job ID is missing.');
    }
    try {
      final booking =
          AcceptedBooking.fromAssignment(await _get('/jobs/$jobId/assignment'));
      if (booking.jobId != jobId) throw const FormatException();
      return booking;
    } on FormatException {
      throw const AssignmentFailure(
          'Assignment confirmation could not be read. The saved job ID is retained; please retry.');
    }
  }

  Future<bool> isOpen(String jobId) async {
    if (textValue(jobId) == null) {
      throw const AssignmentFailure('Saved job ID is missing.');
    }
    final data = objectMap(await _get('/jobs/$jobId/opportunity'));
    if (objectId(data['jobId']) != jobId || data['isOpen'] is! bool) {
      throw const AssignmentFailure(
          'Job availability could not be confirmed. Please retry.');
    }
    return data['isOpen'] as bool;
  }

  Future<List<AcceptedBooking>> active() async {
    try {
      final data = await _get('/jobs/assignments');
      if (data is! List) throw const FormatException();
      final result = data
          .map(AcceptedBooking.fromAssignment)
          .where((booking) => booking.isActive)
          .toList();
      result.sort((a, b) => a.jobId.compareTo(b.jobId));
      return result;
    } on FormatException {
      throw const AssignmentFailure(
          'Assignment list could not be read. Please retry.');
    }
  }

  Future<List<AcceptedBooking>> recover() async {
    try {
      final data = await _get('/jobs/assignments?includeClosed=true');
      if (data is! List) throw const FormatException();
      return data.map(AcceptedBooking.fromAssignment).toList();
    } on FormatException {
      throw const AssignmentFailure(
          'Saved assignments could not be read. Please retry.');
    }
  }
}
