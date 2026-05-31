import 'package:flutter/material.dart';
import '../../../../services/p2p_mesh_service.dart';

class P2PChatScreen extends StatefulWidget {
  final P2PPeer peer;

  const P2PChatScreen({super.key, required this.peer});

  @override
  State<P2PChatScreen> createState() => _P2PChatScreenState();
}

class _P2PChatScreenState extends State<P2PChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    final success = await P2PMeshService().sendP2PMessage(widget.peer, text);

    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to deliver message. Peer connection lost.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    } else {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: theme.cardColor,
        leadingWidth: 70,
        leading: InkWell(
          onTap: () => Navigator.of(context).pop(),
          borderRadius: BorderRadius.circular(30),
          child: Row(
            children: [
              const SizedBox(width: 4),
              const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              const SizedBox(width: 4),
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                child: Text(
                  widget.peer.username[0].toUpperCase(),
                  style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.peer.username,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Local: ${widget.peer.ipAddress} • Zero-Data Mesh',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear History',
            onPressed: () {
              P2PMeshService().clearHistory();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Mesh Security Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: const Color(0xFF10B981).withValues(alpha: 0.06),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.radar_rounded, size: 14, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Text(
                    'Direct Peer connection active. No server routing involved.',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            // Message Stream
            Expanded(
              child: StreamBuilder<List<P2PMessage>>(
                stream: P2PMeshService().getPeerMessagesStream(widget.peer.username),
                initialData: P2PMeshService().getPeerMessageHistory(widget.peer.username),
                builder: (context, snapshot) {
                  final messages = snapshot.data ?? [];
                  if (messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_tethering_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          const Text(
                            'Local Chat Established',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Send a direct message over the local network.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }

                  // Auto scroll to bottom
                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return _buildMessageBubble(msg, theme);
                    },
                  );
                },
              ),
            ),

            // Input Row
            _buildInputBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(P2PMessage message, ThemeData theme) {
    final isMe = message.isMe;

    final bubbleColor = isMe
        ? const Color(0xFF10B981) // Emerald for P2P
        : (theme.brightness == Brightness.dark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0));

    final textColor = isMe
        ? Colors.white
        : (theme.brightness == Brightness.dark ? Colors.white : Colors.black87);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.text,
              style: TextStyle(color: textColor, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 4),
            Text(
              '${message.time.hour}:${message.time.minute.toString().padLeft(2, "0")}',
              style: TextStyle(
                color: isMe ? Colors.white60 : Colors.black45,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type message over offline mesh...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
              onSubmitted: (_) => _handleSendMessage(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded),
            color: const Color(0xFF10B981),
            onPressed: _handleSendMessage,
          ),
        ],
      ),
    );
  }
}
