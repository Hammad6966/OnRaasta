import 'package:dio/dio.dart';
import '../models/bid_model.dart';
import 'api_service.dart';

class JobMessage {
  final String id, jobId, senderId, text;
  final DateTime createdAt;
  JobMessage.fromJson(Object? value)
      : id = objectId(objectMap(value)['_id']) ??
            (throw const FormatException()),
        jobId = objectId(objectMap(value)['jobId']) ??
            (throw const FormatException()),
        senderId = objectId(objectMap(value)['senderId']) ??
            (throw const FormatException()),
        text = textValue(objectMap(value)['text']) ??
            (throw const FormatException()),
        createdAt =
            DateTime.parse(textValue(objectMap(value)['createdAt']) ?? '');
}

class MessagePage {
  final List<JobMessage> messages;
  final String? nextBefore;
  MessagePage(this.messages, this.nextBefore);
}

class JobChatService {
  final Dio dio;
  JobChatService({Dio? client}) : dio = client ?? ApiService.instance.dio;

  Future<MessagePage> load(String jobId, {String? before}) async {
    final response = await dio.get('/jobs/$jobId/messages',
        queryParameters: {if (before != null) 'before': before});
    final data = objectMap(response.data);
    if (data['success'] != true || data['data'] is! List)
      throw const FormatException('Invalid message history.');
    return MessagePage((data['data'] as List).map(JobMessage.fromJson).toList(),
        textValue(data['nextBefore']));
  }

  Future<JobMessage> send(String jobId, String text) async {
    final response =
        await dio.post('/jobs/$jobId/messages', data: {'text': text});
    final data = objectMap(response.data);
    if (data['success'] != true)
      throw const FormatException('Message was not confirmed.');
    return JobMessage.fromJson(data['data']);
  }
}
