import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

Map<String, dynamic> savedJob({bool accepted = false}) => {
      '_id': 'job-1',
      'status': accepted ? 'accepted' : 'bidding',
      if (accepted) 'acceptedBidId': 'bid-1',
      if (accepted) 'mechanicId': 'mechanic-1',
      'description': 'Battery failure',
      'location': {'lat': 33.7, 'lng': 73.1},
      'aiDiagnosis': {'fault_class': 'dead_battery'},
      'vehicleId': 'vehicle-1',
      'photos': ['https://example.test/photo.png'],
    };

Map<String, dynamic> bidJson(
        {bool populated = false,
        String id = 'bid-1',
        String job = 'job-1',
        String status = 'pending'}) =>
    {
      '_id': id,
      'jobId': job,
      'mechanicId': populated
          ? {
              '_id': 'mechanic-1',
              'userId': {'_id': 'mechanic-user-1', 'name': 'Ali Khan'},
              'skills': ['Battery', 'Electrical'],
              'rating': 4.7,
              'totalJobs': 21,
              'isApproved': true,
              'shopAddress': 'Workshop address',
            }
          : 'mechanic-1',
      'labourCost': 900.5,
      'partsCost': 200.25,
      'totalCost': 1100.75,
      'eta': 12,
      'status': status,
    };

Map<String, dynamic> socketBid({String id = 'bid-1', String job = 'job-1'}) => {
      ...bidJson(id: id, job: job)..remove('_id'),
      'bidId': id,
      'mechanicName': 'Ali Khan',
      'rating': 4.7,
      'skills': ['Battery'],
      'isNew': true,
    };

class BiddingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  late Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody apiResponse(Object? data,
        {int status = 200, bool success = true}) =>
    ResponseBody.fromString(
        jsonEncode({'success': success, 'data': data}), status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
