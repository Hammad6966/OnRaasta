/// Shared representation of populated REST bids and flat server socket bids.
class BidModel {
  final Map<String, dynamic> _data;
  BidModel._(Map<String, dynamic> data) : _data = Map.unmodifiable(data);

  factory BidModel.fromJson(Object? value) {
    final json = objectMap(value);
    final mechanic = objectMap(json['mechanicId']);
    final user = objectMap(mechanic['userId']);
    final data = <String, dynamic>{
      'bidId': objectId(json['_id']) ?? objectId(json['bidId']),
      'jobId': objectId(json['jobId']),
      'mechanicId': objectId(json['mechanicId']),
      'mechanicUserId':
          objectId(mechanic['userId']) ?? objectId(json['mechanicUserId']),
      'mechanicName':
          textValue(user['name']) ?? textValue(json['mechanicName']),
      for (final key in ['labourCost', 'partsCost', 'totalCost', 'eta'])
        key: finiteNumber(json[key]),
      for (final key in ['rating', 'totalJobs', 'reviewCount', 'lat', 'lng'])
        key: finiteNumber(mechanic[key] ?? json[key]),
      'skills': mechanic['skills'] ?? json['skills'],
      'shopAddress': textValue(mechanic['shopAddress'] ?? json['shopAddress']),
      'isApproved': mechanic['isApproved'] ?? json['isApproved'],
      'status': textValue(json['status']),
      'updatedAt': textValue(json['updatedAt']),
      'isNew': json['isNew'] == true,
    }..removeWhere((key, value) => value == null);
    if (['bidId', 'jobId', 'mechanicId'].any((key) => data[key] == null)) {
      throw const FormatException('Bid identifiers are missing.');
    }
    return BidModel._(data);
  }

  String get bidId => _data['bidId'] as String;
  String get jobId => _data['jobId'] as String;
  String get mechanicId => _data['mechanicId'] as String;
  String? get mechanicUserId => textValue(_data['mechanicUserId']);
  String get mechanicName =>
      textValue(_data['mechanicName']) ?? 'Name unavailable';
  double? get labourCost => finiteNumber(_data['labourCost']);
  double? get partsCost => finiteNumber(_data['partsCost']);
  double? get totalCost => finiteNumber(_data['totalCost']);
  int? get eta {
    final value = finiteNumber(_data['eta']);
    return value != null && value > 0 && value == value.roundToDouble()
        ? value.toInt()
        : null;
  }

  double? get rating {
    final value = finiteNumber(_data['rating']);
    return value != null && value >= 0 && value <= 5 ? value : null;
  }

  int? get totalJobs => _count('totalJobs');
  int? get reviewCount => _count('reviewCount');
  int? _count(String key) {
    final value = finiteNumber(_data[key]);
    return value != null && value >= 0 && value == value.roundToDouble()
        ? value.toInt()
        : null;
  }

  bool? get isApproved =>
      _data['isApproved'] is bool ? _data['isApproved'] as bool : null;
  String? get shopAddress => textValue(_data['shopAddress']);
  List<String> get skills => _data['skills'] is List
      ? List.unmodifiable((_data['skills'] as List)
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty))
      : const [];
  String? get status => textValue(_data['status']);
  bool get isNew => _data['isNew'] == true;
  String get priceLabel => money(totalCost);
  String get etaLabel => eta == null ? 'ETA unavailable' : 'ETA $eta min';
  String get ratingLabel => rating?.toStringAsFixed(1) ?? 'Unrated';
  bool get hasValidPrice {
    if (labourCost == null ||
        labourCost! < 500 ||
        partsCost == null ||
        partsCost! < 0 ||
        totalCost == null ||
        totalCost! < 0) {
      return false;
    }
    final componentCents = (labourCost! + partsCost!) * 100;
    final totalCents = totalCost! * 100;
    return componentCents.isFinite &&
        totalCents.isFinite &&
        componentCents.round() == totalCents.round();
  }

  bool get canAccept => status == 'pending' && hasValidPrice;

  /// Enrich partial notifications without losing profile fields or regressing
  /// terminal states when a delayed pending notification arrives.
  BidModel merge(BidModel newer) {
    if (bidId != newer.bidId ||
        jobId != newer.jobId ||
        mechanicId != newer.mechanicId) {
      throw const FormatException('Bid identity changed.');
    }
    final oldTime = DateTime.tryParse(_data['updatedAt'] ?? '');
    final newTime = DateTime.tryParse(newer._data['updatedAt'] ?? '');
    final stale =
        oldTime != null && newTime != null && newTime.isBefore(oldTime);
    final merged =
        stale ? {...newer._data, ..._data} : {..._data, ...newer._data};
    if (status != null && status != 'pending' && newer.status == 'pending') {
      merged['status'] = status;
    }
    return BidModel._(merged);
  }
}

Map<String, dynamic> objectMap(Object? value) =>
    value is Map && value.keys.every((key) => key is String)
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
String? textValue(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
String? objectId(Object? value) =>
    textValue(value) ?? textValue(objectMap(value)['_id']);
double? finiteNumber(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;
String money(num? value) => value == null
    ? 'Price unavailable'
    : 'PKR ${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}';
