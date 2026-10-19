import 'package:dio/dio.dart';
import '../models/bid_model.dart';
import '../models/booking_arguments.dart';
import 'api_service.dart';

class BidFlowException implements Exception {
  final String message;
  final int? statusCode;
  const BidFlowException(this.message, [this.statusCode]);
}

class BiddingService {
  static final instance = BiddingService();
  final Dio? _client;
  final Set<String> _acceptingJobs = {};
  BiddingService({Dio? dio}) : _client = dio;
  Dio get _dio => _client ?? ApiService.instance.dio;

  Object? _data(Response response) {
    final envelope = objectMap(response.data);
    if (envelope['success'] != true || !envelope.containsKey('data')) {
      throw const BidFlowException(
          'The server returned an invalid response. Please refresh.');
    }
    return envelope['data'];
  }

  Future<List<BidModel>> loadBids(String jobId) async {
    if (textValue(jobId) == null) {
      throw const BidFlowException('The saved job ID is missing.');
    }
    try {
      final data =
          _data(await _dio.get('/bids', queryParameters: {'jobId': jobId}));
      if (data is! List) throw const FormatException();
      return data
          .map(BidModel.fromJson)
          .where((bid) => bid.jobId == jobId)
          .toList();
    } on DioException catch (e) {
      throw _requestError(e);
    } on FormatException {
      throw const BidFlowException(
          'Bid information could not be read. Please refresh.');
    }
  }

  /// Shared guard for both screens. Reopen an already accepted bid through reads
  /// after a confirmation failure; never repeat its PATCH or guess its job ID.
  Future<AcceptedBooking?> accept(BidSelection selection) async {
    final id = selection.bid.jobId;
    if (!_acceptingJobs.add(id)) return null;
    try {
      BidModel bid;
      if (selection.bid.status == 'accepted') {
        final bids = await loadBids(id);
        bid = bids.firstWhere((b) => b.bidId == selection.bid.bidId,
            orElse: () => throw const BidFlowException(
                'This bid is no longer available.', 409));
      } else {
        if (!selection.bid.canAccept) {
          throw const BidFlowException('This bid is no longer available.', 409);
        }
        final confirmed = BidModel.fromJson(
            _data(await _dio.patch('/bids/${selection.bid.bidId}/accept')));
        if (confirmed.bidId != selection.bid.bidId ||
            confirmed.jobId != id ||
            confirmed.mechanicId != selection.bid.mechanicId ||
            confirmed.status != 'accepted' ||
            !confirmed.hasValidPrice) {
          throw const FormatException();
        }
        bid = selection.bid.merge(confirmed);
      }
      final job = objectMap(_data(await _dio.get('/jobs/$id')));
      return AcceptedBooking(job: job, bid: bid);
    } on DioException catch (e) {
      throw _requestError(e);
    } on FormatException {
      throw const BidFlowException(
          'Booking confirmation could not be read. Refresh bids before trying again.');
    } finally {
      _acceptingJobs.remove(id);
    }
  }

  BidFlowException _requestError(DioException error) {
    final status = error.response?.statusCode;
    final message = switch (status) {
      401 => 'Your session has expired. Please sign in again.',
      403 => 'You are not allowed to access or accept this bid.',
      404 => 'This job or bid is no longer available.',
      409 =>
        'This offer has changed or another bid was accepted. Refreshing bids.',
      _ => 'Unable to reach the bidding service. Please try again.',
    };
    return BidFlowException(message, status);
  }
}
