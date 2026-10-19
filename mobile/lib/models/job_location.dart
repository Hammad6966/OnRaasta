import '../models/bid_model.dart';

class JobLocation {
  final String jobId, mechanicId;
  final double lat, lng;
  final double? accuracy;
  final DateTime observedAt, receivedAt;
  JobLocation._(this.jobId, this.mechanicId, this.lat, this.lng, this.accuracy,
      this.observedAt, this.receivedAt);
  factory JobLocation.parse(Object? input) {
    final data = objectMap(input),
        id = objectId(objectMap(input)['jobId']),
        mechanic = objectId(data['mechanicId']);
    final lat = finiteNumber(data['lat']),
        lng = finiteNumber(data['lng']),
        accuracy = finiteNumber(data['accuracy']);
    final observed = DateTime.tryParse(textValue(data['observedAt']) ?? ''),
        received = DateTime.tryParse(textValue(data['receivedAt']) ?? '');
    if (id == null ||
        mechanic == null ||
        lat == null ||
        lng == null ||
        lat.abs() > 90 ||
        lng.abs() > 180 ||
        lat == 0 && lng == 0 ||
        data['accuracy'] != null &&
            (accuracy == null || accuracy < 0 || accuracy > 100) ||
        observed == null ||
        received == null ||
        observed.isAfter(received.add(const Duration(seconds: 10)))) {
      throw const FormatException('Invalid mechanic observation');
    }
    return JobLocation._(id, mechanic, lat, lng, accuracy, observed, received);
  }
  bool fresh(DateTime now) =>
      now.difference(observedAt) <= const Duration(seconds: 60) &&
      observedAt.difference(now) <= const Duration(seconds: 10);
}
