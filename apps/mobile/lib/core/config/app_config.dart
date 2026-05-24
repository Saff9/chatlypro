// ============================================================
//  AppConfig — Centralized environment configuration for Chatly.
//
//  All server URLs and environment-specific settings live here.
//  In development, they fall back to localhost defaults so the app
//  runs immediately out of the box with no setup required.
//
//  For production builds, pass these in via --dart-define:
//    flutter build apk --dart-define=BASE_URL=https://api.chatly.app
//
//  Author: Chatly Engineering Team
// ============================================================

class AppConfig {
  AppConfig._(); // Prevent instantiation — all members are static.

  // ---------------------------------------------------------------------------
  // Base server URL.
  // Reads the compile-time define BASE_URL if provided; falls back to localhost
  // so developers can run everything locally without any extra config.
  // ---------------------------------------------------------------------------
  static const String apiBaseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:5000/api',
  );

  // ---------------------------------------------------------------------------
  // WebSocket URL (derived automatically from the base URL).
  // Converts http:// → ws:// and https:// → wss:// at runtime.
  // ---------------------------------------------------------------------------
  static String get wsBaseUrl {
    const base = String.fromEnvironment(
      'WS_URL',
      defaultValue: 'ws://localhost:5000',
    );
    // If the user only provided BASE_URL, derive the WS url from it.
    if (base == 'ws://localhost:5000' && apiBaseUrl != 'http://localhost:5000/api') {
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
  // Feature flags — flip these to enable/disable experimental features without
  // touching any screen code.
  // ---------------------------------------------------------------------------

  /// When true, the P2P Mesh (UDP/TCP offline messaging) is active.
  static const bool enableP2PMesh = bool.fromEnvironment(
    'ENABLE_P2P',
    defaultValue: true,
  );

  /// When true, the Lucky Pulse anonymous feed is visible in navigation.
  static const bool enableLuckyPulse = bool.fromEnvironment(
    'ENABLE_PULSE',
    defaultValue: true,
  );

  // ---------------------------------------------------------------------------
  // Network timeouts
  // ---------------------------------------------------------------------------

  /// How long the client waits for a server response before timing out.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
}
