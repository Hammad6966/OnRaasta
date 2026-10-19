import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../models/bid_model.dart';
import 'auth_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() : auth = AuthService.instance;
  ApiService.forTesting(this.auth);
  static ApiService get instance => _instance;
  final AuthService auth;
  late final Dio dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'}))
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        options.baseUrl = ApiConstants.baseUrl;
        final generation = options.extra['sessionEpoch'] as int? ?? auth.epoch;
        options.extra['sessionEpoch'] = generation;
        if (generation != auth.epoch || auth.isClearing) {
          handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
              message: 'Session changed.'));
          return;
        }
        if (!options.path.startsWith('/auth/')) {
          try {
            final token = await auth.accessToken();
            if (generation != auth.epoch) {
              handler.reject(DioException(
                  requestOptions: options,
                  type: DioExceptionType.cancel,
                  message: 'Session changed.'));
              return;
            }
            options.headers.remove('Authorization');
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          } on SessionFailure catch (e) {
            handler.reject(
                DioException(requestOptions: options, message: e.message));
            return;
          }
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (response.requestOptions.extra['sessionEpoch'] != auth.epoch) {
          handler.reject(DioException(
              requestOptions: response.requestOptions,
              type: DioExceptionType.cancel,
              message: 'Session changed.'));
          return;
        }
        handler.next(response);
      },
      onError: (error, handler) async {
        final request = error.requestOptions;
        if (request.extra['sessionEpoch'] != auth.epoch ||
            request.path.startsWith('/auth/')) {
          handler.next(error);
          return;
        }
        final status = error.response?.statusCode;
        final expired =
            objectMap(error.response?.data)['code'] == 'ACCESS_TOKEN_EXPIRED';
        if (status == 403 &&
            objectMap(error.response?.data)['code'] == 'ACCOUNT_UNAVAILABLE') {
          await auth.clearTokens();
          handler.next(error);
          return;
        }
        if (status != 401 || request.extra['authRetried'] == true) {
          handler.next(error);
          return;
        }
        if (!expired) {
          await auth.clearTokens();
          handler.next(error);
          return;
        }
        try {
          // Reuse a refresh already completed for another request's stale 401.
          final stored = await auth.snapshot();
          final old = request.headers['Authorization'];
          final current = textValue(stored['accessToken']);
          final token = current != null && old != 'Bearer $current'
              ? current
              : await auth.refresh();
          if (token == null || request.extra['sessionEpoch'] != auth.epoch) {
            handler.next(error);
            return;
          }
          // Only this explicit middleware error proves a mutation never ran.
          // No retries on timeouts, generic 401s, 5xx or ambiguous outcomes.
          if (request.data is Stream || request.data is FormData) {
            handler.next(error);
            return;
          }
          request.extra['authRetried'] = true;
          request.headers['Authorization'] = 'Bearer $token';
          handler.resolve(await dio.fetch(request));
        } on SessionFailure catch (e) {
          handler.reject(
              DioException(requestOptions: request, message: e.message));
        } on DioException catch (e) {
          handler.next(e);
        }
      },
    ));
}
