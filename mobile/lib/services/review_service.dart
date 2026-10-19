import 'package:dio/dio.dart';
import '../models/bid_model.dart';
import '../models/booking_arguments.dart';
import 'api_service.dart';
import 'assignment_service.dart';

class ReviewFailure implements Exception {
  final String message;
  final int? status;
  const ReviewFailure(this.message, [this.status]);
}

class ReviewPage {
  final String mechanicId;
  final double rating;
  final int count, page;
  final Map<int, int> distribution;
  final List<Map<String, dynamic>> reviews;
  final bool hasMore;
  ReviewPage.fromJson(Object? value)
      : mechanicId = objectId(objectMap(value)['mechanicId']) ??
            (throw const FormatException()),
        rating = finiteNumber(objectMap(value)['rating']) ??
            (throw const FormatException()),
        count = objectMap(value)['reviewCount'] as int,
        page = objectMap(value)['page'] as int,
        hasMore = objectMap(value)['hasMore'] as bool,
        distribution = {
          for (var i = 1; i <= 5; i++)
            i: objectMap(objectMap(value)['distribution'])['$i'] as int
        },
        reviews = (objectMap(value)['reviews'] as List).map((r) {
          final data = objectMap(r);
          if (data['stars'] is! int ||
              (data['stars'] as int) < 1 ||
              (data['stars'] as int) > 5 ||
              DateTime.tryParse(data['createdAt'] as String? ?? '') == null ||
              data['comment'] is! String ||
              data['tags'] is! List ||
              (data['tags'] as List).any((t) => t is! String)) {
            throw const FormatException();
          }
          return data;
        }).toList() {
    if (rating < 0 ||
        rating > 5 ||
        count < 0 ||
        distribution.values.any((n) => n < 0) ||
        distribution.values.fold(0, (int a, b) => a + b) != count) {
      throw const FormatException();
    }
  }
}

class ReviewService {
  static const tags = [
    'Professional',
    'On Time',
    'Fair Price',
    'Quality Work',
    'Friendly',
    'Clean Work',
    'Skilled',
    'Fast Service'
  ];
  static final instance = ReviewService();
  final Dio? client;
  final Future<AcceptedBooking> Function(String)? loadAssignment;
  ReviewService({this.client, this.loadAssignment});
  Dio get _dio => client ?? ApiService.instance.dio;
  Future<AcceptedBooking> assignment(String id) =>
      (loadAssignment ?? AssignmentService.instance.load)(id);
  Future<Object?> _request(String path, {Map<String, dynamic>? data}) async {
    try {
      final r = data == null
          ? await _dio.get(path)
          : await _dio.post(path, data: data);
      final body = objectMap(r.data);
      if (body['success'] != true || body['data'] is! Map) {
        throw const ReviewFailure(
            'Review response could not be confirmed. Please retry.');
      }
      return body['data'];
    } on DioException catch (e) {
      throw ReviewFailure(
          switch (e.response?.statusCode) {
            400 => 'Check the rating, tags and 300-character comment limit.',
            401 => 'Session expired. Please sign in again.',
            403 => 'You do not have permission to access these reviews.',
            404 => 'The saved job or mechanic could not be found.',
            409 =>
              'This job changed or has already been reviewed. Reloading saved state.',
            _ =>
              'Unable to reach the server. Your input is retained; please retry.',
          },
          e.response?.statusCode);
    }
  }

  Future<ReviewPage> reviews(String id, {int page = 1}) async {
    if (objectId(id) == null) {
      throw const ReviewFailure('Mechanic ID is missing.');
    }
    try {
      final result = ReviewPage.fromJson(
          await _request('/mechanics/$id/reviews?page=$page&limit=10'));
      if (result.mechanicId != id || result.page != page) {
        throw const FormatException();
      }
      return result;
    } on ReviewFailure {
      rethrow;
    } catch (_) {
      throw const ReviewFailure('Reviews could not be read. Please retry.');
    }
  }

  Future<void> submit(String jobId, String mechanicId, int stars,
      List<String> tags, String comment) async {
    try {
      final data = objectMap(await _request('/jobs/$jobId/review',
          data: {'stars': stars, 'tags': tags, 'comment': comment.trim()}));
      final review = objectMap(data['review']);
      final reputation = objectMap(data['reputation']);
      if (objectId(data['jobId']) != jobId ||
          objectId(data['mechanicId']) != mechanicId ||
          review['stars'] != stars ||
          DateTime.tryParse(review['createdAt'] as String? ?? '') == null ||
          finiteNumber(reputation['rating']) == null ||
          finiteNumber(reputation['rating'])! < 1 ||
          finiteNumber(reputation['rating'])! > 5 ||
          reputation['reviewCount'] is! int ||
          (reputation['reviewCount'] as int) < 1) {
        throw const ReviewFailure(
            'Review confirmation could not be read. Reload before retrying.');
      }
    } on ReviewFailure {
      rethrow;
    } catch (_) {
      throw const ReviewFailure(
          'Review confirmation could not be read. Reload before retrying.');
    }
  }
}
