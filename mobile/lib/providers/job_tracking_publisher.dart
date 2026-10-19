import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/bid_model.dart';
import '../models/booking_arguments.dart';
import '../models/job_location.dart';
import '../services/foreground_location.dart';
import '../services/socket_service.dart';

/// Owned by the mounted mechanic home beneath pushed routes, never a job page.
class JobTrackingPublisher extends ChangeNotifier {
  static JobTrackingPublisher? current;
  final PresenceSocket socket;
  final ForegroundLocation gps;
  final Future<List<AcceptedBooking>> Function() assignments;
  final Future<Map<String, dynamic>> Function() profile;
  final Future<String?> Function() token;
  final Duration interval;
  final double minimumMovement;
  final Map<String, AcceptedBooking> _jobs = {};
  final Map<String, JobLocation> _confirmed = {};
  StreamSubscription<GpsPoint>? _positions;
  StreamSubscription<bool>? _services;
  int _generation = 0;
  bool _disposed = false, _sending = false, foreground = true, loading = false;
  String? error;
  JobTrackingPublisher(
      {required this.socket,
      required this.gps,
      required this.assignments,
      required this.profile,
      required this.token,
      this.interval = const Duration(seconds: 10),
      this.minimumMovement = 10}) {
    socket.on('connect', _connect);
    socket.on('disconnect', _lost);
    socket.on('session:ended', _ended);
    socket.on('auth:error', _ended);
    socket.on('job:assigned', _changed);
    socket.on('job:status_changed', _changed);
    socket.on('mechanic:availability', _revoked);
  }
  bool sharing(String id) =>
      foreground &&
      socket.isConnected &&
      _jobs.containsKey(id) &&
      _confirmed.containsKey(id) &&
      error == null;
  String message(String id) => !foreground
      ? 'Location sharing paused outside foreground.'
      : error ??
          (sharing(id)
              ? 'Location sharing confirmed by server.'
              : _jobs.containsKey(id)
                  ? 'Waiting for GPS sharing confirmation.'
                  : 'Location sharing is available while en route.');
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _connect(dynamic _) {
    reconcile();
  }

  void _changed(dynamic data) {
    if (objectId(objectMap(data)['jobId']) != null) reconcile();
  }

  void _revoked(dynamic data) {
    if (objectMap(data)['isOnline'] == false) {
      _stop('Availability changed. Recheck approval before sharing.');
    }
  }

  void _lost(dynamic _) {
    _stop(
        'Connection lost. Location sharing will recheck assignment on reconnect.');
  }

  void _ended(dynamic _) {
    _stop(
        'Location sharing stopped. Recheck GPS, connection and sign-in, then retry.');
  }

  void _stop(String? reason) {
    ++_generation;
    _sending = false;
    _jobs.clear();
    _confirmed.clear();
    _positions?.cancel();
    _services?.cancel();
    _positions = null;
    _services = null;
    loading = false;
    error = reason;
    _notify();
  }

