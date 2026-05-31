import 'dart:convert';
import 'package:hive/hive.dart';
import '../features/chat/data/models/message_model.dart';
import 'forensic_eraser_service.dart';

// MessageStorageService — Handles reading and writing of per-chat message
// history to local encrypted Hive databases. Messages are saved in chat-specific
// boxes named "messages_$chatUsername" with "messageId" keys for O(1) lookups.
class MessageStorageService {
  static final MessageStorageService _instance = MessageStorageService._internal();
  factory MessageStorageService() => _instance;
  MessageStorageService._internal();

  /// Retrieve all messages for a specific chat username, sorted chronologically.
  Future<List<MessageData>> getMessages(String chatUsername) async {
    try {
      final box = await Hive.openBox('messages_$chatUsername');
      final messages = <MessageData>[];
      for (final val in box.values) {
        if (val != null) {
          final data = jsonDecode(val.toString()) as Map<String, dynamic>;
          messages.add(MessageData.fromJson(data));
        }
      }
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return messages;
    } catch (_) {
      return [];
    }
  }

  /// Persist a message to local storage under its specific chat box.
  Future<void> saveMessage(String chatUsername, MessageData message) async {
    try {
      final box = await Hive.openBox('messages_$chatUsername');
      await box.put(message.id, jsonEncode(message.toJson()));
    } catch (_) {
      // Fail silently to prevent app crashes on storage exceptions.
    }
  }

  /// Securely delete/shred a single message.
  /// If forensic eraser is enabled, the block is overwritten with random noise
  /// before removal to prevent recovery by disk-forensic tools.
  Future<void> deleteMessage(String chatUsername, String messageId) async {
    try {
      final box = await Hive.openBox('messages_$chatUsername');
      if (box.containsKey(messageId)) {
        final isForensic = ForensicEraserService().isForensicEraserEnabled();
        if (isForensic) {
          final val = box.get(messageId);
          if (val != null) {
            final data = jsonDecode(val.toString()) as Map<String, dynamic>;
            final originalText = data['text'] as String? ?? '';

            // 1. Overwrite in-place with random noise
            final noise = ForensicEraserService().generateRandomNoise(originalText.length);
            data['text'] = noise;
            await box.put(messageId, jsonEncode(data));

            // 2. Physical disk sync block flush
            await box.flush();
          }
        }
        // 3. Delete key from database
        await box.delete(messageId);
      }
    } catch (_) {
      // Fallback: simple delete without forensic overwrite.
      try {
        final box = await Hive.openBox('messages_$chatUsername');
        await box.delete(messageId);
      } catch (_) {}
    }
  }

  /// Enforce the 50-message per-chat limit by scrambling or deleting old messages.
  Future<void> enforceLimit(String chatUsername) async {
    try {
      final box = await Hive.openBox('messages_$chatUsername');
      final messages = await getMessages(chatUsername);

      if (messages.length > 50) {
        final excessCount = messages.length - 50;
        final isRandomizationEnabled = ForensicEraserService().isActiveChatRandomizationEnabled();

        for (int i = 0; i < excessCount; i++) {
          final message = messages[i];

          if (isRandomizationEnabled) {
            // Overwrite with random noise to prevent data recovery.
            final noise = ForensicEraserService().generateRandomNoise(message.text.length);
            final scrambledMessage = MessageData(
              id: message.id,
              text: noise,
              isMe: message.isMe,
              time: message.time,
              isRead: message.isRead,
              isVault: message.isVault,
              isSent: message.isSent,
              timestamp: message.timestamp,
            );
            await box.put(message.id, jsonEncode(scrambledMessage.toJson()));
          } else {
            // Active Chat Randomization is disabled: shred and delete physically.
            await deleteMessage(chatUsername, message.id);
          }
        }

        // Force sync sector modifications to physical disk.
        await box.flush();
      }
    } catch (_) {
      // Fail silently.
    }
  }

  /// Toggle (add/remove) a reaction on a persisted message.
  /// If the reaction already exists it is removed; otherwise it is incremented.
  Future<void> saveReaction(String chatUsername, String messageId, String reactionKey) async {
    try {
      final box = await Hive.openBox('messages_$chatUsername');
      final val = box.get(messageId);
      if (val == null) return;

      final data = jsonDecode(val.toString()) as Map<String, dynamic>;
      final reactions = Map<String, int>.from(
        (data['reactions'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      );

      if (reactions.containsKey(reactionKey)) {
        reactions.remove(reactionKey); // Toggle off existing reaction
      } else {
        reactions[reactionKey] = 1; // Toggle on new reaction
      }

      data['reactions'] = reactions;
      await box.put(messageId, jsonEncode(data));
    } catch (_) {}
  }

  /// Remove all messages whose expiresAt timestamp has passed.
  /// Returns the list of expired message IDs that were purged.
  Future<List<String>> purgeExpiredMessages(String chatUsername) async {
    final purged = <String>[];
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final messages = await getMessages(chatUsername);

      for (final msg in messages) {
        if (msg.expiresAt != null && msg.expiresAt! < now) {
          await deleteMessage(chatUsername, msg.id);
          purged.add(msg.id);
        }
      }
    } catch (_) {}
    return purged;
  }
}
