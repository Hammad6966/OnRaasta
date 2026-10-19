import 'package:dio/dio.dart';
import '../models/recommendation.dart';
import 'api_service.dart';
import 'bidding_service.dart';

// Private Job candidate selection belongs to Node, not the mobile client.
class AiService {
  AiService({this.client});
  static final instance = AiService();
  final Dio? client;
  Future<RecommendationPage> recommendations(String jobId) async {
    if (jobId.trim().isEmpty) {
      throw const BidFlowException('Saved job ID is missing.');
    }
    try {
      final response = await (client ?? ApiService.instance.dio).get(
          '/jobs/$jobId/recommendations',
          options: Options(
              receiveTimeout: const Duration(seconds: 7),
              sendTimeout: const Duration(seconds: 3)));
      return RecommendationPage.parse(response.data, jobId);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw BidFlowException(
          switch (status) {
            401 => 'Session expired. Please sign in again.',
            403 => 'You cannot access recommendations for this job.',
            404 => 'This job is no longer available.',
            409 =>
              'Offers or job availability changed. Refresh bids and retry ranking.',
            _ =>
              'Recommendations unavailable. Offers shown in bid ID order; acceptance is still available.',
          },
          status);
    } on FormatException {
      throw const BidFlowException(
          'Recommendations could not be verified. Offers shown in bid ID order.');
    }
  }
}