  Future<void> reconcile() async {
    if (_disposed || !foreground) return;
    _stop(null);
    final generation = _generation;
    loading = true;
    _notify();
    try {
      final account = await profile();
      if (_disposed || generation != _generation) return;
      if (account['isApproved'] != true) {
        throw const SocketFailure(
            'Approval is required for job location sharing.', 403);
      }
      final jobs = await assignments();
      final access = await token();
      if (_disposed || generation != _generation || !foreground) return;
      if (access == null || access.isEmpty) {
        throw const SocketFailure('Sign in again to share location.', 401);
      }
      // Reuse the authenticated singleton, including account/token replacement.
      await socket.ensureConnected(access);
      if (_disposed || generation != _generation || !foreground) return;
      for (final job in jobs) {
        if (job.job['status'] == 'en_route' &&
            job.bid.mechanicId == objectId(account['_id'])) {
          _jobs[job.jobId] = job;
        }
      }
      if (_jobs.isEmpty) return;
      final point = await gps.current();
      if (_disposed || generation != _generation) return;
      _positions = gps.positions().listen((p) => publish(p),
          onError: (Object _) => _stop(
              'Location permission or GPS access was lost. Enable it and retry.'));
      _services = gps.serviceChanges().listen((enabled) {
        if (!enabled) {
          _stop('Location services disabled. Enable GPS and retry.');
        }
      },
          onError: (Object _) =>
              _stop('Location services could not be monitored. Retry.'));
      await publish(point);
    } catch (e) {
      if (!_disposed && generation == _generation) {
        _stop(e is LocationFailure
            ? e.message
            : e is SocketFailure
                ? e.message
                : 'Could not verify assigned jobs. Retry location sharing.');
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> publish(GpsPoint point) async {
    if (_disposed ||
        !foreground ||
        !socket.isConnected ||
        _jobs.isEmpty ||
        _sending) {
      return;
    }
    if (!point.fresh ||
        point.accuracy != null &&
            (!point.accuracy!.isFinite ||
                point.accuracy! < 0 ||
                point.accuracy! > 100)) {
      _stop(
          'GPS observation is unavailable, stale or inaccurate. Retry outdoors.');
      return;
    }
    final generation = _generation;
    _sending = true;
    try {
      for (final entry in _jobs.entries.toList()) {
        if (_disposed || generation != _generation || !foreground) return;
        final previous = _confirmed[entry.key];
        if (previous != null &&
            (point.observedAt.difference(previous.observedAt) < interval ||
                distanceMeters(
                        previous.lat, previous.lng, point.lat, point.lng) <
                    minimumMovement)) {
          continue;
        }
        final ack = await socket.request('job:mechanic_location', {
          'jobId': entry.key,
          'lat': point.lat,
          'lng': point.lng,
          if (point.accuracy != null) 'accuracy': point.accuracy,
          'observedAt': point.observedAt.toUtc().toIso8601String()
        });
        if (_disposed || generation != _generation) return;
        final saved = JobLocation.parse(ack['location']);
        if (saved.jobId != entry.key ||
            saved.mechanicId != entry.value.bid.mechanicId ||
            saved.lat != point.lat ||
            saved.lng != point.lng ||
            ack['accepted'] is! bool) {
          throw const SocketFailure('Invalid location sharing acknowledgment.');
        }
        _confirmed[entry.key] = saved;
        error = null;
        _notify();
      }
    } catch (e) {
      if (!_disposed && generation == _generation) {
        if (e is SocketFailure && e.status == 429) {
          error =
              'Location updates are temporarily throttled. The next GPS observation will retry.';
          _notify();
        } else {
          _stop(e is SocketFailure
              ? e.message
              : 'Location update was not confirmed. Retry.');
        }
      }
    } finally {
      if (generation == _generation) _sending = false;
    }
  }

  void observeAssignment(AcceptedBooking booking) {
    if (_disposed) return;
    if (booking.job['status'] == 'en_route') {
      if (!_jobs.containsKey(booking.jobId) && !loading && foreground) {
        reconcile();
      }
    } else if (_jobs.remove(booking.jobId) != null) {
      _confirmed.remove(booking.jobId);
      if (_jobs.isEmpty) {
        _stop(null);
      } else {
        _notify();
      }
    }
  }

  void setForeground(bool value) {
    if (_disposed || foreground == value) return;
    foreground = value;
    if (value) {
      reconcile();
    } else {
      _stop('Location sharing paused outside foreground.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stop(null);
    socket.off('connect', _connect);
    socket.off('disconnect', _lost);
    socket.off('session:ended', _ended);
    socket.off('auth:error', _ended);
    socket.off('job:assigned', _changed);
    socket.off('job:status_changed', _changed);
    socket.off('mechanic:availability', _revoked);
    if (identical(current, this)) current = null;
    super.dispose();
  }
}

double distanceMeters(double a, double b, double c, double d) {
  double rad(double v) => v * math.pi / 180;
  final h = math.pow(math.sin(rad(c - a) / 2), 2) +
          math.cos(rad(a)) *
              math.cos(rad(c)) *
              math.pow(math.sin(rad(d - b) / 2), 2),
      bounded = h.clamp(0, 1);
  return 6371000 * 2 * math.atan2(math.sqrt(bounded), math.sqrt(1 - bounded));
}
