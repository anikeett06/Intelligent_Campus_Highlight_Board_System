import 'package:dio/dio.dart';

/// FastAPI often returns `detail` as a string, or a list of `{msg, loc, ...}` objects.
String? detailFromResponseData(dynamic data) {
  if (data == null) return null;
  if (data is String) {
    final t = data.trim();
    return t.isEmpty ? null : t;
  }
  if (data is Map) {
    final detail = data["detail"];
    if (detail is String) {
      final t = detail.trim();
      return t.isEmpty ? null : t;
    }
    if (detail is List) {
      final parts = <String>[];
      for (final item in detail) {
        if (item is Map) {
          final msg = item["msg"]?.toString().trim();
          if (msg != null && msg.isNotEmpty) {
            parts.add(msg);
          }
        } else if (item is String && item.trim().isNotEmpty) {
          parts.add(item.trim());
        }
      }
      if (parts.isNotEmpty) {
        return parts.join("\n");
      }
    }
  }
  return null;
}

/// User-facing text for API failures (avoids raw Dio / XMLHttpRequest strings on web).
String mapDioToUserMessage(DioException e) {
  final fromBody = detailFromResponseData(e.response?.data);
  if (fromBody != null && fromBody.isNotEmpty) {
    return fromBody;
  }

  final status = e.response?.statusCode;
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return "Request timed out. Check your connection and try again.";
    case DioExceptionType.connectionError:
      return "Cannot reach the campus server. Check your network, API address in settings, "
          "and that the backend is running.";
    case DioExceptionType.badResponse:
      if (status == 401) {
        return "Your session may have expired. Sign in again.";
      }
      if (status == 400 || status == 422) {
        return "The server could not accept this request. Check the fields and try again.";
      }
      if (status == 403) {
        return "You do not have permission for this action.";
      }
      if (status == 404) {
        return "That resource was not found. It may have been removed.";
      }
      if (status != null && status >= 500) {
        return "Server error. Please try again in a moment.";
      }
      return "Request failed${status != null ? " ($status)" : ""}.";
    case DioExceptionType.cancel:
      return "Request was cancelled.";
    case DioExceptionType.badCertificate:
      return "Secure connection failed. Check date/time and network settings.";
    case DioExceptionType.unknown:
      final raw = (e.message ?? "").toLowerCase();
      if (raw.contains("xmlhttprequest") ||
          raw.contains("failed host lookup") ||
          raw.contains("socket") ||
          raw.contains("network")) {
        return "Network error. Check your connection and API address, then try again.";
      }
      return "Something went wrong. Please try again.";
  }
}

String userMessageFromUnknown(Object e) {
  if (e is DioException) {
    return mapDioToUserMessage(e);
  }
  final s = e.toString();
  if (s.contains("SocketException") || s.contains("HandshakeException")) {
    return "Network error. Check your connection and try again.";
  }
  return "Something went wrong. Please try again.";
}
