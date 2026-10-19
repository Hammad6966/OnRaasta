import 'package:onraasta/models/booking_arguments.dart';
import 'bidding_fixtures.dart';

Map<String, dynamic> assignmentJson(
        {String id = 'job-1', String status = 'accepted'}) =>
    {
      'jobId': id,
      'acceptedBidId': 'bid-1',
      'mechanicId': 'mechanic-1',
      'mechanicUserId': 'mechanic-user-1',
      'userId': 'driver-1',
      'status': status,
      'labourCost': 900.5,
      'partsCost': 200.25,
      'totalCost': 1100.75,
      'eta': 12,
      'job': {
        ...savedJob(accepted: true),
        '_id': id,
        'userId': 'driver-1',
        'status': status
      },
      'bid': bidJson(populated: true, job: id, status: 'accepted'),
      'driver': {'_id': 'driver-1', 'name': 'Saved Customer'},
    };
AcceptedBooking assignment({String id = 'job-1', String status = 'accepted'}) =>
    AcceptedBooking.fromAssignment(assignmentJson(id: id, status: status));
Map<String, dynamic> assignmentHint({String id = 'job-1'}) => {
      'jobId': id,
      'acceptedBidId': 'bid-1',
      'mechanicId': 'mechanic-1',
      'status': 'accepted'
    };
