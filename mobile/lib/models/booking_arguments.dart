import 'bid_model.dart';

class BidSelection {
  final Map<String, dynamic> job;
  final BidModel bid;
  BidSelection({required Map<String, dynamic> job, required this.bid})
      : job = Map.unmodifiable(job) {
    if (objectId(job['_id']) != bid.jobId) {
      throw const FormatException('The bid does not belong to this saved job.');
    }
  }
  static BidSelection? tryParse(Object? extra) {
    if (extra is BidSelection) return extra;
    try {
      final map = objectMap(extra);
      return BidSelection(
          job: objectMap(map['job']),
          bid: map['bid'] is BidModel
              ? map['bid'] as BidModel
              : BidModel.fromJson(map['bid']));
    } on FormatException {
      return null;
    }
  }
}

class AcceptedBooking extends BidSelection {
  final Map<String, dynamic> driver;
  AcceptedBooking(
      {required super.job,
      required super.bid,
      Map<String, dynamic> driver = const {}})
      : driver = Map.unmodifiable(driver) {
    if (bid.status != 'accepted' ||
        !bid.hasValidPrice ||
        objectId(job['acceptedBidId']) != bid.bidId ||
        objectId(job['mechanicId']) != bid.mechanicId ||
        ![
          'accepted',
          'en_route',
          'arrived',
          'in_progress',
          'completed',
          'cancelled'
        ].contains(job['status'])) {
      throw const FormatException('The booking has not been confirmed.');
    }
  }
  String get jobId => bid.jobId;
  bool get isActive => ['accepted', 'en_route', 'arrived', 'in_progress']
      .contains(job['status']);
  factory AcceptedBooking.fromAssignment(Object? value) {
    final data = objectMap(value);
    final selection = BidSelection.tryParse(data);
    if (selection == null ||
        objectId(data['jobId']) != selection.bid.jobId ||
        objectId(data['acceptedBidId']) != selection.bid.bidId ||
        objectId(data['mechanicId']) != selection.bid.mechanicId ||
        objectId(data['mechanicUserId']) != selection.bid.mechanicUserId ||
        objectId(data['userId']) == null ||
        objectId(data['userId']) != objectId(selection.job['userId']) ||
        data['status'] != selection.job['status'] ||
        finiteNumber(data['labourCost']) != selection.bid.labourCost ||
        finiteNumber(data['partsCost']) != selection.bid.partsCost ||
        finiteNumber(data['totalCost']) != selection.bid.totalCost ||
        finiteNumber(data['eta']) != selection.bid.eta) {
      throw const FormatException(
          'Assignment identifiers or prices do not match.');
    }
    final driver = objectMap(data['driver']);
    if (objectId(driver['_id']) != data['userId']) {
      throw const FormatException('Assignment driver does not match.');
    }
    return AcceptedBooking(
        job: selection.job, bid: selection.bid, driver: driver);
  }
  static AcceptedBooking? tryParse(Object? extra) {
    if (extra is AcceptedBooking) return extra;
    if (objectMap(extra).containsKey('jobId')) {
      try {
        return AcceptedBooking.fromAssignment(extra);
      } on FormatException {
        return null;
      }
    }
    final selection = BidSelection.tryParse(extra);
    if (selection == null) return null;
    try {
      return AcceptedBooking(
          job: selection.job,
          bid: selection.bid,
          driver: objectMap(objectMap(extra)['driver']));
    } on FormatException {
      return null;
    }
  }
}
