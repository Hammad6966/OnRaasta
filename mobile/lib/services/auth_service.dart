import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants/api_constants.dart';
import '../models/bid_model.dart';
import 'socket_service.dart';

enum SessionStatus { unknown, authenticated, signedOut, offline }

class SessionFailure implements Exception {
  final String message;
  const SessionFailure(this.message);
}

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._();
  AuthService._()
      : transport = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15)));
  AuthService.forTesting(this.transport);
  final Dio transport; // Deliberately no auth/refresh interceptor.
  final _storage = const FlutterSecureStorage();
  SessionStatus status = SessionStatus.unknown;
  String? role;
  int _epoch = 0;
  bool _clearing = false;
  bool get isClearing => _clearing;
  int get epoch => _epoch;
  Future<void>? _writes;
  Future<String?>? _refreshing;
  int _refreshEpoch = -1;
  Future<T> _locked<T>(Future<T> Function() work) {
    final result =
        _writes == null ? Future<T>.sync(work) : _writes!.then((_) => work());
    final tail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writes = tail;
    tail.then((_) {
      if (identical(_writes, tail)) _writes = null;
    });
    return result;
  }

  Future<Map<String, dynamic>> snapshot() async =>
      _clearing ? <String, dynamic>{} : await _snapshot();
  Future<Map<String, dynamic>> _snapshot() async {
    final raw = await _storage.read(key: 'auth_session');
    if (raw != null) {
      try {
        return objectMap(jsonDecode(raw));
      } catch (_) {
        return {};
      }
    }
    return {
      'accessToken': await _storage.read(key: 'access_token'),
      'refreshToken': await _storage.read(key: 'refresh_token'),
      'user': {
        'id': await _storage.read(key: 'user_id'),
        'role': await _storage.read(key: 'user_role')
      }
    };
  }

  static DateTime? expiry(String? token) {
    try {
      final data = objectMap(jsonDecode(utf8.decode(
          base64Url.decode(base64Url.normalize(token!.split('.')[1])))));
      return data['exp'] is int
          ? DateTime.fromMillisecondsSinceEpoch((data['exp'] as int) * 1000)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<Response<dynamic>> _request(String method, String path,
      {Object? data, String? token}) {
    transport.options.baseUrl = ApiConstants.baseUrl;
    return transport.request(path,
        data: data,
        options: Options(
            method: method,
            headers: {if (token != null) 'Authorization': 'Bearer $token'}));
  }

  Map<String, dynamic> _tokens(Object? body,
      {String? expectedId, String? expectedRole}) {
    final data = objectMap(body), user = objectMap(objectMap(body)['user']);
    if (data['success'] != true ||
        textValue(data['accessToken']) == null ||
        textValue(data['refreshToken']) == null ||
        textValue(user['id']) == null ||
        !['user', 'mechanic'].contains(user['role']) ||
        (expectedId != null && user['id'] != expectedId) ||
        (expectedRole != null && user['role'] != expectedRole)) {
      throw const SessionFailure(
          'Session confirmation is invalid. Please sign in again.');
    }
    return {
      'accessToken': data['accessToken'],
      'refreshToken': data['refreshToken'],
      'user': user
    };
  }

  Future<void> _store(Map<String, dynamic> data, int generation) =>
      _locked(() async {
        if (generation != _epoch) {
          throw const SessionFailure('Session changed. Please sign in again.');
        }
        // Canonical snapshot is a single secure-storage write; legacy keys are only
        // compatibility mirrors for existing screens, never the refresh source.
        await _storage.write(key: 'auth_session', value: jsonEncode(data));
        final user = objectMap(data['user']);
        for (final entry in {
          'access_token': data['accessToken'],
          'refresh_token': data['refreshToken'],
          'user_id': user['id'],
          'user_role': user['role'],
          'user_name': user['name'],
          'phone': user['phone']
        }.entries) {
          await _storage.write(key: entry.key, value: entry.value?.toString());
        }
        if (generation != _epoch) {
          throw const SessionFailure('Session changed.');
        }
        role = user['role'] as String;
      });
  Future<Map<String, dynamic>> authenticate(
      String path, Map<String, dynamic> body) async {
    final ending = _end();
    final generation = _epoch;
    final previous = await ending;
    await _revoke(textValue(previous['refreshToken']));
    if (generation != _epoch) throw const SessionFailure('Session changed.');
    final r = await _request('POST', path, data: body);
    final data = _tokens(r.data);
    if (generation != _epoch) throw const SessionFailure('Session changed.');
    // Invalidate anonymous requests started while the sign-in was pending.
    final committedGeneration = ++_epoch;
    await _store(data, committedGeneration);
    if (committedGeneration != _epoch) {
      throw const SessionFailure('Session changed.');
    }
    status = SessionStatus.authenticated;
    notifyListeners();
    bindSocket();
    return objectMap(data['user']);
  }

  void bindSocket() {
    SocketService().recoverCredentials =
        (force) => accessToken(forceRefresh: force);
  }

  Future<String?> accessToken({bool forceRefresh = false}) async {
    final data = await snapshot();
    final token = textValue(data['accessToken']);
    final expires = expiry(token);
    if ((token == null && textValue(data['refreshToken']) != null) ||
        forceRefresh ||
        (expires != null &&
            expires
                .isBefore(DateTime.now().add(const Duration(seconds: 30))))) {
      return refresh();
    }
    return token;
  }

  Future<String?> getAccessToken() async {
    try {
      return await accessToken();
    } on SessionFailure {
      return null;
    }
  }

  Future<String?> getUserRole() async =>
      textValue(objectMap((await snapshot())['user'])['role']);
  Future<String?> getUserId() async =>
      textValue(objectMap((await snapshot())['user'])['id']);
  Future<String?> refresh() {
    if (_refreshing != null && _refreshEpoch == _epoch) return _refreshing!;
    final generation = _epoch;
    _refreshEpoch = generation;
    final future = _rotate(generation);
    _refreshing = future;
    future.then((_) {
      if (identical(_refreshing, future)) _refreshing = null;
    }, onError: (Object _, StackTrace __) {
      if (identical(_refreshing, future)) _refreshing = null;
    });
    return future;
  }

  Future<String?> _rotate(int generation) async {
    final previous = await snapshot();
    final token = textValue(previous['refreshToken']);
    if (token == null) {
      if (generation == _epoch) await clearTokens();
      return null;
    }
    try {
      final r = await _request('POST', '/auth/refresh',
          data: {'refreshToken': token});
      if (generation != _epoch) throw const SessionFailure('Session changed.');
      final user = objectMap(previous['user']);
      final data = _tokens(r.data,
          expectedId: textValue(user['id']),
          expectedRole: textValue(user['role']));
      await _store(data, generation);
      if (generation != _epoch) throw const SessionFailure('Session changed.');
      status = SessionStatus.authenticated;
      notifyListeners();
      SocketService().replaceCredentials(data['accessToken'] as String);
      return data['accessToken'] as String;
    } on DioException catch (e) {
      if (generation != _epoch) throw const SessionFailure('Session changed.');
      if ([400, 401, 403, 409].contains(e.response?.statusCode)) {
        await clearTokens();
        throw const SessionFailure('Session expired. Please sign in again.');
      }
      throw const SessionFailure(
          'Unable to refresh your session. Check connection and retry.');
    } on SessionFailure {
      // Malformed success may follow a committed rotation: require sign-in;
      // never repeatedly replay the old refresh token.
      if (generation == _epoch) await clearTokens();
      rethrow;
    }
  }

  Future<SessionStatus> recover() async {
    bindSocket();
    final generation = _epoch;
    try {
      final token = await accessToken();
      if (generation != _epoch) return status;
      if (token == null) {
        await clearTokens();
        return status;
      }
      Response<dynamic> r;
      try {
        r = await _request('GET', '/auth/session', token: token);
      } on DioException catch (e) {
        if (e.response?.statusCode != 401) rethrow;
        final renewed = await refresh();
        if (renewed == null) return status;
        r = await _request('GET', '/auth/session', token: renewed);
      }
      if (generation != _epoch) return status;
      final body = objectMap(r.data), user = objectMap(body['user']);
      final data = await snapshot(), oldUser = objectMap(data['user']);
      if (body['success'] != true ||
          textValue(user['id']) == null ||
          !['user', 'mechanic'].contains(user['role']) ||
          (textValue(oldUser['id']) != null && oldUser['id'] != user['id']) ||
          (textValue(oldUser['role']) != null &&
              oldUser['role'] != user['role'])) {
        await clearTokens();
        return status;
      }
      data['user'] = user;
      await _store(data, generation);
      if (generation == _epoch) {
        status = SessionStatus.authenticated;
        notifyListeners();
      }
    } on DioException catch (e) {
      if (generation != _epoch) return status;
      if ([401, 403, 404].contains(e.response?.statusCode)) {
        await clearTokens();
      } else {
        status = SessionStatus.offline;
        notifyListeners();
      }
    } on SessionFailure {
      if (generation == _epoch) {
        status = SessionStatus.offline;
        notifyListeners();
      }
    }
    return status;
  }

  Future<Map<String, dynamic>> _end() {
    final generation = ++_epoch;
    _clearing = true;
    role = null;
    status = SessionStatus.signedOut;
    SocketService().disconnect();
    notifyListeners();
    return _locked(() async {
      final previous = await _snapshot();
      for (final key in [
        'auth_session',
        'access_token',
        'refresh_token',
        'user_role',
        'user_id',
        'user_name',
        'phone',
        'token'
      ]) {
        await _storage.delete(key: key);
      }
      return previous;
    }).whenComplete(() {
      if (generation == _epoch) _clearing = false;
    });
  }

  Future<void> clearTokens() async {
    await _end();
  }

  Future<void> _revoke(String? token) async {
    if (token == null) return;
    try {
      await _request('POST', '/auth/logout', data: {'refreshToken': token})
          .timeout(const Duration(seconds: 5));
    } catch (_) {/* Local logout remains final even offline. */}
  }

  Future<void> logout() async {
    final previous = await _end();
    await _revoke(textValue(previous['refreshToken']));
  }

  Future<bool> isLoggedIn() async =>
      await recover() == SessionStatus.authenticated;
}
