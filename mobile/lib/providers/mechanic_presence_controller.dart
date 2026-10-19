import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/bid_model.dart';
import '../models/job_request.dart';
import '../services/foreground_location.dart';
import '../services/socket_service.dart';

/// Owned by Mechanic Home, active only while the application is foregrounded.
/// Intent survives transport loss/backgrounding, never logout or replacement.
class MechanicPresenceController extends ChangeNotifier {
  final PresenceSocket socket;
  final ForegroundLocation gps;
  final Future<String?> Function() token;
  final Future<Map<String, dynamic>> Function() profile;
  final Future<List<dynamic>> Function() loadRequests;
  final Duration heartbeatInterval;
  bool online = false,
      busy = false,
      loadingProfile = true,
      approved = false,
      wantsOnline = false;
  bool foreground = true, feedLoading = false;
  String? error, feedError;
  String name = '', mechanicId = '';
  int? completedJobs;
  String? bookedNetMinor;
  int unpricedJobs = 0;
  GpsPoint? location;
  bool _disposed = false, _suspending = false, _sending = false;
  int _generation = 0, _feedGeneration = 0, _revision = 0;
  final Map<String, JobRequest> _jobs = {};
  final Set<String> _unavailableJobs = {};
  final Map<String, int> _arrivals = {};
  StreamSubscription<GpsPoint>? _positions;
  StreamSubscription<bool>? _services;
  Timer? _heartbeat;
  List<JobRequest> get jobs => List.unmodifiable(_jobs.values);
  MechanicPresenceController(
      {required this.socket,
      required this.gps,
      required this.token,
      required this.profile,
      required this.loadRequests,
      this.heartbeatInterval = const Duration(seconds: 30)}) {
    socket.on('connect', _connected);
    socket.on('disconnect', _disconnected);
    socket.on('session:ended', _ended);
    socket.on('auth:error', _authError);
    socket.on('security:error', _securityError);
    socket.on('mechanic:availability', _revoked);
    socket.on('mechanic:approval_changed', _approvalChanged);
    socket.on('connection:failed', _connectionFailed);
    socket.on('job:new_request', _request);
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(int generation) =>
      !_disposed && foreground && wantsOnline && generation == _generation;
  Future<void> _profile() async {
    final data = await profile();
    if (_disposed) return;
    mechanicId = objectId(data['_id']) ?? '';
    if (mechanicId.isEmpty) {
      throw const LocationFailure(
          'Mechanic profile is unavailable. Please retry.');
    }
    approved = data['isApproved'] == true;
    name = textValue(objectMap(data['userId'])['name']) ?? '';
    final statistics = objectMap(data['statistics']);
    completedJobs = statistics['completedJobs'] is int
        ? statistics['completedJobs'] as int
        : null;
    bookedNetMinor = statistics['netMinor'] as String?;
    unpricedJobs = statistics['unpricedJobs'] as int? ?? 0;
  }

  Future<void> initialize() async {
    final generation = _generation;
    loadingProfile = true;
    error = null;
    _notify();
    try {
      await _profile();
      if (_disposed || generation != _generation) return;
      final access = await token();
      if (_disposed || generation != _generation) return;
      if (access == null || access.isEmpty) {
        throw const SocketFailure('Please sign in again.', 401);
      }
      socket.connect(access);
      if (!approved) {
        error =
            'Your mechanic account is awaiting approval. You can go online after approval.';
      }
    } catch (e) {
      if (!_disposed) error = _message(e);
    } finally {
      if (!_disposed) {
        loadingProfile = false;
        _notify();
      }
    }
  }

  Future<void> toggle() async {
    if (_disposed || busy || loadingProfile) return;
    if (online) {
      await goOffline();
    } else {
      wantsOnline = true;
      await _goOnline();
    }
  }

  Future<void> _goOnline() async {
    if (_disposed || !foreground || busy || !wantsOnline) return;
    final generation = ++_generation;
    busy = true;
    error = null;
    _notify();
    try {
      await _profile();
      if (!_valid(generation)) return;
      if (!approved) {
        throw const SocketFailure(
            'Your mechanic account is awaiting approval.', 403);
      }
      final access = await token();
      if (!_valid(generation)) return;
      if (access == null || access.isEmpty) {
        throw const SocketFailure('Please sign in again.', 401);
      }
      final point = await gps.current();
      if (!_valid(generation)) return;
      if (!point.fresh) {
        throw const LocationFailure(
            'GPS position is invalid or stale. Please retry.');
      }
      await socket.ensureConnected(access);
      if (!_valid(generation)) return;
      final confirmation =
          await socket.request('mechanic:go_online', point.toJson());
      if (!_valid(generation)) return;
      if (confirmation['isOnline'] != true ||
          objectId(confirmation['mechanicId']) != mechanicId ||
          finiteNumber(confirmation['lat']) != point.lat ||
          finiteNumber(confirmation['lng']) != point.lng ||
          finiteNumber(confirmation['serviceRadius']) == null ||
          finiteNumber(confirmation['serviceRadius'])! < 1 ||
          finiteNumber(confirmation['serviceRadius'])! > 100) {
        throw const SocketFailure(
            'Invalid availability acknowledgment. Please retry.');
      }
      online = true;
      location = point;
      _startLocation();
      refreshRequests();
    } catch (e) {
      if (_valid(generation)) {
        error = _message(e);
        _stopIntent();
        _closeTransport();
      }
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> goOffline() async {
    if (_disposed || busy) return;
    final generation = ++_generation;
    wantsOnline = false;
    busy = true;
    error = null;
    _stopLocation();
    _notify();
    try {
      final confirmation = await socket.request('mechanic:go_offline', {});
      if (_disposed || generation != _generation) return;
      if (confirmation['isOnline'] != false ||
          objectId(confirmation['mechanicId']) != mechanicId) {
        throw const SocketFailure('Invalid offline acknowledgment.');
      }
      online = false;
      _clearFeed();
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = '${_message(e)} Connection closed to stop availability.';
      online = false;
      _clearFeed();
      _closeTransport();
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  void _startLocation() {
    _stopLocation();
    _positions = gps.positions().listen((point) {
      _sendLocation(point);
    },
        onError: (Object _) => _locationFailed(
            'Location access was lost. Check GPS and permission.'));
    _services = gps.serviceChanges().listen((enabled) {
      if (!enabled) {
        _locationFailed(
            'Location services disabled. Enable GPS before going online.');
      }
    },
        onError: (Object _) =>
            _locationFailed('Unable to monitor location services.'));
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => checkLocation());
  }

  Future<void> checkLocation() async {
    if (!online || !foreground || _disposed || _sending) return;
    try {
      await _sendLocation(await gps.current());
      if (!_disposed && online && foreground) refreshRequests();
    } catch (e) {
      if (!_disposed && online) _locationFailed(_message(e));
    }
  }

  Future<void> _sendLocation(GpsPoint point) async {
    if (!online || !foreground || _disposed || _sending) return;
    if (!point.fresh) {
      _locationFailed('GPS position became invalid or stale. Please retry.');
      return;
    }
    final generation = _generation;
    _sending = true;
    try {
      final result =
          await socket.request('mechanic:update_location', point.toJson());
      if (!_valid(generation)) return;
      if (result['isOnline'] != true ||
          objectId(result['mechanicId']) != mechanicId) {
        throw const SocketFailure('Location update was not confirmed.');
      }
      location = point;
      _notify();
    } catch (e) {
      if (_valid(generation)) _locationFailed(_message(e));
    } finally {
      _sending = false;
    }
  }

  void _stopLocation() {
    _positions?.cancel();
    _services?.cancel();
    _heartbeat?.cancel();
    _positions = null;
    _services = null;
    _heartbeat = null;
  }

  void _clearFeed() {
    ++_feedGeneration;
    feedLoading = false;
    _jobs.clear();
    _arrivals.clear();
  }

  void _stopIntent() {
    ++_generation;
    wantsOnline = false;
    online = false;
    busy = false;
    _stopLocation();
    _clearFeed();
    _notify();
  }

  void _closeTransport() {
    _suspending = true;
    socket.disconnect();
    _suspending = false;
  }

  void _locationFailed(String message) {
    if (_disposed || !online) return;
    error = message;
    _stopIntent();
    _closeTransport();
  }

  void _connected(dynamic _) {
    if (wantsOnline && foreground && !busy && !online) _goOnline();
  }

  void _disconnected(dynamic _) {
    if (_disposed) return;
    ++_generation;
    online = false;
    busy = false;
    _stopLocation();
    _clearFeed();
    if (wantsOnline && foreground) {
      error =
          'Connection lost. Availability will resume after reconnection with fresh GPS.';
    }
    _notify();
  }

  void _ended(dynamic _) {
    completedJobs = null;
    bookedNetMinor = null;
    unpricedJobs = 0;
    if (!_suspending && !_disposed) {
      error = 'Session ended. Please sign in again.';
      _stopIntent();
    }
  }

  void _authError(dynamic _) {
    if (!_disposed) {
      error = 'Session rejected or expired. Please sign in again.';
      _stopIntent();
    }
  }

  void _securityError(dynamic data) {
    final event = textValue(objectMap(data)['event']);
    if (event != null && !event.startsWith('mechanic:')) return;
    if (!_disposed) {
      error =
          textValue(objectMap(data)['message']) ?? 'Availability was rejected.';
      _stopIntent();
      _closeTransport();
    }
  }

  void _approvalChanged(dynamic data) {
    final value = objectMap(data);
    if (_disposed || objectId(value['mechanicId']) != mechanicId) return;
    approved = value['isApproved'] == true;
    if (!approved) _stopIntent();
    initialize(); // Reload account approval; never infer document verification.
  }

  void _revoked(dynamic data) {
    if (objectMap(data)['isOnline'] == false && !_disposed) {
      error = textValue(objectMap(data)['reason']) ?? 'Availability ended.';
      _stopIntent();
    }
  }

  void _connectionFailed(dynamic _) {
    if (!_disposed) {
      error = 'Unable to reconnect. Check network and tap online to retry.';
      _stopIntent();
    }
  }

  void setForeground(bool value) {
    if (_disposed || foreground == value) return;
    foreground = value;
    if (!value) {
      ++_generation;
      online = false;
      busy = false;
      _stopLocation();
      _clearFeed();
      _closeTransport();
      _notify();
    } else if (wantsOnline) {
      _goOnline();
    }
  }

  void _request(dynamic data) {
    if (!online || !wantsOnline || !foreground || _disposed) return;
    try {
      final job = JobRequest.fromJson(objectMap(data));
      if (_unavailableJobs.contains(job.jobId)) return;
      _jobs[job.jobId] = job;
      _arrivals[job.jobId] = ++_revision;
      _notify();
    } on FormatException {
      /* Ignore malformed opportunities, never invent IDs. */
    }
  }

  void invalidateOpportunity(String jobId) {
    _unavailableJobs.add(jobId);
    _jobs.remove(jobId);
    _arrivals.remove(jobId);
    _notify();
  }

  void decline(String jobId) {
    _jobs.remove(jobId);
    _arrivals.remove(jobId);
    _notify();
  }

  Future<void> refreshRequests() async {
    if (!online || _disposed) return;
    final generation = ++_feedGeneration, revision = _revision;
    feedLoading = true;
    feedError = null;
    _notify();
    try {
      final result = await loadRequests();
      if (_disposed || !online || generation != _feedGeneration) return;
      final snapshot = <String, JobRequest>{};
      for (final raw in result) {
        final job = JobRequest.fromJson(objectMap(raw));
        if (!_unavailableJobs.contains(job.jobId)) snapshot[job.jobId] = job;
      }
      for (final entry in _jobs.entries) {
        if ((_arrivals[entry.key] ?? 0) > revision) {
          snapshot[entry.key] = entry.value;
        }
      }
      _jobs
        ..clear()
        ..addAll(snapshot);
    } catch (_) {
      if (!_disposed && generation == _feedGeneration) {
        feedError =
            'Unable to refresh requests. New live requests will still appear.';
      }
    } finally {
      if (!_disposed && generation == _feedGeneration) {
        feedLoading = false;
        _notify();
      }
    }
  }

  String _message(Object error) => error is SocketFailure
      ? error.message
      : error is LocationFailure
          ? error.message
          : 'Unable to load availability. Check your session and network, then retry.';
  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    wantsOnline = false;
    _stopLocation();
    socket.off('connect', _connected);
    socket.off('disconnect', _disconnected);
    socket.off('session:ended', _ended);
    socket.off('auth:error', _authError);
    socket.off('security:error', _securityError);
    socket.off('mechanic:availability', _revoked);
    socket.off('mechanic:approval_changed', _approvalChanged);
    socket.off('connection:failed', _connectionFailed);
    socket.off('job:new_request', _request);
    socket.disconnect();
    super.dispose();
  }
}
