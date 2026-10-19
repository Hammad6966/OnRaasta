import 'package:flutter/foundation.dart';
import '../models/history_models.dart';
import '../services/history_service.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/socket_service.dart';

class HistoryController extends ChangeNotifier {
  HistoryController(
      {HistoryService? service,
      AuthService? auth,
      PresenceSocket? socket,
      this.mechanic = false,
      this.earnings = false})
      : service = service ?? HistoryService.instance,
        auth = auth ?? AuthService.instance,
        socket = socket ?? SocketService() {
    _epoch = this.auth.epoch;
    this.auth.addListener(_session);
    this.socket.on('session:ended', _ended);
    this.socket.on('auth:error', _ended);
    this.socket.on('connect', _reconcile);
    this.socket.on('job:status_changed', _reconcile);
  }
  final HistoryService service;
  final AuthService auth;
  final PresenceSocket socket;
  final bool mechanic, earnings;
  List<HistoryJob> jobs = [];
  Map<String, dynamic>? summary;
  int page = 0, undated = 0, _epoch = 0, _generation = 0;
  bool loading = false, hasMore = false, _disposed = false;
  String? error, status, from, to;
  bool _reconcilePending = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(int g) =>
      !_disposed &&
      _epoch == auth.epoch &&
      !auth.isClearing &&
      g == _generation;
  void _ended(dynamic _) {
    _generation++;
    jobs = [];
    summary = null;
    hasMore = false;
    loading = false;
    undated = 0;
    _reconcilePending = false;
    error = 'Session ended. Please sign in again.';
    _notify();
  }

  void _session() {
    if (_epoch == auth.epoch && !auth.isClearing) return;
    _epoch = auth.epoch;
    _generation++;
    jobs = [];
    summary = null;
    hasMore = false;
    loading = false;
    undated = 0;
    _reconcilePending = false;
    error = 'Session changed. Please sign in again.';
    _notify();
  }

  void _reconcile(dynamic _) {
    if (auth.isClearing || auth.status == SessionStatus.signedOut) return;
    if (loading) {
      _reconcilePending = true;
      return;
    }
    load();
  }

  Future<void> filter({String? status, String? from, String? to}) async {
    this.status = status;
    this.from = from;
    this.to = to;
    jobs = [];
    summary = null;
    await load();
  }

  Future<void> load({bool more = false}) async {
    if (_disposed || auth.isClearing || more && (loading || !hasMore)) return;
    final g = ++_generation, next = more ? page + 1 : 1;
    loading = true;
    error = null;
    _notify();
    try {
      final result = await service.fetch(
          mechanic: mechanic,
          earnings: earnings,
          page: next,
          status: status,
          from: from,
          to: to);
      if (!_valid(g)) return;
      if (result.page != next) {
        throw const FormatException('Incorrect history page');
      }
      final merged = <String, HistoryJob>{
        if (more)
          for (final j in jobs) j.id: j,
        for (final j in result.jobs) j.id: j
      };
      jobs = merged.values.toList();
      page = result.page;
      hasMore = result.hasMore;
      summary = result.summary;
      undated = result.undated;
    } catch (e) {
      if (_valid(g)) error = profileError(e);
    } finally {
      if (_valid(g)) {
        loading = false;
        _notify();
        if (_reconcilePending) {
          _reconcilePending = false;
          load();
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    auth.removeListener(_session);
    socket.off('session:ended', _ended);
    socket.off('auth:error', _ended);
    socket.off('connect', _reconcile);
    socket.off('job:status_changed', _reconcile);
    super.dispose();
  }
}
