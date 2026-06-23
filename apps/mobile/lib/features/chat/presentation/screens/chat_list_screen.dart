import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../services/message_storage_service.dart';
import '../../data/models/message_model.dart';
import '../../../../services/websocket_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'chat_screen.dart';
import '../../../../providers/connection_provider.dart';
import '../../../../providers/layout_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../core/widgets/beautiful_avatar.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const ChatListScreen({super.key, this.isEmbedded = false});

  @override
  ConsumerState<ChatListScreen> createState() => ChatListScreenState();
}

class ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  void setSearchQuery(String query) {
    if (mounted) {
      setState(() {
        _searchQuery = query.toLowerCase().trim();
      });
    }
  }

  Future<void> scanQRCode() async {
    final granted = await _requestCameraPermission(context);
    if (granted && mounted) {
      _showQRScannerDialog(context);
    }
  }


  final List<ChatListItemData> _chats = [];
  Set<String> _pinnedChats = {};
  Set<String> _mutedChats = {};
  Set<String> _blockedChats = {};
  StreamSubscription? _socketSubscription;

  void _loadPreferences() {
    final box = Hive.box('settings');
    final pinned = (box.get('pinned_chats', defaultValue: <String>[]) as List).cast<String>();
    final muted = (box.get('muted_chats', defaultValue: <String>[]) as List).cast<String>();
    final blocked = (box.get('blocked_chats', defaultValue: <String>[]) as List).cast<String>();
    if (mounted) {
      setState(() {
        _pinnedChats = pinned.toSet();
        _mutedChats = muted.toSet();
        _blockedChats = blocked.toSet();
      });
    }
  }

  Future<void> _savePreferences() async {
    final box = Hive.box('settings');
    await box.put('pinned_chats', _pinnedChats.toList());
    await box.put('muted_chats', _mutedChats.toList());
    await box.put('blocked_chats', _blockedChats.toList());
  }

  void _togglePin(String username) {
    setState(() {
      if (_pinnedChats.contains(username)) {
        _pinnedChats.remove(username);
      } else {
        _pinnedChats.add(username);
      }
    });
    _savePreferences();
  }

  void _toggleMute(String username) {
    setState(() {
      if (_mutedChats.contains(username)) {
        _mutedChats.remove(username);
      } else {
        _mutedChats.add(username);
      }
    });
    _savePreferences();
  }

  Future<void> _blockContact(String username) async {
    setState(() {
      _blockedChats.add(username);
      _pinnedChats.remove(username);
      _chats.removeWhere((c) => c.username == username);
    });
    await _savePreferences();
  }

  Future<void> _deleteChat(String username) async {
    final boxName = 'messages_$username';
    if (Hive.isBoxOpen(boxName)) {
      await Hive.box(boxName).clear();
    } else {
      try {
        final box = await Hive.openBox(boxName);
        await box.clear();
      } catch (_) {}
    }
    setState(() {
      _chats.removeWhere((c) => c.username == username);
    });
  }

  Future<void> _markAsRead(String username) async {
    final storage = MessageStorageService();
    final messages = await storage.getMessages(username);
    for (final msg in messages) {
      if (!msg.isMe && !msg.isRead) {
        await storage.saveMessage(
          username,
          MessageData(
            id: msg.id,
            text: msg.text,
            isMe: msg.isMe,
            time: msg.time,
            timestamp: msg.timestamp,
            isSent: msg.isSent,
            isRead: true,
            isVault: msg.isVault,
            isVoice: msg.isVoice,
            voiceDuration: msg.voiceDuration,
            voiceTranscript: msg.voiceTranscript,
            reactions: msg.reactions,
            expiresAt: msg.expiresAt,
            isTimeLocked: msg.isTimeLocked,
            unlocksAt: msg.unlocksAt,
          ),
        );
      }
    }
    _loadChats();
  }

  void _showChatOptions(BuildContext context, ChatListItemData chat) {
    final theme = Theme.of(context);
    final isPinned = _pinnedChats.contains(chat.username);
    final isMuted = _mutedChats.contains(chat.username);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      BeautifulAvatar(name: chat.name, username: chat.username, radius: 20),
                      const SizedBox(width: 12),
                      Text(
                        chat.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
                _OptionTile(
                  icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                  label: isPinned ? 'Unpin Chat' : 'Pin to Top',
                  color: theme.primaryColor,
                  onTap: () {
                    Navigator.of(context).pop();
                    _togglePin(chat.username);
                  },
                ),
                _OptionTile(
                  icon: isMuted ? Icons.notifications_rounded : Icons.notifications_off_rounded,
                  label: isMuted ? 'Unmute Notifications' : 'Mute Notifications',
                  color: Colors.amber,
                  onTap: () {
                    Navigator.of(context).pop();
                    _toggleMute(chat.username);
                  },
                ),
                _OptionTile(
                  icon: Icons.done_all_rounded,
                  label: 'Mark as Read',
                  color: const Color(0xFF10B981),
                  onTap: () {
                    Navigator.of(context).pop();
                    _markAsRead(chat.username);
                  },
                ),
                _OptionTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete Chat',
                  color: Colors.redAccent,
                  onTap: () {
                    Navigator.of(context).pop();
                    _confirmDeleteChat(context, chat);
                  },
                ),
                _OptionTile(
                  icon: Icons.block_rounded,
                  label: 'Block Contact',
                  color: Colors.red,
                  onTap: () {
                    Navigator.of(context).pop();
                    _confirmBlockContact(context, chat);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteChat(BuildContext context, ChatListItemData chat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF13131B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white10),
        ),
        title: const Text('Delete Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Delete all messages with ${chat.name}? This cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.of(context).pop();
              _deleteChat(chat.username);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmBlockContact(BuildContext context, ChatListItemData chat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF13131B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white10),
        ),
        title: const Text('Block Contact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Block ${chat.name}? They will be removed from your contacts and you will no longer receive messages from them.',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(context).pop();
              _blockContact(chat.username);
            },
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  // Returns a color based on recency of last message (relationship health ring).
  Color _getRelationshipHealthColor(String username) {
    final boxName = 'messages_$username';
    if (!Hive.isBoxOpen(boxName)) return const Color(0xFFF59E0B);
    final box = Hive.box(boxName);
    if (box.isEmpty) return const Color(0xFFF59E0B);

    int latestTimestamp = 0;
    for (final val in box.values) {
      if (val != null) {
        try {
          final data = jsonDecode(val.toString()) as Map<String, dynamic>;
          final ts = data['timestamp'] as int? ?? 0;
          if (ts > latestTimestamp) latestTimestamp = ts;
        } catch (_) {}
      }
    }

    if (latestTimestamp == 0) return const Color(0xFFF59E0B);

    final diffMs = DateTime.now().millisecondsSinceEpoch - latestTimestamp;
    const oneDayMs = 24 * 60 * 60 * 1000;
    const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;

    if (diffMs < oneDayMs) return const Color(0xFF10B981);
    if (diffMs < sevenDaysMs) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  bool _hasMatchingMessages(String username, String query) {
    if (query.isEmpty) return true;
    try {
      final boxName = 'messages_$username';
      if (!Hive.isBoxOpen(boxName)) return false;
      final box = Hive.box(boxName);
      for (final val in box.values) {
        if (val != null) {
          final data = jsonDecode(val.toString()) as Map<String, dynamic>;
          final text = (data['text'] as String? ?? '').toLowerCase();
          if (text.contains(query)) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _loadChats() async {
    if (!mounted) return;
    final connectionState = ref.read(connectionProvider);
    final acceptedConnections = connectionState.connections
        .where((u) => !_blockedChats.contains(u))
        .toList();

    final List<ChatListItemData> loadedChats = [];
    for (final username in acceptedConnections) {
      final messages = await MessageStorageService().getMessages(username);
      final lastMsg = messages.isNotEmpty
          ? messages.last.text
          : 'Tap to start conversation.';
      final lastMsgTime =
          messages.isNotEmpty ? messages.last.time : '';
      final unreadCount =
          messages.where((m) => !m.isMe && !m.isRead).length;

      loadedChats.add(ChatListItemData(
        name: username.substring(0, 1).toUpperCase() +
            username.substring(1),
        username: username,
        lastMessage: lastMsg,
        time: lastMsgTime,
        unreadCount: unreadCount,
        isOnline: true,
      ));
    }

    bool hasChanged = _chats.length != loadedChats.length;
    if (!hasChanged) {
      for (int i = 0; i < _chats.length; i++) {
        if (_chats[i].username != loadedChats[i].username ||
            _chats[i].lastMessage != loadedChats[i].lastMessage ||
            _chats[i].unreadCount != loadedChats[i].unreadCount) {
          hasChanged = true;
          break;
        }
      }
    }

    loadedChats.sort((a, b) {
      final aPinned = _pinnedChats.contains(a.username) ? 0 : 1;
      final bPinned = _pinnedChats.contains(b.username) ? 0 : 1;
      return aPinned.compareTo(bPinned);
    });

    if (hasChanged && mounted) {
      setState(() {
        _chats.clear();
        _chats.addAll(loadedChats);
      });
    }
  }

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      setState(() =>
          _searchQuery = _searchController.text.toLowerCase().trim());
    });

    _loadPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChats();
    });

    _socketSubscription =
        WebSocketService().messageStream.listen((event) {
      if (event['type'] == 'message') {
        _loadChats();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _socketSubscription?.cancel();
    super.dispose();
  }

  Widget _buildMainBody(
      BuildContext context,
      ThemeData theme,
      Color textColor,
      Color subColor,
      double verticalMargin,
      double verticalPadding) {
    return Column(
      children: [
          // Pending Incoming Connection Requests
          Consumer(
            builder: (context, ref, child) {
              final connState = ref.watch(connectionProvider);
              final pendingIncoming = connState.invitations
                  .where((i) =>
                      i.type == 'incoming' && i.status == 'pending')
                  .toList();

              if (pendingIncoming.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_add_rounded,
                                  color: Color(0xFF818CF8), size: 12),
                              const SizedBox(width: 5),
                              Text(
                                '${pendingIncoming.length} new request${pendingIncoming.length > 1 ? 's' : ''}',
                                style: const TextStyle(
                                  color: Color(0xFF818CF8),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...pendingIncoming.map((req) => Container(
                        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF1E1B4B)
                                  .withValues(alpha: 0.85),
                              const Color(0xFF13131B),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.22),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.07),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF6366F1),
                                    Color(0xFF8B5CF6),
                                  ],
                                ),
                              ),
                              child: BeautifulAvatar(
                                name: req.username,
                                username: req.username,
                                radius: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '@${req.username}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Wants to connect with you',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () => ref
                                  .read(connectionProvider.notifier)
                                  .rejectInvitation(req.username),
                              child: Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: Colors.white
                                      .withValues(alpha: 0.06),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.white12),
                                ),
                                child: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white54,
                                    size: 17),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                ref
                                    .read(connectionProvider.notifier)
                                    .acceptInvitation(req.username);
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(
                                      'Connected with @${req.username}!'),
                                  backgroundColor:
                                      const Color(0xFF10B981),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ));
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 9),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF10B981),
                                      Color(0xFF059669),
                                    ],
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'Accept',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),

          // Chat list
          Expanded(
            child: Builder(builder: (context) {
              final filtered = _searchQuery.isEmpty
                  ? _chats
                  : _chats.where((c) {
                      return c.name
                              .toLowerCase()
                              .contains(_searchQuery) ||
                          c.lastMessage
                              .toLowerCase()
                              .contains(_searchQuery) ||
                          c.username
                              .toLowerCase()
                              .contains(_searchQuery) ||
                          _hasMatchingMessages(
                              c.username, _searchQuery);
                    }).toList();

              if (filtered.isEmpty) {
                if (_searchQuery.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48,
                            color: theme.textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(
                          'No chats match "$_searchQuery"',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Center(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 48.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.08),
                            border: Border.all(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 40,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'No conversations yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE4E1ED),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            'Add a contact by username or QR code to '
                            'start a Signal-encrypted conversation.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFFC7C4D7),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.only(
                    top: 8.0, bottom: 100.0),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final chat = filtered[index];
                  return Container(
                    margin: EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: verticalMargin),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.015),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            Colors.white.withValues(alpha: 0.04),
                        width: 1.0,
                      ),
                    ),
                    child: ListTile(
                      onLongPress: () => _showChatOptions(context, chat),
                      onTap: () {
                        if (MediaQuery.of(context).size.width >
                            900) {
                          ref
                              .read(selectedGroupProvider.notifier)
                              .state = null;
                          ref
                              .read(selectedChatProvider.notifier)
                              .state = chat;
                        } else {
                          Navigator.of(context)
                              .push(MaterialPageRoute(
                                builder: (context) =>
                                    ChatScreen(chatData: chat),
                              ))
                              .then((_) => _loadChats());
                        }
                      },
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: verticalPadding),
                      leading: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _getRelationshipHealthColor(
                                    chat.username),
                                width: 2.0,
                              ),
                            ),
                            child: BeautifulAvatar(
                              name: chat.name,
                              username: chat.username,
                              radius: 23,
                            ),
                          ),
                          if (chat.isOnline)
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Container(
                                width: 13,
                                height: 13,
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: const Color(
                                          0xFF13131B),
                                      width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                              0xFF10B981)
                                          .withValues(alpha: 0.4),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        chat.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: textColor,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          chat.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: chat.unreadCount > 0
                                ? textColor
                                : subColor.withValues(alpha: 0.6),
                            fontWeight: chat.unreadCount > 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_pinnedChats.contains(chat.username))
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.push_pin_rounded, size: 12, color: Colors.white38),
                                ),
                              if (_mutedChats.contains(chat.username))
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.notifications_off_rounded, size: 12, color: Colors.white38),
                                ),
                              Text(
                                chat.time,
                                style: TextStyle(
                                  color: subColor.withValues(alpha: 0.4),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (chat.unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: theme.primaryColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.primaryColor.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Text(
                                '${chat.unreadCount}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(connectionProvider, (previous, next) {
      _loadChats();
    });

    final theme = Theme.of(context);
    final densityBox = Hive.box('settings');
    final int density =
        densityBox.get('chat_tile_density', defaultValue: 5) as int;
    final double verticalMargin =
        (6.0 - (density - 5) * 1.0).clamp(2.0, 8.0);
    final double verticalPadding =
        (8.0 - (density - 5) * 2.0).clamp(0.0, 12.0);

    final textColor =
        theme.textTheme.bodyLarge?.color ?? const Color(0xFFE4E1ED);
    final subColor =
        theme.textTheme.bodyMedium?.color ?? const Color(0xFFC7C4D7);

    final mainBody = _buildMainBody(
        context, theme, textColor, subColor, verticalMargin, verticalPadding);

    if (widget.isEmbedded) {
      return mainBody;
    }

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: textColor, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search chats or @username...',
                  hintStyle: TextStyle(
                      color: subColor.withValues(alpha: 0.5)),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                  prefixIcon: Icon(Icons.search_rounded,
                      color: subColor.withValues(alpha: 0.6)),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: subColor.withValues(alpha: 0.6)),
                    onPressed: () {
                      setState(() {
                        _isSearching = false;
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    },
                  ),
                ),
              )
            : Row(
                children: [
                  Text('Chatly',
                      style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF13131B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: const BorderSide(
                                color: Colors.white10),
                          ),
                          title: const Text('End-to-End Encrypted',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          content: const Text(
                            'All messages are protected by Signal Protocol '
                            '(Double Ratchet + X3DH). Only you and your '
                            'contacts can read them — the server never sees '
                            'plaintext.',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.45),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: 0.3),
                            width: 1.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shield_rounded,
                              size: 10,
                              color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Text(
                            'E2EE',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.9),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
        centerTitle: false,
        actions: [
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded),
              onPressed: () async {
                final granted =
                    await _requestCameraPermission(context);
                if (granted && context.mounted) {
                  _showQRScannerDialog(context);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () {
                setState(() => _isSearching = true);
              },
            ),
          ],
        ],
      ),
      body: mainBody,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: FloatingActionButton.extended(
          onPressed: () => showAddContactSheet(context),
          backgroundColor: theme.primaryColor,
          elevation: 4,
          icon: const Icon(Icons.person_add_rounded,
              color: Colors.white, size: 20),
          label: const Text(
            'Add Contact',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _requestCameraPermission(
      BuildContext context) async {
    final box = Hive.box('settings');
    final alreadyGranted =
        box.get('camera_permission_granted', defaultValue: false)
            as bool;
    if (alreadyGranted) return true;

    final completer = Completer<bool>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: Row(
            children: [
              Icon(Icons.camera_alt_rounded,
                  color: theme.primaryColor),
              const SizedBox(width: 12),
              const Text('Camera Permission',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
          content: const Text(
            'Chatly requires camera access to scan E2EE pairing QR codes.',
            style: TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                completer.complete(false);
              },
              child: const Text('Deny',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                await box.put('camera_permission_granted', true);
                if (context.mounted) Navigator.of(context).pop();
                completer.complete(true);
              },
              child: const Text('Allow'),
            ),
          ],
        );
      },
    );
    return completer.future;
  }

  void _showQRScannerDialog(BuildContext context) {
    final usernameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return StatefulBuilder(
          builder: (context, setState) {
            bool isScanning = true;
            String? scanResult;
            List<Map<String, dynamic>> searchResults = [];
            bool isSearchingUsers = false;

            void simulateScan(String text) async {
              setState(() {
                isScanning = false;
                scanResult = text;
              });
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF13131B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Colors.white10),
              ),
              title: const Text('QR Contact Add',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isScanning) ...[
                      _QRScannerWidget(onScan: simulateScan),
                      const SizedBox(height: 12),
                      const Text(
                        'Align QR code inside the viewfinder.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            height: 1.4),
                      ),
                    ] else ...[
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF10B981), size: 48),
                      const SizedBox(height: 12),
                      Text('Scanned!',
                          style: TextStyle(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      const SizedBox(height: 8),
                      Text(
                        scanResult ?? '',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFamily: 'monospace'),
                      ),
                    ],
                    const Divider(height: 32, color: Colors.white10),
                    TextField(
                      controller: usernameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Search or enter username...',
                        hintStyle:
                            TextStyle(color: Colors.white30),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        suffixIcon: Icon(Icons.search,
                            color: Colors.white30, size: 20),
                      ),
                      onChanged: (val) async {
                        final q = val
                            .trim()
                            .replaceAll('@', '');
                        if (q.length >= 2) {
                          setState(
                              () => isSearchingUsers = true);
                          final results =
                              await ApiService().searchUsers(q);
                          setState(() {
                            searchResults = results;
                            isSearchingUsers = false;
                          });
                        } else {
                          setState(() => searchResults = []);
                        }
                      },
                    ),
                    if (isSearchingUsers)
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(vertical: 8.0),
                        child: Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2)),
                      ),
                    if (searchResults.isNotEmpty)
                      Container(
                        constraints:
                            const BoxConstraints(maxHeight: 120),
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color:
                              Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.white10),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: searchResults.length,
                          itemBuilder: (context, idx) {
                            final user = searchResults[idx];
                            final uName =
                                user['username'] ?? '';
                            return ListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 2),
                              leading: BeautifulAvatar(
                                name: uName,
                                username: uName,
                                radius: 14,
                              ),
                              title: Text('@$uName',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight:
                                          FontWeight.bold)),
                              onTap: () {
                                usernameController.text = uName;
                                setState(
                                    () => searchResults = []);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel',
                      style:
                          TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final username = usernameController.text
                        .trim()
                        .replaceAll('@', '');
                    final target = username.isNotEmpty
                        ? username
                        : scanResult?.split('@').last;
                    if (target != null) {
                      final nav = Navigator.of(context);
                      final messenger =
                          ScaffoldMessenger.of(context);

                      messenger.showSnackBar(const SnackBar(
                        content: Text(
                            'Verifying username...'),
                        duration: Duration(seconds: 1),
                      ));

                      final results = await ApiService()
                          .searchUsers(target);
                      final userExists = results.any((u) =>
                          u['username']
                              .toString()
                              .toLowerCase() ==
                          target.toLowerCase());

                      if (!userExists) {
                        messenger.showSnackBar(SnackBar(
                          content: Text(
                              'User @$target not found.'),
                          backgroundColor:
                              const Color(0xFFEF4444),
                        ));
                        return;
                      }

                      nav.pop();
                      final done = await ref
                          .read(connectionProvider.notifier)
                          .sendInvitation(target);
                      if (done) {
                        messenger.showSnackBar(SnackBar(
                          content: Text(
                              'Invitation sent to @$target!'),
                          backgroundColor:
                              const Color(0xFF10B981),
                        ));
                      }
                    }
                  },
                  child: const Text('Connect'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => usernameController.dispose());
  }

  void showAddContactSheet(BuildContext context) {
    final controller = TextEditingController();
    final primaryColor = Theme.of(context).primaryColor;

    List<Map<String, dynamic>> results = [];
    bool searching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(builder: (_, setState) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF13131B),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Add Contact',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Search by username to send a secure connection request.',
                    style:
                        TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: '@username',
                        hintStyle: TextStyle(color: Colors.white38),
                        prefixIcon: Icon(
                            Icons.alternate_email_rounded,
                            color: Colors.white38,
                            size: 18),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      onChanged: (val) async {
                        final q = val.trim().replaceAll('@', '');
                        if (q.length >= 2) {
                          setState(() => searching = true);
                          final r = await ApiService().searchUsers(q);
                          setState(() {
                            results = r;
                            searching = false;
                          });
                        } else {
                          setState(() => results = []);
                        }
                      },
                    ),
                  ),
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2)),
                    ),
                  if (results.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      constraints:
                          const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                            vertical: 6),
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, color: Colors.white10),
                        itemBuilder: (context, idx) {
                          final user = results[idx];
                          final uName = user['username'] ?? '';
                          final bio = user['bio']?.toString() ?? '';
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                            leading: BeautifulAvatar(
                                name: uName,
                                username: uName,
                                radius: 18),
                            title: Text('@$uName',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                            subtitle: bio.isNotEmpty
                                ? Text(bio,
                                    style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)
                                : null,
                            onTap: () {
                              controller.text = uName;
                              setState(() => results = []);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.of(sheetContext).pop();
                            final granted =
                                await _requestCameraPermission(
                                    context);
                            if (granted && context.mounted) {
                              _showQRScannerDialog(context);
                            }
                          },
                          icon: const Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 16),
                          label: const Text('Scan QR'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(
                                color: Colors.white24),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final username = controller.text
                                .trim()
                                .replaceAll('@', '');
                            if (username.isEmpty) return;

                            final nav = Navigator.of(sheetContext);
                            final messenger =
                                ScaffoldMessenger.of(context);

                            final found = await ApiService()
                                .searchUsers(username);
                            final exists = found.any((u) =>
                                u['username']
                                    .toString()
                                    .toLowerCase() ==
                                username.toLowerCase());

                            if (!exists) {
                              messenger.showSnackBar(SnackBar(
                                content: Text(
                                    'User @$username not found.'),
                                backgroundColor:
                                    const Color(0xFFEF4444),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ));
                              return;
                            }

                            nav.pop();
                            final done = await ref
                                .read(connectionProvider.notifier)
                                .sendInvitation(username);
                            if (done) {
                              messenger.showSnackBar(SnackBar(
                                content: Text(
                                    'Request sent to @$username!'),
                                backgroundColor:
                                    const Color(0xFF10B981),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ));
                            }
                          },
                          icon: const Icon(Icons.send_rounded,
                              size: 16, color: Colors.white),
                          label: const Text('Send Request',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    ).then((_) => controller.dispose());
  }
}

