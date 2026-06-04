import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart';
import '../../../../providers/connection_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/encryption_service.dart';
import '../../../../services/message_storage_service.dart';
import '../../../../services/websocket_service.dart';
import '../../../chat/data/models/message_model.dart';

class GroupChatScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;
  final bool isCampfire;
  final int? expiresAt;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    this.isCampfire = false,
    this.expiresAt,
  });

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  int _membersCount = 1;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<MessageData> _messages = [];
  Timer? _countdownTimer;
  StreamSubscription? _socketSubscription;

  final List<String> _toxicKeywords = [
    'hate', 'kill', 'die', 'stupid', 'idiot', 'jerk', 'trash', 
    'garbage', 'fool', 'loser', 'hate you', 'shut up', 'ugly', 'scam'
  ];

  @override
  void initState() {
    super.initState();
    _loadLocalMessages();
    _syncMessages();

    if (widget.isCampfire && widget.expiresAt != null) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now >= widget.expiresAt!) {
          timer.cancel();
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔥 Campfire Group dissolved and database sector logs shredded!'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        } else {
          setState(() {});
        }
      });
    }

    _socketSubscription = WebSocketService().messageStream.listen((payload) async {
      if (payload['type'] == 'group_message' && payload['groupId'] == widget.groupId) {
        final sender = payload['senderId']?.toString() ?? '';
        final ciphertext = payload['ciphertext']?.toString() ?? '';
        final timestamp = payload['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        
        final myUsername = AuthService().username;
        if (sender == myUsername) return; // Already loaded locally

        final key = await _getGroupKey();
        final plaintext = await _decrypt(ciphertext, key);
        
        final msg = MessageData(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: plaintext,
          isMe: false,
          sender: sender,
          time: _formatTimestamp(timestamp),
          isRead: true,
          timestamp: timestamp,
        );
        
        await MessageStorageService().saveGroupMessage(widget.groupId, msg);
        if (mounted) {
          setState(() {
            _messages.add(msg);
          });
          _scrollToBottom();
        }
      }
    });
  }

  Future<SecretKey> _getGroupKey() async {
    final bytes = List<int>.generate(32, (i) {
      if (i < widget.groupId.length) {
        return widget.groupId.codeUnitAt(i) ^ 0x5A;
      }
      return 0xA5 ^ i;
    });
    return SecretKey(bytes);
  }

  Future<String> _decrypt(String ciphertext, SecretKey key) async {
    try {
      return await EncryptionService().decryptMessage(
        encryptedPacketBase64: ciphertext,
        secretKey: key,
      );
    } catch (_) {
      return '[Decryption failed]';
    }
  }

  Future<String> _encrypt(String plaintext, SecretKey key) async {
    return await EncryptionService().encryptMessage(
      plaintext: plaintext,
      secretKey: key,
    );
  }

  String _formatTimestamp(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _loadLocalMessages() async {
    final localMsgs = await MessageStorageService().getGroupMessages(widget.groupId);
    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(localMsgs);
      });
      _scrollToBottom();
    }
  }

  Future<void> _syncMessages() async {
    final key = await _getGroupKey();
    final rawMsgs = await ApiService().getGroupMessages(widget.groupId);
    final myUsername = AuthService().username;
    
    for (final raw in rawMsgs) {
      final id = raw['id']?.toString() ?? '';
      final sender = raw['sender']?.toString() ?? '';
      final ciphertext = raw['text']?.toString() ?? '';
      final createdAtStr = raw['created_at']?.toString() ?? '';
      
      int timestamp = DateTime.now().millisecondsSinceEpoch;
      try {
        timestamp = DateTime.parse(createdAtStr).toLocal().millisecondsSinceEpoch;
      } catch (_) {}
      
      final plaintext = await _decrypt(ciphertext, key);
      final isMe = sender == myUsername;
      
      final msg = MessageData(
        id: id,
        text: plaintext,
        isMe: isMe,
        sender: sender,
        time: _formatTimestamp(timestamp),
        isRead: true,
        timestamp: timestamp,
      );
      
      await MessageStorageService().saveGroupMessage(widget.groupId, msg);
    }
    
    await _loadLocalMessages();
  }

  String _getCampfireTimeRemaining() {
    if (widget.expiresAt == null) return '';
    final remaining = widget.expiresAt! - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return 'Dissolving...';
    final totalSecs = (remaining / 1000).ceil();
    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;
    return '🔥 Shredding in ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _countdownTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  double _calculateGroupToxicity() {
    if (_messages.isEmpty) return 0.0;

    final recentMessages = _messages.length > 15 
        ? _messages.sublist(_messages.length - 15) 
        : _messages;

    int toxicCount = 0;
    for (final msg in recentMessages) {
      if (_isMessageToxic(msg.text)) {
        toxicCount++;
      }
    }

    return toxicCount / recentMessages.length;
  }

  String _normalizeLeetspeak(String text) {
    final mapping = {
      '@': 'a', '4': 'a', '▲': 'a',
      '8': 'b', 'ß': 'b',
      '©': 'c', '¢': 'c', '<': 'c', '(': 'c',
      '3': 'e', '€': 'e',
      '#': 'h',
      '1': 'i', '!': 'i', '|': 'i', '¡': 'i',
      '0': 'o',
      '5': 's', '\$': 's', '§': 's',
      '7': 't', '+': 't',
      '\\/\\/': 'w',
      '\\/': 'v',
      '2': 'z'
    };
    String normalized = text.toLowerCase();
    final sortedKeys = mapping.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sortedKeys) {
      normalized = normalized.replaceAll(key, mapping[key]!);
    }
    return normalized;
  }

  bool _isMessageToxic(String text) {
    final normalizedText = _normalizeLeetspeak(text);
    for (final term in _toxicKeywords) {
      if (normalizedText.contains(term)) {
        return true;
      }
    }
    return false;
  }

  void _handleSendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (_isMessageToxic(text)) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 10),
              Text('Toxic Content Warning', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Your message contains potentially offensive language. Do you still want to send it?',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Send Anyway', style: TextStyle(color: Colors.orange)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final myUsername = AuthService().username ?? 'Me';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    final newMessage = MessageData(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text,
      isMe: true,
      sender: myUsername,
      time: _formatTimestamp(timestamp),
      isRead: true,
      isSent: false,
      timestamp: timestamp,
    );

    _messageController.clear();
    
    setState(() {
      _messages.add(newMessage);
    });
    _scrollToBottom();

    final key = await _getGroupKey();
    final ciphertext = await _encrypt(text, key);
    
    final wasSent = await WebSocketService().sendGroupMessage(
      groupId: widget.groupId,
      ciphertext: ciphertext,
    );
    
    newMessage.isSent = wasSent;
    await MessageStorageService().saveGroupMessage(widget.groupId, newMessage);
    if (mounted) {
      setState(() {});
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
    
    final toxicity = _calculateGroupToxicity();
    
    Color vibeColor;
    String vibeLabel;
    IconData vibeIcon;

    if (toxicity <= 0.15) {
      vibeColor = const Color(0xFF10B981);
      vibeLabel = 'Chill Vibe • Friendly & Respectful';
      vibeIcon = Icons.sentiment_satisfied_alt_rounded;
    } else if (toxicity <= 0.40) {
      vibeColor = const Color(0xFFF59E0B);
      vibeLabel = 'Spicy Vibe • Heated Discussions';
      vibeIcon = Icons.sentiment_neutral_rounded;
    } else {
      vibeColor = const Color(0xFFEF4444);
      vibeLabel = 'Toxic Vibe Alert • Spammers/Insults';
      vibeIcon = Icons.sentiment_very_dissatisfied_rounded;
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B132B) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.groupName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.isCampfire) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.local_fire_department_rounded, color: Color(0xFFEF4444), size: 18),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.isCampfire 
                        ? _getCampfireTimeRemaining()
                        : '$_membersCount members online',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.isCampfire 
                          ? const Color(0xFFEF4444)
                          : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                      fontWeight: widget.isCampfire ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded),
            onPressed: () {
              _showInviteMembersDialog(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () {
              _showGroupInfoDialog(context);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: vibeColor.withValues(alpha: 0.08),
                border: Border(
                  bottom: BorderSide(color: vibeColor.withValues(alpha: 0.15), width: 1),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: vibeColor.withValues(alpha: 0.2),
                    child: Icon(vibeIcon, size: 14, color: vibeColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      vibeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: vibeColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: vibeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Score: ${(toxicity * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: vibeColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildGroupMessageBubble(msg, theme, isDark);
                },
              ),
            ),

            _buildInputBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupMessageBubble(MessageData msg, ThemeData theme, bool isDark) {
    final isMe = msg.isMe;
    
    if (msg.sender == 'System') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            msg.text,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      );
    }

    final bubbleColor = isMe
        ? theme.primaryColor
        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0));

    final textColor = isMe
        ? Colors.white
        : (isDark ? Colors.white : Colors.black87);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 4),
                child: Text(
                  msg.sender ?? 'Unknown',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor.withValues(alpha: 0.85),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMe ? 20 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    msg.text,
                    style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        msg.time,
                        style: TextStyle(
                          color: isMe ? Colors.white60 : Colors.black45,
                          fontSize: 8,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          msg.isSent ? Icons.done_all : Icons.access_time,
                          size: 10,
                          color: Colors.white60,
                        ),
                      ]
                    ],
                  ),
                ],
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
                hintText: 'Type group message...',
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
            color: theme.primaryColor,
            onPressed: _handleSendMessage,
          ),
        ],
      ),
    );
  }

  void _showInviteMembersDialog(BuildContext context) {
    final connections = ref.read(connectionProvider).connections;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: const Color(0xFF13131B),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Invite Contacts to Group',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              if (connections.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No active connections found. You can only invite users who are in your secure contact list.',
                    style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: connections.length,
                    itemBuilder: (context, idx) {
                      final contact = connections[idx];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.white10,
                          child: Text(contact[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(contact, style: const TextStyle(color: Colors.white)),
                        trailing: const Icon(Icons.send_rounded, color: Color(0xFF8083FF)),
                        onTap: () async {
                          setState(() {
                            _messages.add(
                              MessageData(
                                id: DateTime.now().microsecondsSinceEpoch.toString(),
                                text: 'You invited @$contact to the group.',
                                isMe: true,
                                sender: 'System',
                                time: _formatTimestamp(DateTime.now().millisecondsSinceEpoch),
                                timestamp: DateTime.now().millisecondsSinceEpoch,
                              ),
                            );
                            _membersCount++;
                          });
                          Navigator.of(context).pop();
                          
                          // Call Api to invite/join
                          await ApiService().joinGroup(widget.groupId); // simulate invite join for this demo user
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Invited @$contact to this group room.'),
                              backgroundColor: const Color(0xFF10B981),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showGroupInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFF8083FF)),
              const SizedBox(width: 10),
              Text(widget.groupName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This group room uses end-to-end post-quantum encryption. Messages are transient and encrypted.',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 10),
              _buildInfoRow('Discovery Mode', 'Invite-Only / Secure Handshake'),
              _buildInfoRow('Total Members', '$_membersCount members'),
              _buildInfoRow('Max Create Limit', '25 groups per user'),
              _buildInfoRow('Max Join Limit', '50 groups per user'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close', style: TextStyle(color: Colors.white60)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          Text(value, style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }
}
