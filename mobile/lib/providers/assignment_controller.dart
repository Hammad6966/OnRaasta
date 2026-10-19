import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/bid_model.dart';
import '../models/booking_arguments.dart';
import '../services/api_service.dart';
import '../services/assignment_service.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';

class AssignmentInboxController extends ChangeNotifier {
  final PresenceSocket socket;
  final Future<List<AcceptedBooking>> Function() loadActive;
  final Future<AcceptedBooking> Function(String) loadOne;
  final void Function(String)? onUnavailable;
  final Map<String, AcceptedBooking> _bookings = {};
  final Set<String> _fetching = {};
  final Map<String, Map<String, dynamic>> _pendingHints = {};
  final Map<String, int> _changes = {};
  int _generation = 0, _revision = 0, _session = 0;
  bool _disposed = false, loading = false;
  String? error;
  bool get connected => socket.isConnected;
  List<AcceptedBooking> get bookings {
    final result = _bookings.values
        .where((booking) => booking.isActive)
        .toList()
      ..sort((a, b) => a.jobId.compareTo(b.jobId));
    return List.unmodifiable(result);
  }

  List<AcceptedBooking> get recentClosed {
    final result = _bookings.values
        .where((booking) => !booking.isActive)
        .toList()
      ..sort((a, b) => (textValue(b.job['updatedAt']) ?? '')
          .compareTo(textValue(a.job['updatedAt']) ?? ''));
    return List.unmodifiable(result.take(10));
  }

