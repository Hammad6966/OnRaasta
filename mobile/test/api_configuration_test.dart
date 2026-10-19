import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onraasta/core/constants/api_constants.dart';

void main() {
  if (ApiConstants.hasConfiguredServer) {
    test('explicit build URLs override saved hosts and stale asset environment',
        () {
      dotenv.testLoad(
          fileInput:
              'API_BASE_URL=http://obsolete.example.test/api\nAI_URL=http://obsolete.example.test:8000');
      ApiConstants.serverIp = 'obsolete-saved-host';
      expect(ApiConstants.baseUrl, 'https://fixture-server.example.test/api');
      expect(ApiConstants.socketUrl, 'https://fixture-server.example.test');
      expect(ApiConstants.aiUrl, 'https://fixture-ai.example.test');
    });
    return;
  }
  test('configured environment uses one API and socket origin', () {
    dotenv.testLoad(
        fileInput:
            'API_BASE_URL=https://backend.example.test/api\nSOCKET_URL=http://obsolete.example.test\nAI_URL=https://ai.example.test');
    expect(ApiConstants.baseUrl, 'https://backend.example.test/api');
    expect(ApiConstants.socketUrl, 'https://backend.example.test');
    expect(ApiConstants.aiUrl, 'https://ai.example.test');
  });
  test(
      'development host updates API, refresh origin, socket and diagnosis consistently',
      () {
    ApiConstants.serverIp = 'localhost';
    expect(ApiConstants.baseUrl, 'http://localhost:5000/api');
    expect(ApiConstants.socketUrl, 'http://localhost:5000');
    expect(ApiConstants.aiUrl, 'http://localhost:8000');
  });
  test(
      'server host rejects credentials, paths, supplied ports and invalid values',
      () {
    for (final value in [
      '',
      'a/b',
      'name@host',
      'host:5000',
      'host?query',
      'host#fragment'
    ]) {
      expect(ApiConstants.validServerHost(value), false);
    }
  });
}
