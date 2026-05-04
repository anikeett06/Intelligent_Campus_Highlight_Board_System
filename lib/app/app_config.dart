import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

const String configuredBaseUrl = String.fromEnvironment("API_BASE_URL", defaultValue: "");

/// Default API port (must match README / typical `uvicorn --port 8010`).
const int kDefaultApiPort = 8010;

const String _defaultApiRoot = "/api/v1";

bool _isLegacy8011DevHost(String host) {
  final h = host.toLowerCase();
  return h == '127.0.0.1' || h == 'localhost' || h == '10.0.2.2' || h == '::1';
}

/// Old app builds defaulted to port 8011; migrate stored URLs on dev hosts to [kDefaultApiPort].
String migrateLegacyApiPort8011(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasPort || uri.port != 8011) return raw.trim();
  if (!_isLegacy8011DevHost(uri.host)) return raw.trim();
  return uri.replace(port: kDefaultApiPort).toString();
}

String _loopbackBase() => "http://127.0.0.1:$kDefaultApiPort$_defaultApiRoot";

/// Android emulator: `10.0.2.2` is the host machine. Physical device: set URL in-app.
String _androidEmulatorBase() => "http://10.0.2.2:$kDefaultApiPort$_defaultApiRoot";

/// Default API root (must include `/api/v1`). Override with `--dart-define=API_BASE_URL=...`
/// or set in-app on the login screen (saved to secure storage).
String resolvedDefaultBaseUrl() {
  if (configuredBaseUrl.isNotEmpty) {
    return configuredBaseUrl;
  }
  if (kIsWeb) {
    return _loopbackBase();
  }
  // Desktop: hit API on this machine. Physical Android/iOS: use "Change server URL" + PC LAN IP.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return _loopbackBase();
  }
  if (Platform.isAndroid) {
    return _androidEmulatorBase();
  }
  if (Platform.isIOS) {
    // Simulator can use loopback; device on LAN needs in-app URL override.
    return _loopbackBase();
  }
  return _loopbackBase();
}

String normalizeApiBaseUrl(String raw) {
  var s = migrateLegacyApiPort8011(raw).trim();
  if (s.isEmpty) {
    return resolvedDefaultBaseUrl();
  }
  if (!s.startsWith("http://") && !s.startsWith("https://")) {
    s = "http://$s";
  }
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) {
    return resolvedDefaultBaseUrl();
  }
  final origin = uri.origin;
  final path = uri.path;
  if (path.isEmpty || path == "/") {
    return "$origin$_defaultApiRoot";
  }
  return s.replaceAll(RegExp(r"/$"), "");
}