// ─── QR Scanner Widget ────────────────────────────────────────────────────────

class _MovingLaserLine extends StatefulWidget {
  @override
  State<_MovingLaserLine> createState() =>
      _MovingLaserLineState();
}

class _MovingLaserLineState extends State<_MovingLaserLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Align(
          alignment:
              Alignment(0, -1.0 + (_controller.value * 2.0)),
          child: Container(
            height: 2,
            width: double.infinity,
            margin:
                const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981)
                      .withValues(alpha: 0.8),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QRScannerWidget extends StatefulWidget {
  final Function(String) onScan;
  const _QRScannerWidget({required this.onScan});

  @override
  State<_QRScannerWidget> createState() =>
      _QRScannerWidgetState();
}

class _QRScannerWidgetState extends State<_QRScannerWidget> {
  final MobileScannerController _controller =
      MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context)
                .primaryColor
                .withValues(alpha: 0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                for (final barcode in capture.barcodes) {
                  final raw = barcode.rawValue;
                  if (raw != null && raw.isNotEmpty) {
                    widget.onScan(raw);
                    break;
                  }
                }
              },
            ),
            _MovingLaserLine(),
            Positioned(
                top: 10,
                left: 10,
                child: Icon(Icons.crop_free_rounded,
                    color: Theme.of(context).primaryColor,
                    size: 24)),
            Positioned(
                top: 10,
                right: 10,
                child: Transform.rotate(
                    angle: 1.5708,
                    child: Icon(Icons.crop_free_rounded,
                        color: Theme.of(context).primaryColor,
                        size: 24))),
            Positioned(
                bottom: 10,
                left: 10,
                child: Transform.rotate(
                    angle: -1.5708,
                    child: Icon(Icons.crop_free_rounded,
                        color: Theme.of(context).primaryColor,
                        size: 24))),
            Positioned(
                bottom: 10,
                right: 10,
                child: Transform.rotate(
                    angle: 3.1415,
                    child: Icon(Icons.crop_free_rounded,
                        color: Theme.of(context).primaryColor,
                        size: 24))),
          ],
        ),
      ),
    );
  }
}

// ─── Option Tile ──────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500)),
      onTap: onTap,
      dense: true,
    );
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────

class ChatListItemData {
  final String name;
  final String username;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final bool isOnline;

  ChatListItemData({
    required this.name,
    required this.username,
    required this.lastMessage,
    required this.time,
    required this.unreadCount,
    required this.isOnline,
  });
}
