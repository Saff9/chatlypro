class MessageData {
  final String id;
  String text;
  final bool isMe;
  final String time;
  final bool isRead;
  final bool isVault;
  bool isSent;
  final int timestamp;

  /// Key = reaction icon name (e.g. 'thumb_up', 'favorite', 'bolt'),
  /// Value = total count of that reaction from all users.
  Map<String, int> reactions;

  /// Unix ms timestamp when this message expires (null = never).
  /// Only set for vault/disappearing messages.
  int? expiresAt;

  // New features
  final bool isTimeLocked;
  final int? unlocksAt;
  final bool isVoice;
  final int? voiceDuration;
  final String? voiceTranscript;

  MessageData({
    required this.id,
    required this.text,
    required this.isMe,
    required this.time,
    required this.isRead,
    this.isVault = false,
    this.isSent = true,
    required this.timestamp,
    Map<String, int>? reactions,
    this.expiresAt,
    this.isTimeLocked = false,
    this.unlocksAt,
    this.isVoice = false,
    this.voiceDuration,
    this.voiceTranscript,
  }) : reactions = reactions ?? {};

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isMe': isMe,
      'time': time,
      'isRead': isRead,
      'isVault': isVault,
      'isSent': isSent,
      'timestamp': timestamp,
      'reactions': reactions,
      'expiresAt': expiresAt,
      'isTimeLocked': isTimeLocked,
      'unlocksAt': unlocksAt,
      'isVoice': isVoice,
      'voiceDuration': voiceDuration,
      'voiceTranscript': voiceTranscript,
    };
  }

  factory MessageData.fromJson(Map<String, dynamic> json) {
    // Deserialise reactions map safely
    Map<String, int> parsedReactions = {};
    final rawReactions = json['reactions'];
    if (rawReactions is Map) {
      rawReactions.forEach((k, v) {
        if (k is String && v is int) parsedReactions[k] = v;
      });
    }

    return MessageData(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      isMe: json['isMe'] as bool? ?? true,
      time: json['time'] as String? ?? '',
      isRead: json['isRead'] as bool? ?? true,
      isVault: json['isVault'] as bool? ?? false,
      isSent: json['isSent'] as bool? ?? true,
      timestamp: json['timestamp'] as int? ?? 0,
      reactions: parsedReactions,
      expiresAt: json['expiresAt'] as int?,
      isTimeLocked: json['isTimeLocked'] as bool? ?? false,
      unlocksAt: json['unlocksAt'] as int?,
      isVoice: json['isVoice'] as bool? ?? false,
      voiceDuration: json['voiceDuration'] as int?,
      voiceTranscript: json['voiceTranscript'] as String?,
    );
  }
}
