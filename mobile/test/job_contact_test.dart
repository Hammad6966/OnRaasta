import 'package:flutter_test/flutter_test.dart';
import 'package:onraasta/services/job_contact_service.dart';

void main() {
  test('Pakistani mobile formats produce a dialable +92 number', () {
    for (final value in [
      '03001234567',
      '3001234567',
      '+923001234567',
      '923001234567',
      '00923001234567',
      '+92 300-1234567',
    ]) {
      expect(pakistaniDialNumber(value), '+923001234567');
      expect(pakistaniDialUri(value).toString(), 'tel:+923001234567');
    }
  });

  test('invalid or missing contact is rejected before launching', () {
    for (final value in [
      null,
      '',
      '12345',
      '+923001234567;123',
      '031234567890'
    ]) {
      expect(pakistaniDialNumber(value), isNull);
    }
  });
}