  AssignmentInboxController(
      {required this.socket,
      required this.loadActive,
      required this.loadOne,
      this.onUnavailable}) {
    socket.on('connect', _connect);
    socket.on('bid:accepted', _assigned);
    socket.on('job:assigned', _assigned);
    socket.on('job:unavailable', _unavailable);
    socket.on('session:ended', _ended);
    socket.on('auth:error', _ended);
    socket.on('mechanic:availability', _eligibility);
    socket.on('job:status_changed', _status);
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _connect(dynamic _) {
    refresh();
  }

  void _status(dynamic value) {
    final data = objectMap(value), id = objectId(objectMap(value)['jobId']);
    if (id == null ||
        ![
          'accepted',
          'en_route',
          'arrived',
          'in_progress',
          'completed',
          'cancelled'
        ].contains(data['status'])) {
      return;
    }
    final known = _bookings[id];
    if (known == null) {
      refresh();
      return;
    }
    _reloadHint(id,
        {'acceptedBidId': known.bid.bidId, 'mechanicId': known.bid.mechanicId});
  }

  void _eligibility(dynamic _) {
    refresh();
  }

  void _ended(dynamic _) {
    ++_generation;
    ++_session;
    _bookings.clear();
    _changes.clear();
    _fetching.clear();
    _pendingHints.clear();
    loading = false;
    error = 'Session ended. Please sign in again.';
    _notify();
  }

  void _unavailable(dynamic data) {
    final id = objectId(objectMap(data)['jobId']);
    if (id != null) onUnavailable?.call(id);
  }

  void _assigned(dynamic data) {
    final hint = objectMap(data);
    final id = objectId(hint['jobId']);
    if (id == null ||
        objectId(hint['acceptedBidId']) == null ||
        objectId(hint['mechanicId']) == null) {
      return;
    }
    onUnavailable?.call(id);
    _reloadHint(id, hint);
  }

  Future<void> _reloadHint(String id, Map<String, dynamic> hint) async {
    if (_disposed) return;
    if (!_fetching.add(id)) {
      _pendingHints[id] = hint;
      return;
    }
    final session = _session;
    final revision = ++_revision;
    _changes[id] = revision;
    try {
      final booking = await loadOne(id);
      if (_disposed || session != _session) return;
      if (booking.jobId != id ||
          booking.bid.bidId != hint['acceptedBidId'] ||
          booking.bid.mechanicId != hint['mechanicId']) {
        throw const AssignmentFailure(
            'Assignment notification did not match the saved record.');
      }
      final existing = _bookings[id];
      if (existing != null && !existing.isActive && booking.isActive) return;
      _bookings[id] = booking;
      _changes[id] = ++_revision;
      error = null;
      _notify();
    } catch (e) {
      if (!_disposed && session == _session) {
        error = e is AssignmentFailure
            ? e.message
            : 'Unable to retrieve assigned job. Please refresh.';
        _notify();
      }
    } finally {
      if (session == _session) {
        _fetching.remove(id);
        final pending = _pendingHints.remove(id);
        if (pending != null && !_disposed) {
          _reloadHint(id, pending);
        }
      }
    }
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation, revision = _revision;
    loading = true;
    error = null;
    _notify();
    try {
      final result = await loadActive();
      if (_disposed || generation != _generation) return;
      final snapshot = {for (final booking in result) booking.jobId: booking};
      for (final booking in snapshot.values) {
        onUnavailable?.call(booking.jobId);
      }
      for (final entry in _bookings.entries) {
        if ((_changes[entry.key] ?? 0) > revision ||
            (!entry.value.isActive && snapshot[entry.key]?.isActive == true)) {
          snapshot[entry.key] = entry.value;
        }
      }
      // A newer single-job read may have confirmed terminal state.
      for (final entry in _changes.entries) {
        if (entry.value > revision && !_bookings.containsKey(entry.key)) {
          snapshot.remove(entry.key);
        }
      }
      _bookings
        ..clear()
        ..addAll(snapshot);
    } catch (e) {
      if (_disposed || generation != _generation) return;
      if (e is AssignmentFailure && [401, 403].contains(e.status)) {
        _bookings.clear();
      }
      error = e is AssignmentFailure
          ? e.message
          : 'Unable to load assignments. Please retry.';
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
    socket.off('connect', _connect);
    socket.off('bid:accepted', _assigned);
    socket.off('job:assigned', _assigned);
    socket.off('job:unavailable', _unavailable);
    socket.off('session:ended', _ended);
    socket.off('auth:error', _ended);
    socket.off('mechanic:availability', _eligibility);
    socket.off('job:status_changed', _status);
    super.dispose();
  }
}

/// A validated snapshot keeps identity/costs available during network failure.
/// Mutations require a successful authoritative read in this screen session.
class AssignmentDetailController extends ChangeNotifier {
  final PresenceSocket socket;
  final Future<AcceptedBooking> Function(String) load;
  final Future<String?> Function() token;
  final String jobId;
  AcceptedBooking booking;
  bool loading = false,
      updating = false,
      verified = false,
      accessDenied = false;
  String? error, roomError;
  int _generation = 0, _session = 0;
  bool _disposed = false, _statusReading = false, _statusQueued = false;
  AssignmentDetailController(
      {required this.booking,
      required this.socket,
      required this.load,
      Future<String?> Function()? token})
      : jobId = booking.jobId,
        token = token ?? AuthService.instance.getAccessToken {
    socket.on('connect', _connected);
    socket.on('disconnect', _disconnected);
    socket.on('job:status_changed', _statusChanged);
    socket.on('session:ended', _ended);
    socket.on('auth:error', _ended);
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _connected(dynamic _) {
    reload();
  }

  int? _version(Map<String, dynamic> job) {
    final v = job['statusVersion'];
    return v is int && v >= 0 ? v : null;
  }

  void _statusChanged(dynamic value) {
    final data = objectMap(value);
    if (objectId(data['jobId']) != jobId ||
        ![
          'accepted',
          'en_route',
          'arrived',
          'in_progress',
          'completed',
          'cancelled'
        ].contains(data['status'])) {
      return;
    }
    final v = data['version'], saved = _version(booking.job);
    if (v is int && saved != null && v <= saved) return;
    _statusQueued = true;
    _reconcileStatus();
  }

  Future<void> _reconcileStatus() async {
    if (_statusReading || _disposed) return;
    _statusReading = true;
    try {
      while (_statusQueued && !_disposed && !accessDenied) {
        _statusQueued = false;
        await reload();
      }
    } finally {
      _statusReading = false;
    }
  }

  void _disconnected(dynamic _) {
    roomError =
        'Realtime disconnected. Reconnect or retry to reload the saved booking.';
    _notify();
  }

  void _ended(dynamic _) {
    ++_generation;
    ++_session;
    _statusQueued = false;
    verified = false;
    accessDenied = true;
    loading = false;
    error = 'Session ended. Please sign in again.';
    _notify();
  }

  Future<void> reload() async {
    if (_disposed) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    roomError = null;
    _notify();
    try {
      final result = await load(jobId);
      if (_disposed || generation != _generation) return;
      if (result.jobId != jobId ||
          result.bid.bidId != booking.bid.bidId ||
          result.bid.mechanicId != booking.bid.mechanicId) {
        throw const AssignmentFailure(
            'Assignment identity changed. Reopen the saved job.', 409);
      }
      final oldVersion = _version(booking.job),
          newVersion = _version(result.job);
      if (oldVersion != null && newVersion != null && newVersion < oldVersion) {
        return;
      }
      booking = result;
      verified = true;
      accessDenied = false;
      // Server authorizes the room again; a reconnect never trusts the snapshot.
      final access = await token();
      if (_disposed || generation != _generation) return;
      if (access != null && access.isNotEmpty && socket.isConnected) {
        try {
          await socket.request('join_room', {'room': 'job_$jobId'});
        } on SocketFailure catch (e) {
          if (!_disposed && generation == _generation) {
            roomError = e.message;
          }
        }
      } else {
        roomError =
            'Realtime disconnected. The booking is loaded from the server.';
      }
    } catch (e) {
      if (_disposed || generation != _generation) return;
      verified = false;
      if (e is AssignmentFailure && [401, 403].contains(e.status)) {
        accessDenied = true;
      }
      error = e is AssignmentFailure
          ? e.message
          : 'Unable to reload assigned job. Please retry.';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> updateStatus(String target) async {
    if (_disposed || updating || !verified || accessDenied || loading) return;
    final session = _session;
    updating = true;
    error = null;
    _notify();
    try {
      final response =
          await ApiService.instance.dio.patch('/jobs/$jobId/status', data: {
        'status': target,
        'expectedStatus': booking.job['status'],
        if (_version(booking.job) != null)
          'expectedVersion': _version(booking.job)
      });
      if (_disposed || accessDenied || session != _session) return;
      final envelope = objectMap(response.data),
          job = objectMap(objectMap(response.data)['job']);
      if (envelope['success'] != true ||
          objectId(job['_id']) != jobId ||
          job['status'] != target) {
        throw const FormatException();
      }
      final result =
          AcceptedBooking(job: job, bid: booking.bid, driver: booking.driver);
      final oldVersion = _version(booking.job),
          newVersion = _version(result.job);
      if (oldVersion == null ||
          newVersion == null ||
          newVersion >= oldVersion) {
        booking = result;
      }
      await reload();
    } catch (e) {
      if (!_disposed && session == _session) {
        verified = false;
        final status = e is DioException ? e.response?.statusCode : null;
        if ([401, 403].contains(status)) {
          accessDenied = true;
        } else {
          await reload();
        }
        if (_disposed || session != _session) return;
        error = switch (status) {
          401 =>
            'Job update was not confirmed. Session expired; sign in again.',
          403 =>
            'Job update was not confirmed. Assigned, approved mechanic access is required.',
          404 =>
            'Job update was not confirmed. The saved job is unavailable; reopen your assignments.',
          409 => verified
              ? 'Job update was not confirmed. The saved state changed; the latest state is shown. Retry the next action.'
              : 'Job update was not confirmed. The saved state changed; reload the job before retrying.',
          _ =>
            'Job update was not confirmed. Check your connection and retry after reloading the saved job.',
        };
      }
    } finally {
      if (!_disposed) {
        updating = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    socket.off('connect', _connected);
    socket.off('disconnect', _disconnected);
    socket.off('job:status_changed', _statusChanged);
    socket.off('session:ended', _ended);
    socket.off('auth:error', _ended);
    super.dispose();
  }
}
