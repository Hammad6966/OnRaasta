import 'bid_model.dart';

int? _paisa(double? value) {
  if (value == null || value < 0 || value > 200000000) return null;
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(value.toString());
  if (match == null) return null;
  return int.parse(match[1]!) * 100 +
      int.parse((match[2] ?? '').padRight(2, '0'));
}

int? validBidTotal(BidModel bid) {
  final labour = _paisa(bid.labourCost),
      parts = _paisa(bid.partsCost),
      total = _paisa(bid.totalCost);
  if (labour == null ||
      parts == null ||
      total == null ||
      labour < 50000 ||
      labour > 10000000000 ||
      parts > 10000000000 ||
      labour + parts != total) {
    return null;
  }
  return total;
}

class Recommendation {
  final String bidId, mechanicId;
  final int totalMinor;
  final double score, distanceKm;
  final double? rating;
  final Map<String, double> components;
  final List<String> skills, matchedSkills;
  Recommendation(Object? raw)
      : bidId = objectId(objectMap(raw)['bidId']) ?? '',
        mechanicId = objectId(objectMap(raw)['mechanicId']) ?? '',
        totalMinor = objectMap(raw)['totalMinor'] is int
            ? objectMap(raw)['totalMinor'] as int
            : -1,
        score = finiteNumber(objectMap(raw)['score']) ?? -1,
        distanceKm = finiteNumber(objectMap(raw)['distanceKm']) ?? -1,
        rating = finiteNumber(objectMap(raw)['rating']),
        components = objectMap(objectMap(raw)['components'])
            .map((k, v) => MapEntry(k, finiteNumber(v) ?? -1)),
        skills = (objectMap(raw)['skills'] as List? ?? [])
            .whereType<String>()
            .toList(),
        matchedSkills = (objectMap(raw)['matchedSkills'] as List? ?? [])
            .whereType<String>()
            .toList() {
    if (bidId.isEmpty ||
        mechanicId.isEmpty ||
        totalMinor < 50000 ||
        totalMinor > 20000000000 ||
        score < 0 ||
        score > 1 ||
        distanceKm < 0 ||
        distanceKm > 100 ||
        (rating != null && (rating! < 0 || rating! > 5)) ||
        !['skillMatch', 'distanceScore', 'ratingScore', 'priceScore'].every(
            (k) =>
                components[k] != null &&
                components[k]! >= 0 &&
                components[k]! <= 1)) {
      throw const FormatException('Invalid recommendation');
    }
    final weighted = 0.35 * components['skillMatch']! +
        0.25 * components['distanceScore']! +
        0.25 * components['ratingScore']! +
        0.15 * components['priceScore']!;
    if ((weighted - score).abs() > 1e-8) {
      throw const FormatException('Inconsistent recommendation score');
    }
  }
  bool matches(BidModel bid) =>
      bid.bidId == bidId &&
      bid.mechanicId == mechanicId &&
      bid.status == 'pending' &&
      validBidTotal(bid) == totalMinor;
  String get explanation =>
      '${(score * 100).toStringAsFixed(1)} / 100 rules score; ${components['skillMatch'] == 1 ? 'declared skill match' : components['skillMatch'] == 0.5 ? 'general skill fallback' : 'no declared skill match'}';
}

class RecommendationPage {
  final String jobId;
  final List<Recommendation> rankings;
  final DateTime? expiresAt;
  final bool truncated;
  RecommendationPage(
      {required this.jobId,
      required this.rankings,
      required this.expiresAt,
      this.truncated = false});
  factory RecommendationPage.parse(Object? raw, String expectedJob) {
    final envelope = objectMap(raw), data = objectMap(objectMap(raw)['data']);
    if (envelope['success'] != true ||
        objectId(data['jobId']) != expectedJob ||
        data['policyVersion'] != 'weighted_rules_v1' ||
        data['distanceType'] != 'straight_line_km' ||
        data['rankings'] is! List) {
      throw const FormatException('Invalid recommendation response');
    }
    final ranks = (data['rankings'] as List).map(Recommendation.new).toList();
    final expires = DateTime.tryParse(data['expiresAt'] as String? ?? '');
    if (ranks.length > 100 ||
        ranks.map((r) => r.bidId).toSet().length != ranks.length ||
        ranks.isNotEmpty && expires == null) {
      throw const FormatException('Invalid ranking snapshot');
    }
    for (var i = 1; i < ranks.length; i++) {
      if (ranks[i - 1].score < ranks[i].score ||
          ranks[i - 1].score == ranks[i].score &&
              ranks[i - 1].bidId.compareTo(ranks[i].bidId) > 0) {
        throw const FormatException('Invalid ranking order');
      }
    }
    return RecommendationPage(
        jobId: expectedJob,
        rankings: ranks,
        expiresAt: expires,
        truncated: data['truncated'] == true);
  }
}

List<BidModel> sortedOffers(List<BidModel> bids, int tab,
    [List<Recommendation> ranks = const []]) {
  final order = {for (var i = 0; i < ranks.length; i++) ranks[i].bidId: i};
  int nullable(num? a, num? b) => a == null
      ? b == null
          ? 0
          : 1
      : b == null
          ? -1
          : a.compareTo(b);
  return [...bids]..sort((a, b) {
      final comparison = switch (tab) {
        1 => nullable(validBidTotal(a), validBidTotal(b)),
        2 => nullable(a.eta, b.eta),
        _ => nullable(order[a.bidId], order[b.bidId]),
      };
      return comparison != 0 ? comparison : a.bidId.compareTo(b.bidId);
    });
}
