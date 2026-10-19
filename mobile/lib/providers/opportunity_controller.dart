import 'package:flutter/foundation.dart';
import '../models/bid_model.dart';
import '../services/assignment_service.dart';
import '../services/socket_service.dart';

/// A closed opportunity cannot be reopened by a stale HTTP response.
class OpportunityController extends ChangeNotifier {
  final String jobId;
  final PresenceSocket socket;
  final Future<bool> Function(String) load;
  bool loading = false, isOpen = false, _closed = false, _disposed = false;
  int _generation = 0;
  String? error;
  bool get canBid => isOpen && !loading && !_closed && error == null;
  OpportunityController(
      {required this.jobId, required this.socket, required this.load}) {
    socket.on('job:unavailable', _unavailable);
    socket.on('connect', _connected);
    socket.on('session:ended', _ended);
    socket.on('auth:error', _ended);
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _connected(dynamic _) {
    refresh();
  }

  void _ended(dynamic _) {
    ++_generation;
    isOpen = false;
    loading = false;
    error = 'Session ended. Please sign in again.';
    _notify();
  }

  void _unavailable(dynamic data) {
    if (objectId(objectMap(data)['jobId']) == jobId) close();
  }

  void close() {
    ++_generation;
    _closed = true;
    isOpen = false;
    loading = false;
    error = 'This job is no longer accepting bids.';
    _notify();
  }

  Future<void> refresh() async {
    if (_disposed || _closed) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      final result = await load(jobId);
      if (_disposed || generation != _generation) return;
      if (!result) {
        close();
        return;
      }
      isOpen = true;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      isOpen = false;
      error = e is AssignmentFailure
          ? e.message
          : 'Could not check job availability. Please retry.';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    socket.off('job:unavailable', _unavailable);
    socket.off('connect', _connected);
    socket.off('session:ended', _ended);
    socket.off('auth:error', _ended);
    super.dispose();
  }
}
