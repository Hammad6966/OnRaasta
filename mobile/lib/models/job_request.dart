import 'bid_model.dart';

class JobRequest {
  final Map<String, dynamic> _data;
  bool isNew = true;
  JobRequest._(this._data);
  factory JobRequest.fromJson(Map<String, dynamic> json) {
    final id = objectId(json['jobId']) ?? objectId(json['_id']);
    if (id == null) throw const FormatException('Saved job ID is missing.');
    return JobRequest._(Map.unmodifiable({...json, 'jobId': id}));
  }
  String get jobId => _data['jobId'] as String;
  String get description =>
      textValue(_data['description']) ?? 'Description unavailable';
  double? get distance => finiteNumber(_data['distance']);
  String get distanceLabel => distance != null && distance! >= 0
      ? '${distance!.toStringAsFixed(1)} km away'
      : 'Distance unavailable';
  Map<String, dynamic>? get aiDiagnosis =>
      _data['aiDiagnosis'] is Map ? objectMap(_data['aiDiagnosis']) : null;
  String? get faultLabel =>
      textValue(aiDiagnosis?['fault_class'])?.replaceAll('_', ' ');
  String? get costMin => aiDiagnosis?['cost_min']?.toString();
  String? get costMax => aiDiagnosis?['cost_max']?.toString();
  String get timeAgo {
    final date = DateTime.tryParse(textValue(_data['createdAt']) ?? '');
    if (date == null) return 'Time unavailable';
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  Map<String, dynamic> toJson() => Map.of(_data);
}
