import 'dart:async';
import 'package:flutter/material.dart';

/// Bottom message-composition bar for [ChatScreen].
///
/// All interaction callbacks are injected by the parent so this widget stays
/// stateless and easy to test in isolation.
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isVaultMode;
  final bool isRecordingVoice;
  final int recordingDuration;
  final int? activeTimeLockDelayMs;
  final VoidCallback onSendPressed;
  final VoidCallback onLongPressSend;
  final VoidCallback onMicPressed;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.isVaultMode,
    required this.isRecordingVoice,
    required this.recordingDuration,
    required this.activeTimeLockDelayMs,
    required this.onSendPressed,
    required this.onLongPressSend,
    required this.onMicPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              isRecordingVoice ? Icons.mic_rounded : Icons.mic_none_rounded,
              color: isRecordingVoice ? Colors.redAccent : theme.primaryColor,
            ),
            onPressed: onMicPressed,
          ),
          Expanded(
            child: isRecordingVoice
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Recording... 0:${recordingDuration.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(child: RecordingWaveform()),
                      ],
                    ),
                  )
                : TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: isVaultMode
                          ? 'Type ephemeral message...'
                          : 'Type secure message...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      fillColor: Colors.transparent,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
          ),
          GestureDetector(
            onLongPress: isRecordingVoice ? null : onLongPressSend,
            child: IconButton(
              icon: Icon(
                activeTimeLockDelayMs != null
                    ? Icons.lock_clock_rounded
                    : Icons.send_rounded,
              ),
              color: activeTimeLockDelayMs != null
                  ? Colors.orange
                  : (isVaultMode ? const Color(0xFFF59E0B) : theme.primaryColor),
              onPressed: onSendPressed,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated waveform displayed while a voice note is being recorded.
class RecordingWaveform extends StatefulWidget {
  const RecordingWaveform({super.key});

  @override
  State<RecordingWaveform> createState() => _RecordingWaveformState();
}

class _RecordingWaveformState extends State<RecordingWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _heights = List.generate(25, (i) => 4.0 + (i % 5) * 4.0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat(reverse: true);

    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (mounted) {
        setState(() {
          for (int i = 0; i < _heights.length; i++) {
            _heights[i] = 4.0 + (16.0 * (0.2 + 0.8 * (i % 3 == 0 ? 0.8 : 0.4)));
            _heights[i] += (DateTime.now().millisecond % 10);
            _heights[i] = _heights[i].clamp(4.0, 36.0);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _heights.map((h) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 3,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        }).toList(),
      ),
    );
  }
}
