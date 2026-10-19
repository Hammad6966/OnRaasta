import 'bid_model.dart';

int commissionPaisa(int grossPaisa) => (grossPaisa * 15 + 50) ~/ 100;

String pkr(Object? minor) {
  final value = minor is int
      ? BigInt.from(minor)
      : minor is String
          ? BigInt.tryParse(minor)
          : null;
  if (value == null || value < BigInt.zero) return 'Amount unavailable';
  final whole = (value ~/ BigInt.from(100))
      .toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  return 'PKR $whole.${(value % BigInt.from(100)).toString().padLeft(2, '0')}';
}

String historyDate(Object? value) {
  final date = value is String ? DateTime.tryParse(value)?.toLocal() : null;
  return date == null
      ? 'Date unavailable'
      : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class HistoryJob {
  final Map<String, dynamic> data;
  HistoryJob(Object? raw) : data = objectMap(raw) {
    if (objectId(data['_id']) == null ||
        !const [
          'pending',
          'bidding',
          'accepted',
          'en_route',
          'arrived',
          'in_progress',
          'completed',
          'cancelled'
        ].contains(data['status'])) {
      throw const FormatException('Invalid history job');
    }
  }
  String get id => data['_id'] as String;
  String get status => data['status'] as String;
  String get description =>
      textValue(data['description']) ?? 'Description unavailable';
  String get mechanicName =>
      textValue(objectMap(data['mechanic'])['name']) ?? 'Mechanic unavailable';
  Map<String, dynamic> get pricing => objectMap(data['pricing']);
  String get total => pkr(pricing['totalMinor']);
  String get date => historyDate(
      status == 'completed' ? data['completedAt'] : data['createdAt']);
}

class HistoryPage {
  final List<HistoryJob> jobs;
  final int page;
  final bool hasMore;
  final Map<String, dynamic>? summary;
  final int undated;
  const HistoryPage(
      {required this.jobs,
      required this.page,
      required this.hasMore,
      this.summary,
      this.undated = 0});
  factory HistoryPage.parse(Object? raw, {bool earnings = false}) {
    final envelope = objectMap(raw);
    final payload = earnings ? objectMap(envelope['data']) : envelope;
    final rows = earnings ? payload['jobs'] : envelope['data'];
    final pagination = objectMap(payload['pagination']);
    if (envelope['success'] != true ||
        rows is! List ||
        pagination['page'] is! int ||
        pagination['hasMore'] is! bool) {
      throw const FormatException('Invalid history response');
    }
    final summary = earnings ? objectMap(payload['summary']) : null;
    if (earnings &&
        (payload['basis'] != 'booked_not_paid' ||
            payload['currency'] != 'PKR' ||
            summary!['completedJobs'] is! int ||
            summary['months'] is! List)) {
      throw const FormatException('Invalid booked amounts');
    }
    return HistoryPage(
        jobs: rows.map(HistoryJob.new).toList(),
        page: pagination['page'] as int,
        hasMore: pagination['hasMore'] as bool,
        summary: summary,
        undated: payload['undatedCompletedJobs'] as int? ?? 0);
  }
}
