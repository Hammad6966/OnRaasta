import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models/bid_model.dart';
import 'api_service.dart';

class MediaService {
  MediaService({Dio? dio}) : dio = dio ?? ApiService.instance.dio;
  final Dio dio;
  static final instance = MediaService();

  Future<Map<String, dynamic>> documents() async =>
      objectMap((await dio.get('/mechanics/documents')).data['data']);

  Future<Map<String, dynamic>> submit(Map<String, dynamic> body) async =>
      objectMap((await dio.post('/mechanics/documents/submit', data: body))
          .data['data']);

  Future<Map<String, dynamic>> upload(String path, Uint8List bytes, String name,
      String mime, void Function(int, int) progress,
      {int? expectedVersion}) async {
    final result = await dio.post(path,
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes,
              filename: name, contentType: DioMediaType.parse(mime)),
          if (expectedVersion != null) 'expectedVersion': expectedVersion,
        }),
        options: Options(
            contentType: 'multipart/form-data',
            sendTimeout: const Duration(minutes: 2),
            receiveTimeout: const Duration(minutes: 2)),
        onSendProgress: progress);
    return objectMap(result.data['data']);
  }

  Future<Uint8List> bytes(String path) async {
    final result = await dio.get<List<int>>(path,
        options: Options(responseType: ResponseType.bytes));
    return Uint8List.fromList(result.data!);
  }
}

String? uploadMime(Uint8List b, {bool pdf = false}) {
  if (b.length < 12 || b.length > 8 * 1024 * 1024) return null;
  if (b[0] == 255 && b[1] == 216 && b[2] == 255) return 'image/jpeg';
  if (b[0] == 137 && b[1] == 80 && b[2] == 78 && b[3] == 71) return 'image/png';
  if (String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') return 'image/webp';
  if (pdf && String.fromCharCodes(b.sublist(0, 5)) == '%PDF-')
    return 'application/pdf';
  return null;
}
