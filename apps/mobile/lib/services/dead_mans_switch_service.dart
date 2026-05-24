import 'package:hive/hive.dart';
import 'auth_service.dart';
import 'websocket_service.dart';

class DeadMansSwitchService {
  static final DeadMansSwitchService _instance = DeadMansSwitchService._internal();
  factory DeadMansSwitchService() => _instance;
  DeadMansSwitchService._internal();

  // Inactivity threshold configuration (default 30 days)
  static const int defaultThresholdDays = 30;

  /// Update the last active timestamp to the current time.
  Future<void> updateLastActive() async {
    try {
      final settingsBox = await Hive.openBox('settings');
      final nowStr = DateTime.now().toIso8601String();
      await settingsBox.put('last_active_at', nowStr);
    } catch (_) {
      // Fail silently to prevent app crashes on database lock
    }
  }

  /// Checks if the inactivity threshold has been exceeded.
  /// If so, executes a complete secure wipe of all local data.
  /// Returns [true] if a wipe was triggered, [false] otherwise.
  Future<bool> checkAndTrigger() async {
    try {
      final settingsBox = await Hive.openBox('settings');
      final lastActiveStr = settingsBox.get('last_active_at');

      if (lastActiveStr != null) {
        final lastActive = DateTime.parse(lastActiveStr);
        final difference = DateTime.now().difference(lastActive);
        
        final thresholdDays = settingsBox.get('dead_mans_switch_days', defaultValue: defaultThresholdDays) as int;

        if (difference.inDays >= thresholdDays) {
          // Inactivity threshold exceeded! Shred all data.
          await wipeAllData();
          return true;
        }
      }
      
      // Update last active on successful check
      await updateLastActive();
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Destroys all local secure keys, tokens, outbox databases, settings, and session caches.
  Future<void> wipeAllData() async {
    // 1. Disconnect WS connection immediately
    WebSocketService().disconnect();

    // 2. Open and completely clear all local Hive boxes
    final settingsBox = await Hive.openBox('settings');
    await settingsBox.clear();

    final secureBox = await Hive.openBox('secure_vault');
    await secureBox.clear();

    final outboxBox = await Hive.openBox('outbox');
    await outboxBox.clear();

    final messagesBox = await Hive.openBox('messages');
    await messagesBox.clear();

    // 3. Reset AuthService local variables
    final authService = AuthService();
    await authService.logout(); // Wipes residual tokens in memory & DB
  }
}
