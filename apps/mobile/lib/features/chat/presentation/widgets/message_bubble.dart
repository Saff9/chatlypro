import 'package:flutter/material.dart';
import '../../data/models/message_model.dart';

/// Available reaction types for long-press message menu.
const List<Map<String, dynamic>> kReactions = [
  {'key': 'thumb_up',                 'icon': Icons.thumb_up_rounded,                 'label': 'Like'},
  {'key': 'favorite',                 'icon': Icons.favorite_rounded,                 'label': 'Love'},
  {'key': 'bolt',                     'icon': Icons.bolt_rounded,                     'label': 'Wow'},
  {'key': 'sentiment_very_satisfied', 'icon': Icons.sentiment_very_satisfied_rounded, 'label': 'Haha'},
  {'key': 'sentiment_dissatisfied',   'icon': Icons.sentiment_dissatisfied_rounded,   'label': 'Sad'},
  {'key': 'celebration',              'icon': Icons.celebration_rounded,              'label': 'Celebrate'},
];

/// Custom painter to draw Telegram-style message bubbles with tails.
class BubbleBackgroundPainter extends CustomPainter {
  final bool isMe;
  final Color color;

  BubbleBackgroundPainter({required this.isMe, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    const r = 16.0; // corner radius
    const tw = 6.0; // tail width

    if (isMe) {
      // Draw me bubble
      path.moveTo(r, 0);
      path.lineTo(size.width - r, 0);
      path.quadraticBezierTo(size.width, 0, size.width, r);
      // Right side down to tail
      path.lineTo(size.width, size.height - r);
      // Tail on bottom right
      path.lineTo(size.width + tw, size.height);
      path.lineTo(size.width - r, size.height);
      path.lineTo(r, size.height);
      path.quadraticBezierTo(0, size.height, 0, size.height - r);
      path.lineTo(0, r);
      path.quadraticBezierTo(0, 0, r, 0);
    } else {
      // Draw receiver bubble
      path.moveTo(r, 0);
      path.lineTo(size.width - r, 0);
      path.quadraticBezierTo(size.width, 0, size.width, r);
      path.lineTo(size.width, size.height - r);
      path.quadraticBezierTo(size.width, size.height, size.width - r, size.height);
      path.lineTo(r, size.height);
      // Tail on bottom left
      path.lineTo(-tw, size.height);
      path.lineTo(0, size.height - r);
      path.lineTo(0, r);
      path.quadraticBezierTo(0, 0, r, 0);
    }

    path.close();

    // Draw shadow first
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.04)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Draw fill
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant BubbleBackgroundPainter oldDelegate) {
    return oldDelegate.isMe != isMe || oldDelegate.color != color;
  }
}

/// Renders a single message in the conversation list.
///
/// Voice-message playback state and transcript-expand state are controlled by
/// the parent via [isPlaying], [isTranscriptExpanded], and their matching
/// callbacks — keeping this widget stateless and simple to test.
class ChatMessageBubble extends StatelessWidget {
  final MessageData message;
  final bool isPlaying;
  final bool isTranscriptExpanded;
  final List<double> waveHeights;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleTranscript;
  final String Function(int timestamp) formatTime;
  final String? senderName;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isPlaying,
    required this.isTranscriptExpanded,
    required this.waveHeights,
    required this.onTogglePlay,
    required this.onToggleTranscript,
    required this.formatTime,
    this.senderName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = message.isMe;
    final isDark = theme.brightness == Brightness.dark;

