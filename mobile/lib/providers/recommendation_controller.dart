import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/bid_model.dart';
import '../models/recommendation.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/bidding_service.dart';

class RecommendationController extends ChangeNotifier {
  RecommendationController(
      {required this.jobId,
      Future<RecommendationPage> Function(String)? load,
      AuthService? auth,
      this.debounce = const Duration(milliseconds: 300)})
      : load = load ?? AiService.instance.recommendations,
        auth = auth ?? AuthService.instance {
    _epoch = this.auth.epoch;
    this.auth.addListener(_session);
  }
  final String jobId;
  final Future<RecommendationPage> Function(String) load;
  final AuthService auth;
  final Duration debounce;
  List<Recommendation> rankings = [];
  List<BidModel> _bids = [];
  bool loading = false, truncated = false, _disposed = false;
  String? error;
  String _fingerprint = '';
  int _generation = 0, _epoch = 0;
  int? _inFlight;
  Timer? _delay, _expiry;
  bool _valid(int g) =>
      !_disposed &&
      g == _generation &&
      _epoch == auth.epoch &&
      !auth.isClearing;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _session() {
    if (_epoch == auth.epoch && !auth.isClearing) return;
    _epoch = auth.epoch;
    _generation++;
    _delay?.cancel();
    _expiry?.cancel();
    _bids = [];
    _fingerprint = '';
    truncated = false;
    _inFlight = null;
    rankings = [];
    loading = false;
    error = 'Session changed. Please sign in again.';
    _notify();
  }

  void updateBids(List<BidModel> bids) {
    if (_disposed) return;
    final ordered = bids.where((b) => b.jobId == jobId).toList()
      ..sort((a, b) => a.bidId.compareTo(b.bidId));
    final fingerprint = jsonEncode(ordered
        .map((b) => [
              b.bidId,
              b.mechanicId,
              b.status,
              b.labourCost,
              b.partsCost,
              b.totalCost,
              b.rating,
              b.skills
            ])
        .toList());
    _bids = ordered;
    if (fingerprint == _fingerprint) return;
    _fingerprint = fingerprint;
    _generation++;
    _delay?.cancel();
    _expiry?.cancel();
    rankings = [];
    truncated = false;
    error = null;
    loading = false;
    if (_bids.any((b) => b.status == 'pending' && validBidTotal(b) != null)) {
      loading = true;
      _delay = Timer(debounce, refresh);
    }
    _notify();
  }

  void invalidate() {
    _generation++;
    _delay?.cancel();
    _expiry?.cancel();
    _fingerprint = '';
    rankings = [];
    truncated = false;
    loading = false;
    error = 'Offers changed. Ranking must be refreshed.';
    _notify();
  }

  Future<void> refresh() async {
    if (_disposed ||
        auth.isClearing ||
        jobId.isEmpty ||
        _inFlight == _generation) {
      return;
    }
    _delay?.cancel();
    _expiry?.cancel();
    final g = ++_generation;
    _inFlight = g;
    truncated = false;
    rankings = [];
    loading = true;
    error = null;
    _notify();
    try {
      final page = await load(jobId);
      if (!_valid(g)) return;
      if (page.jobId != jobId ||
          page.rankings.isNotEmpty &&
              (page.expiresAt == null ||
                  !page.expiresAt!.isAfter(DateTime.now()))) {
        throw const FormatException();
      }
      final byId = {for (final bid in _bids) bid.bidId: bid};
      rankings = page.rankings
          .where((r) => byId[r.bidId] != null && r.matches(byId[r.bidId]!))
          .toList();
      truncated = page.truncated;
      if (rankings.isNotEmpty) {
        _expiry = Timer(page.expiresAt!.difference(DateTime.now()), () {
          if (_valid(g)) {
            rankings = [];
            error = 'Ranking snapshot expired. Retry to check availability.';
            _notify();
          }
        });
      }
    } catch (e) {
      if (_valid(g)) {
        error = e is BidFlowException
            ? e.message
            : 'Recommendations could not be verified. Offers shown in bid ID order.';
      }
    } finally {
      if (_inFlight == g) _inFlight = null;
      if (_valid(g)) {
        loading = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _delay?.cancel();
    _expiry?.cancel();
    auth.removeListener(_session);
    super.dispose();
  }
}
