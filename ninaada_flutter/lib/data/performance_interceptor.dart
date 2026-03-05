import 'package:dio/dio.dart';
import 'package:ninaada_music/core/app_logger.dart';

/// Dio interceptor that measures request→response latency.
///
/// - Stamps `start_time` into `options.extra` on every outgoing request.
/// - On response/error, calculates duration and logs via [AppLogger]:
///     ≥ 2 000 ms → `AppLogger.warning` (survives release builds)
///     < 2 000 ms → `AppLogger.debug`   (stripped in release)
///
/// Add this **before** any cache interceptors so it measures the
/// true network round-trip, not a local cache hit.
class PerformanceInterceptor extends Interceptor {
  static const int _slowThresholdMs = 2000;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['start_time'] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _log(response.requestOptions, response.statusCode ?? 0);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(err.requestOptions, err.response?.statusCode ?? 0, isError: true);
    handler.next(err);
  }

  void _log(RequestOptions opts, int statusCode, {bool isError = false}) {
    final startTime = opts.extra['start_time'] as int?;
    if (startTime == null) return;

    final duration = DateTime.now().millisecondsSinceEpoch - startTime;
    final method = opts.method;
    final path = opts.path;
    final status = statusCode > 0 ? ' [$statusCode]' : '';

    if (duration >= _slowThresholdMs) {
      AppLogger.warning(
        '🐢 SLOW API: [$method] $path took ${duration}ms$status'
        '${isError ? ' (ERROR)' : ''}',
      );
    } else {
      AppLogger.debug(
        '⚡ FAST API: [$method] $path took ${duration}ms$status'
        '${isError ? ' (ERROR)' : ''}',
      );
    }
  }
}
