class ApiConstants {
  ApiConstants._();

  static String serverIp = '192.168.137.59';

  static String get baseUrl   => 'http://$serverIp:5000/api';
  static String get socketUrl => 'http://$serverIp:5000';
  static String get aiUrl     => 'http://$serverIp:8000';

  static const String googleMapsKey = 'REPLACE_WITH_KEY';
}
