import 'dart:math';
import 'package:hive/hive.dart';

class ForensicEraserService {
  static final ForensicEraserService _instance = ForensicEraserService._internal();
  factory ForensicEraserService() => _instance;
  ForensicEraserService._internal();

  final Random _random = Random.secure();
  static const String _chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()';

  /// Check if Forensic Eraser Mode is enabled in settings
  bool isForensicEraserEnabled() {
    try {
      final settingsBox = Hive.box('settings');
      return settingsBox.get('forensic_eraser_enabled', defaultValue: false) as bool;
    } catch (_) {
      return false;
    }
  }

  /// Check if Active Chat Randomization is enabled in settings
  bool isActiveChatRandomizationEnabled() {
    try {
      final settingsBox = Hive.box('settings');
      return settingsBox.get('active_chat_randomization_enabled', defaultValue: false) as bool;
    } catch (_) {
      return false;
    }
  }

  /// Generate random character noise of a specific length
  String generateRandomNoise(int length) {
    if (length <= 0) return '';
    return List.generate(length, (index) => _chars[_random.nextInt(_chars.length)]).join();
  }

  /// Shreds a Hive database value by overwriting it with random noise first,
  /// flushing to disk, and then calling delete.
  Future<void> shredBoxValue(Box box, dynamic key) async {
    try {
      if (!box.containsKey(key)) return;

      final value = box.get(key);
      if (value != null && isForensicEraserEnabled()) {
        // Compute approximate string/byte length to overwrite
        final int valueLength = value.toString().length;
        final String noise = generateRandomNoise(valueLength);

        // 1. Overwrite in-place with random garbage
        await box.put(key, noise);

        // 2. Force physical disk sync block flush
        await box.flush();
      }

      // 3. Perform standard deletion
      await box.delete(key);
    } catch (_) {
      // Fail silently to prevent app lockups
      await box.delete(key);
    }
  }
}
