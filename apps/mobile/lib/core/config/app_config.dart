// ============================================================
//  AppConfig — Centralized environment configuration for Chatly.
//
//  All server URLs and environment-specific settings live here.
//  In development, they fall back to localhost defaults so the app
//  runs immediately out of the box with no setup required.
//
//  For production builds, pass these in via --dart-define:
//    flutter build apk --dart-define=BASE_URL=https://api.chatly.app
// ============================================================

class AppConfig {
  AppConfig._(); // Prevent instantiation — all members are static.

  // ---------------------------------------------------------------------------
  // Base server URL.
  // Reads the compile-time define BASE_URL if provided; falls back to the
  // production Render backend.
  // ---------------------------------------------------------------------------
  static const String apiBaseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://chatly-backend-nepf.onrender.com/api',
  );

  // ---------------------------------------------------------------------------
  // WebSocket URL (derived automatically from the base URL).
  // Converts http:// → ws:// and https:// → wss:// at runtime.
  // ---------------------------------------------------------------------------
  static String get wsBaseUrl {
    const base = String.fromEnvironment(
      'WS_URL',
      defaultValue: 'wss://chatly-backend-nepf.onrender.com',
    );
    if (base == 'wss://chatly-backend-nepf.onrender.com' &&
        apiBaseUrl != 'https://chatly-backend-nepf.onrender.com/api') {
      return apiBaseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://')
          .replaceAll('/api', '');
    }
    return base;
  }

  // ---------------------------------------------------------------------------
  // App metadata
  // ---------------------------------------------------------------------------
  static const String appName = 'Chatly';
  static const String appVersion = '1.0.0';
  static const String buildNumber = '1';

  // ---------------------------------------------------------------------------
  // Network timeouts
  // ---------------------------------------------------------------------------
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
}
