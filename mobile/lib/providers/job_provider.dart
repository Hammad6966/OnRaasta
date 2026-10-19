import 'package:flutter/foundation.dart';
import '../models/bid_model.dart';
import '../services/bidding_service.dart';

/// Screen-owned state with HTTP generations and per-bid socket revisions.
class JobBidsController extends ChangeNotifier {
  final String jobId;
  final Future<List<BidModel>> Function(String) load;
  final Map<String, BidModel> _bids = {};
  final Map<String, int> _socketRevision = {};
  int _revision = 0, _generation = 0;
  bool _disposed = false;
  bool loading = false;
  String? error;
  JobBidsController({required this.jobId, required this.load});
  List<BidModel> get bids => List.unmodifiable(_bids.values);
  void receive(Object? payload) {
    if (_disposed) return;
    try {
      final bid = BidModel.fromJson(payload);
      if (bid.jobId != jobId) return;
      _bids[bid.bidId] = _bids[bid.bidId]?.merge(bid) ?? bid;
      _socketRevision[bid.bidId] = ++_revision;
      notifyListeners();
    } on FormatException {/* Ignore malformed or foreign notifications. */}
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    final revision = _revision;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await load(jobId);
      if (_disposed || generation != _generation) return;
      final snapshot = <String, BidModel>{};
      for (final bid in result.where((b) => b.jobId == jobId)) {
        final old = _bids[bid.bidId];
        snapshot[bid.bidId] = old == null
            ? bid
            : (_socketRevision[bid.bidId] ?? 0) > revision
                ? bid.merge(old)
                : old.merge(bid);
      }
      for (final entry in _bids.entries) {
        // A socket record may precede even the first GET. An older database
        // snapshot must not erase it merely because it was absent from that GET.
        if (_socketRevision.containsKey(entry.key)) {
          snapshot.putIfAbsent(entry.key, () => entry.value);
        }
      }
      _bids
        ..clear()
        ..addAll(snapshot);
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = e is BidFlowException
          ? e.message
          : 'Unable to load bids. Please retry.';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
