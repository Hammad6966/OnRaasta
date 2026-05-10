import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _storage = const FlutterSecureStorage();

  Future<String?> getAccessToken() => _storage.read(key: 'access_token');
  Future<String?> getUserRole()    => _storage.read(key: 'user_role');
  Future<String?> getUserId()      => _storage.read(key: 'user_id');

  Future<void> clearTokens() => Future.wait([
    _storage.delete(key: 'access_token'),
    _storage.delete(key: 'refresh_token'),
    _storage.delete(key: 'user_role'),
    _storage.delete(key: 'user_id'),
  ]);

  Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
