import 'package:flutter/foundation.dart';
import '../services/profile_service.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';

class ProfileController extends ChangeNotifier {
  ProfileController(
      {ProfileService? service, this.mechanic = false, AuthService? auth})
      : service = service ?? ProfileService.instance,
        auth = auth ?? AuthService.instance {
    _epoch = this.auth.epoch;
    this.auth.addListener(_sessionChanged);
    SocketService().on('job:status_changed', _statusChanged);
    SocketService().on('connect', _statusChanged);
  }
  final ProfileService service;
  final AuthService auth;
  final bool mechanic;
  Map<String, dynamic>? user, mechanicProfile;
  List<Map<String, dynamic>> vehicles = [];
  bool loading = false, saving = false, _disposed = false;
  String? error;
  int _epoch = 0, _generation = 0;
  bool _current(int g) =>
      !_disposed &&
      _epoch == auth.epoch &&
      !auth.isClearing &&
      g == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _statusChanged(dynamic _) {
    if (user != null && !saving && !loading) load();
  }

  void _sessionChanged() {
    if (_epoch == auth.epoch && !auth.isClearing) return;
    _epoch = auth.epoch;
    _generation++;
    user = null;
    mechanicProfile = null;
    vehicles = [];
    loading = false;
    saving = false;
    error = 'Session changed. Please reopen your profile.';
    _notify();
  }

  Future<void> load() async {
    if (loading || saving) return;
    final g = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      final account = await service.profile();
      final list =
          mechanic ? <Map<String, dynamic>>[] : await service.vehicles();
      final details = mechanic ? await service.mechanic() : null;
      if (!_current(g)) return;
      user = account;
      vehicles = list;
      mechanicProfile = details;
    } catch (e) {
      if (_current(g)) error = profileError(e);
    } finally {
      if (_current(g)) {
        loading = false;
        _notify();
      }
    }
  }

  Future<bool> save(
      String method, String path, Map<String, dynamic>? body) async {
    if (saving || loading || user == null) return false;
    final g = _generation;
    saving = true;
    error = null;
    _notify();
    try {
      await service.request(method, path, body);
      if (!_current(g)) return false;
      if (path == '/mechanics/profile') {
        ProfileService.mechanicChanges.notifyListeners();
      }
      return true;
    } catch (e) {
      if (_current(g)) error = profileError(e);
      return false;
    } finally {
      if (_current(g)) {
        saving = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    auth.removeListener(_sessionChanged);
    SocketService().off('job:status_changed', _statusChanged);
    SocketService().off('connect', _statusChanged);
    super.dispose();
  }
}
