import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConstants {
  ApiConstants._();
  static const _server = String.fromEnvironment('ONRAASTA_SERVER_URL');
  static const _ai = String.fromEnvironment('ONRAASTA_AI_URL');
  static String? _runtimeHost;

  // Compile-time configuration wins over old saved development IP addresses.
  static bool get hasConfiguredServer => _server.isNotEmpty;
  static String _env(String key) =>
      dotenv.isInitialized ? dotenv.env[key]?.trim() ?? '' : '';
  static Uri _url(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
          'A valid server URL without credentials is required.');
    }
    return uri;
  }

  static String get serverIp => _runtimeHost ?? _url(baseUrl).host;
  static bool validServerHost(String host) {
    final uri = Uri.tryParse('http://$host:5000');
    return host.isNotEmpty &&
        uri != null &&
        uri.host == host &&
        uri.userInfo.isEmpty &&
        uri.path.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  static set serverIp(String value) {
    if (!validServerHost(value)) {
      throw const FormatException('Invalid server host');
    }
    _runtimeHost = value;
  }

  static String get baseUrl {
    if (_server.isNotEmpty) return '${_url(_server).origin}/api';
    if (_runtimeHost != null) return 'http://$_runtimeHost:5000/api';
    final configured = _env('API_BASE_URL');
    if (configured.isNotEmpty) {
      return _url(configured).toString().replaceFirst(RegExp(r'/$'), '');
    }
    // Android emulator development only; phones require explicit config.
    return 'http://10.0.2.2:5000/api';
  }

  // A single origin prevents API, refresh and socket identities diverging.
  static String get socketUrl => _url(baseUrl).origin;
  static String get aiUrl {
    if (_ai.isNotEmpty) {
      return _url(_ai).toString().replaceFirst(RegExp(r'/$'), '');
    }
    if (_runtimeHost != null && !hasConfiguredServer) {
      return 'http://$_runtimeHost:8000';
    }
    final configured = _env('AI_URL');
    if (configured.isNotEmpty && !hasConfiguredServer) {
      return _url(configured).toString().replaceFirst(RegExp(r'/$'), '');
    }
    return _url(socketUrl)
        .replace(port: 8000)
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }
}
