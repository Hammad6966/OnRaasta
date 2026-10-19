import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/job_location.dart';
import '../services/job_location_service.dart';
import '../services/socket_service.dart';
import 'assignment_controller.dart';

class JobLocationController extends ChangeNotifier {
  final AssignmentDetailController assignment;
  final PresenceSocket socket;
  final Future<JobLocationSnapshot> Function(String) load;
  final DateTime Function() clock;
  JobLocation? _point;
  bool _disposed = false, foreground = true, loading = false, _denied = false;
  int _generation = 0, _revision = 0;
  String? error;
  Timer? _freshness;
  bool get eligible =>
      foreground &&
      !_denied &&
      assignment.verified &&
      !assignment.accessDenied &&
      assignment.booking.job['status'] == 'en_route';
  JobLocation? get location => eligible ? _point : null;
  String get label {
    if (!foreground) return 'Location paused outside foreground';
    if (_denied) return 'Location access unavailable. Refresh the saved job.';
    if (!eligible) return 'Location sharing is available while en route';
    if (error != null) return error!;
    if (_point == null) return 'Waiting for mechanic location';
    final observed = _point!.observedAt.toLocal();
    final time =
        '${observed.hour.toString().padLeft(2, '0')}:${observed.minute.toString().padLeft(2, '0')}:${observed.second.toString().padLeft(2, '0')}';
    if (!socket.isConnected) return 'Offline — last observation $time';
    if (!_point!.fresh(clock())) {
      return 'Location stale — last observation $time';
    }
    return 'Recent location — observed $time';
  }

  JobLocationController(
      {required this.assignment,
      required this.socket,
      required this.load,
      DateTime Function()? clock})
      : clock = clock ?? DateTime.now {
    assignment.addListener(_assignmentChanged);
    socket.on('job:mechanic_location', _receive);
    socket.on('disconnect', _lost);
    socket.on('session:ended', _ended);
    socket.on('auth:error', _ended);
    _startClock();
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _startClock() {
    _freshness?.cancel();
    _freshness = Timer.periodic(const Duration(seconds: 15), (_) => _notify());
  }

  void _assignmentChanged() {
    if (assignment.verified &&
        !assignment.loading &&
        !assignment.accessDenied) {
      _denied = false;
    }
    if (!eligible) {
      ++_generation;
      _point = null;
      loading = false;
      _notify();
      return;
    }
    if (!assignment.loading) recover();
  }

  void _lost(dynamic _) {
    ++_generation;
    loading = false;
    _notify();
  }

  void _ended(dynamic _) {
    ++_generation;
    _point = null;
    _denied = true;
    error = 'Session ended. Sign in again.';
    loading = false;
    _notify();
  }

  void _merge(JobLocation point) {
    if (!eligible ||
        point.jobId != assignment.jobId ||
        point.mechanicId != assignment.booking.bid.mechanicId ||
        point.observedAt.isAfter(clock().add(const Duration(seconds: 10)))) {
      return;
    }
    if (_point != null && !point.observedAt.isAfter(_point!.observedAt)) return;
    _point = point;
    ++_revision;
    error = null;
    _notify();
  }

  void _receive(dynamic value) {
    try {
      _merge(JobLocation.parse(value));
    } on FormatException {/* Ignore malformed relays. */}
  }

  Future<void> recover() async {
    if (_disposed || !eligible) return;
    final generation = ++_generation, revision = _revision;
    loading = true;
    error = null;
    _notify();
    try {
      final snapshot = await load(assignment.jobId);
      if (_disposed || generation != _generation || !eligible) return;
      if (snapshot.jobId != assignment.jobId) throw const FormatException();
      if (!snapshot.allowed) {
        _point = null;
        error = 'Location sharing is not currently available.';
      } else if (snapshot.location != null) {
        _merge(snapshot.location!);
      } else if (revision == _revision) {
        _point = null;
      }
    } catch (e) {
      if (_disposed || generation != _generation) return;
      if (e is DioException && [401, 403].contains(e.response?.statusCode)) {
        _point = null;
        _denied = true;
      }
      error = 'Location unavailable. Check connection and retry.';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  void setForeground(bool value) {
    if (_disposed || value == foreground) return;
    foreground = value;
    ++_generation;
    loading = false;
    if (value) {
      _startClock();
    } else {
      _freshness?.cancel();
    }
    _notify();
  }

  Future<void> retry() async {
    final generation = _generation;
    try {
      final access = await assignment.token();
      if (_disposed || generation != _generation || !foreground) return;
      if (access != null && access.isNotEmpty && !socket.isConnected) {
        await socket.ensureConnected(access);
      }
      if (!_disposed && foreground) await assignment.reload();
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = 'Location connection unavailable. Check sign-in and retry.';
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _freshness?.cancel();
    assignment.removeListener(_assignmentChanged);
    socket.off('job:mechanic_location', _receive);
    socket.off('disconnect', _lost);
    socket.off('session:ended', _ended);
    socket.off('auth:error', _ended);
    super.dispose();
  }
}