    // ── System message ───────────────────────────────────────────────────────
    if (message.sender == 'System' || senderName == 'System') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            message.text,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      );
    }

    // Colors
    Color bubbleColor;
    if (message.isVault) {
      bubbleColor = isMe
          ? const Color(0xFFF59E0B)
          : (isDark ? const Color(0xFF2C1B0F) : const Color(0xFFFEF3C7));
    } else {
      bubbleColor = isMe
          ? theme.primaryColor
          : (isDark ? const Color(0xFF182533) : const Color(0xFFE2E8F0));
    }
    final textColor = isMe ? Colors.white : (isDark ? Colors.white : Colors.black87);

    // ── Time-locked message ──────────────────────────────────────────────────
    final bool isLocked = message.isTimeLocked &&
        message.unlocksAt != null &&
        DateTime.now().millisecondsSinceEpoch < message.unlocksAt!;

    if (isLocked) {
      final remainingMs = message.unlocksAt! - DateTime.now().millisecondsSinceEpoch;
      String lockedLabel = '';
      if (remainingMs > 0) {
        final totalSecs = (remainingMs / 1000).ceil();
        final mins = totalSecs ~/ 60;
        final secs = totalSecs % 60;
        lockedLabel = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
      }

      final lockedBody = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMe && senderName != null) ...[
              Text(
                senderName!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, size: 14, color: Colors.orange),
                const SizedBox(width: 6),
                Text(
                  'Time-Locked Message',
                  style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Decrypts in: $lockedLabel',
              style: TextStyle(
                color: textColor.withValues(alpha: 0.7),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );

      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            bottom: 6,
            left: isMe ? 40 : 16,
            right: isMe ? 16 : 40,
          ),
          child: CustomPaint(
            painter: BubbleBackgroundPainter(isMe: isMe, color: bubbleColor),
            child: lockedBody,
          ),
        ),
      );
    }

    // ── Voice message ────────────────────────────────────────────────────────
    if (message.isVoice) {
      final voiceBody = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMe && senderName != null) ...[
              Text(
                senderName!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    size: 32,
                    color: isMe ? Colors.white : theme.primaryColor,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onTogglePlay,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 24,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: waveHeights.map((h) {
                        return Container(
                          width: 2.5,
                          height: h,
                          decoration: BoxDecoration(
                            color: (isMe ? Colors.white : theme.primaryColor)
                                .withValues(alpha: isPlaying ? 0.9 : 0.4),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isPlaying
                      ? '0:01'
                      : '0:${message.voiceDuration?.toString().padLeft(2, '0') ?? '03'}',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: onToggleTranscript,
                  child: Row(
                    children: [
                      Icon(
                        isTranscriptExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: isMe
                            ? Colors.white70
                            : (isDark ? Colors.white70 : Colors.black54),
                      ),
                      Text(
                        'Transcribed Text Note',
                        style: TextStyle(
                          color: isMe
                              ? Colors.white70
                              : (isDark ? Colors.white70 : Colors.black54),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatTime(message.timestamp),
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.5),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            bottom: 6,
            left: isMe ? 40 : 16,
            right: isMe ? 16 : 40,
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              CustomPaint(
                painter: BubbleBackgroundPainter(isMe: isMe, color: bubbleColor),
                child: voiceBody,
              ),
              if (isTranscriptExpanded)
                Container(
                  margin: const EdgeInsets.only(top: 4, left: 4, right: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(
                    message.voiceTranscript ?? 'No transcript available.',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // ── Normal / Vault text message ──────────────────────────────────────────
    String displayText = message.text;
    double emojiSize = 15;
    bool isSizedEmoji = false;

    if (displayText.startsWith('[size:')) {
      final match = RegExp(r'^\[size:(\w+)\](.*)').firstMatch(displayText);
      if (match != null) {
        final sizeType = match.group(1);
        displayText = match.group(2) ?? '';
        isSizedEmoji = true;
        emojiSize = switch (sizeType) {
          'small'  => 16,
          'large'  => 48,
          'xlarge' => 72,
          _        => 30,
        };
      }
    }

    final bool isSingleEmoji = isSizedEmoji && displayText.trim().length <= 4;

    if (isSingleEmoji) {
      bubbleColor = Colors.transparent;
    }

    String? expiryLabel;
    if (message.expiresAt != null) {
      final remaining = message.expiresAt! - DateTime.now().millisecondsSinceEpoch;
      if (remaining > 0) {
        final secs = (remaining / 1000).ceil();
        expiryLabel = secs >= 60 ? '${(secs / 60).ceil()}m' : '${secs}s';
      }
    }

    final bubbleBody = Container(
      padding: isSingleEmoji
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isMe && senderName != null) ...[
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  senderName!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                  ),
                ),
              ),
            ),
          ],
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              displayText,
              style: TextStyle(
                color: isSingleEmoji ? Colors.white : textColor,
                fontSize: isSingleEmoji ? emojiSize : 15,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.isVault) ...[
                Icon(Icons.hourglass_empty_rounded,
                    size: 10, color: isMe ? Colors.white70 : Colors.amber),
                const SizedBox(width: 4),
              ],
              if (expiryLabel != null) ...[
                Icon(Icons.timer_outlined,
                    size: 10, color: isMe ? Colors.white60 : Colors.amber),
                const SizedBox(width: 2),
                Text(
                  expiryLabel,
                  style: TextStyle(
                    fontSize: 9,
                    color: isMe ? Colors.white60 : Colors.amber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                formatTime(message.timestamp),
                style: TextStyle(
                  color: isMe ? Colors.white60 : Colors.black45,
                  fontSize: 9,
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                Icon(
                  !message.isSent
                      ? Icons.schedule_rounded
                      : (message.isRead
                          ? Icons.done_all_rounded
                          : Icons.done_rounded),
                  size: 12,
                  color: Colors.white70,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 6,
          left: isMe ? 40 : 16,
          right: isMe ? 16 : 40,
        ),
        child: isSingleEmoji
            ? bubbleBody
            : CustomPaint(
                painter: BubbleBackgroundPainter(isMe: isMe, color: bubbleColor),
                child: bubbleBody,
              ),
      ),
    );
  }
}

/// Reaction pill row displayed below a message that has reactions.
class ReactionPill extends StatelessWidget {
  final MessageData message;
  final VoidCallback onTap;

  const ReactionPill({
    super.key,
    required this.message,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: message.reactions.entries.map((entry) {
          final meta = kReactions.firstWhere(
            (r) => r['key'] == entry.key,
            orElse: () => {'icon': Icons.circle, 'label': ''},
          );
          return GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.primaryColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(meta['icon'] as IconData, size: 13, color: theme.primaryColor),
                  if (entry.value > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${entry.value}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.primaryColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
