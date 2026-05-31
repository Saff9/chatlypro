import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../services/message_storage_service.dart';
import '../../../../services/websocket_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'chat_screen.dart';
import '../../../../services/p2p_mesh_service.dart';
import 'p2p_chat_screen.dart';
import '../../../../providers/connection_provider.dart';
import '../../../../providers/layout_provider.dart';
import '../../../../services/api_service.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  // Real contacts loaded dynamically
  final List<ChatListItemData> _chats = [];

  // Decoy contacts shown in duress mode
  final List<ChatListItemData> _decoyChats = [];

  StreamSubscription? _socketSubscription;

  // Returns a deterministic color for the relationship health ring around the
  // contact avatar. In a future release this will be driven by a real engagement
  // score computed from message frequency and response latency metrics.
  Color _getRelationshipHealthColor(String username) {
    final hash = username.codeUnits.fold(0, (a, b) => a + b) % 3;
    switch (hash) {
      case 0:
        return const Color(0xFF10B981); // Active engagement
      case 1:
        return const Color(0xFFF59E0B); // Moderate engagement
      default:
        return const Color(0xFFEF4444); // Low engagement
    }
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
          final transcript = (data['voiceTranscript'] as String? ?? '').toLowerCase();
          if (text.contains(query) || transcript.contains(query)) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _loadChats() async {
    if (!mounted) return;
    final connectionState = ref.read(connectionProvider);
    final acceptedConnections = connectionState.connections;
    
    final List<ChatListItemData> loadedChats = [];
    for (final username in acceptedConnections) {
      final messages = await MessageStorageService().getMessages(username);
      final lastMsg = messages.isNotEmpty ? messages.last.text : 'Tap to start conversation.';
      final lastMsgTime = messages.isNotEmpty ? messages.last.time : '';
      final unreadCount = messages.where((m) => !m.isMe && !m.isRead).length;

      loadedChats.add(ChatListItemData(
        name: username.substring(0, 1).toUpperCase() + username.substring(1),
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
    P2PMeshService().startP2P();
    
    // Load decoy chats
    _decoyChats.addAll([
      ChatListItemData(
        name: 'Sarah Connor',
        username: 'sarah_c',
        lastMessage: 'Milk, eggs, and bread. Thanks!',
        time: '2 min ago',
        unreadCount: 0,
        isOnline: true,
      ),
      ChatListItemData(
        name: 'Dad',
        username: 'dad',
        lastMessage: 'Perfect, looking forward to it.',
        time: '45 min ago',
        unreadCount: 0,
        isOnline: false,
      ),
      ChatListItemData(
        name: 'Tech Support',
        username: 'tech_support',
        lastMessage: 'Great, it is working now. Thank you!',
        time: '18 hrs ago',
        unreadCount: 0,
        isOnline: false,
      ),
    ]);

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase().trim());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChats();
    });

    _socketSubscription = WebSocketService().messageStream.listen((event) {
      if (event['type'] == 'message') {
        _loadChats();
      }
    });
  }

  @override
  void dispose() {
    P2PMeshService().stopP2P();
    _searchController.dispose();
    _socketSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch connectionProvider to trigger rebuild when connections change
    ref.watch(connectionProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChats();
    });

    final theme = Theme.of(context);
    final densityBox = Hive.box('settings');
    final int density = densityBox.get('chat_tile_density', defaultValue: 5) as int;
    final double verticalMargin = (6.0 - (density - 5) * 1.0).clamp(2.0, 8.0);
    final double verticalPadding = (8.0 - (density - 5) * 2.0).clamp(0.0, 12.0);
    
    final textColor = theme.textTheme.bodyLarge?.color ?? const Color(0xFFE4E1ED);
    final subColor = theme.textTheme.bodyMedium?.color ?? const Color(0xFFC7C4D7);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: textColor, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search chats or @username...',
                  hintStyle: TextStyle(color: subColor.withValues(alpha: 0.5)),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                  prefixIcon: Icon(Icons.search_rounded, color: subColor.withValues(alpha: 0.6)),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.close_rounded, color: subColor.withValues(alpha: 0.6)),
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
                  Text('Chatly', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF13131B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: const BorderSide(color: Colors.white10),
                          ),
                          title: const Text('Privacy Shield Active', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          content: const Text(
                            'Your conversations are end-to-end encrypted. Only you and your contacts can read them.',
                            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3), width: 1.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shield_rounded, size: 10, color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Text(
                            'SHIELD ACTIVE',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF10B981).withValues(alpha: 0.9),
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
              icon: const Icon(Icons.radar_rounded),
              tooltip: 'Simulate Proximity Tap',
              onPressed: () {
                ref.read(connectionProvider.notifier).simulateProximityRequest('marcus_collect');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Simulated close-proximity NFC tap trigger!'),
                    backgroundColor: Color(0xFF6366F1),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded),
              onPressed: () {
                _showQRScannerDialog(context);
              },
            ),
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Proximity Request Alert Banner
          Builder(
            builder: (context) {
              final connState = ref.watch(connectionProvider);
              final activeReq = connState.activeProximityRequest;
              if (activeReq == null) return const SizedBox.shrink();

              return Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1F1C2C), Color(0xFF928DAB)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.radar_rounded, color: Colors.amber, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'PROXIMITY PAIR REQUEST',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber, letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Connect with @${activeReq.username} close by?',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                          onPressed: () {
                            ref.read(connectionProvider.notifier).rejectInvitation(activeReq.username);
                            ref.read(connectionProvider.notifier).clearProximityRequest();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.check_rounded, color: Colors.greenAccent),
                          onPressed: () {
                            ref.read(connectionProvider.notifier).acceptInvitation(activeReq.username);
                            ref.read(connectionProvider.notifier).clearProximityRequest();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Connected with @${activeReq.username}!'),
                                backgroundColor: const Color(0xFF10B981),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          // P2P Nearby Peers discovery row
          StreamBuilder<List<P2PPeer>>(
            stream: P2PMeshService().peersStream,
            initialData: P2PMeshService().discoveredPeers,
            builder: (context, snapshot) {
              final peers = snapshot.data ?? [];
              if (peers.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
                    child: Row(
                      children: [
                        const Icon(Icons.radar_rounded, color: Color(0xFF10B981), size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Nearby Peers (Offline Mesh)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 90,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      scrollDirection: Axis.horizontal,
                      itemCount: peers.length,
                      itemBuilder: (context, idx) {
                        final peer = peers[idx];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => P2PChatScreen(peer: peer),
                                ),
                              );
                            },
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: Text(
                                          peer.username[0].toUpperCase(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  peer.username,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                ],
              );
            },
          ),
          
          // Chat List View
          Expanded(
            child: Builder(builder: (context) {
              final bool isDuressActive = densityBox.get('is_duress_active', defaultValue: false) as bool;
              final sourceChats = isDuressActive ? _decoyChats : _chats;

              final filtered = _searchQuery.isEmpty
                  ? sourceChats
                  : sourceChats.where((c) {
                      return c.name.toLowerCase().contains(_searchQuery) ||
                          c.lastMessage.toLowerCase().contains(_searchQuery) ||
                          c.username.toLowerCase().contains(_searchQuery) ||
                          _hasMatchingMessages(c.username, _searchQuery);
                    }).toList();

              if (filtered.isEmpty) {
                // Show a contextual empty state: different copy for active search
                // vs a genuinely empty contact list on first launch.
                if (_searchQuery.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(
                          'No chats match "$_searchQuery"',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                // First-launch empty state — guide the user to add their first contact.
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                            border: Border.all(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.2),
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
                          padding: EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            'Add a contact by username to start a secure, encrypted conversation.',
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
                padding: const EdgeInsets.only(top: 8.0, bottom: 20.0),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final chat = filtered[index];
                  return Container(
                    margin: EdgeInsets.symmetric(horizontal: 16.0, vertical: verticalMargin),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.015),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.04),
                        width: 1.0,
                      ),
                    ),
                    child: ListTile(
                      onTap: () {
                        if (MediaQuery.of(context).size.width > 900) {
                          ref.read(selectedGroupProvider.notifier).state = null;
                          ref.read(selectedChatProvider.notifier).state = chat;
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(chatData: chat),
                            ),
                          );
                        }
                      },
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: verticalPadding),
                      leading: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _getRelationshipHealthColor(chat.username),
                                width: 2.0,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 23,
                              backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
                              child: Text(
                                chat.name[0],
                                style: TextStyle(
                                  color: theme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
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
                                  color: const Color(0xFF10B981), // Emerald
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF13131B), width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.4),
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
                            fontWeight: chat.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            chat.time,
                            style: TextStyle(
                              color: subColor.withValues(alpha: 0.4),
                              fontSize: 11,
                            ),
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
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
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
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: FloatingActionButton(
          onPressed: () {
            _showQRScannerDialog(context);
          },
          backgroundColor: theme.primaryColor,
          child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
        ),
      ),
    );
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
              title: const Text('E2E QR Connection Scanner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isScanning) ...[
                      // Simulated Camera Viewfinder
                      Container(
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.3)),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Text('[ Viewfinder Feed Active ]', style: TextStyle(color: Colors.white24, fontSize: 12)),
                            // Moving Laser Animation
                            _MovingLaserLine(),
                            // Corner markers
                            Positioned(top: 10, left: 10, child: Icon(Icons.crop_free_rounded, color: theme.primaryColor, size: 24)),
                            Positioned(top: 10, right: 10, child: Transform.rotate(angle: 1.5708, child: Icon(Icons.crop_free_rounded, color: theme.primaryColor, size: 24))),
                            Positioned(bottom: 10, left: 10, child: Transform.rotate(angle: -1.5708, child: Icon(Icons.crop_free_rounded, color: theme.primaryColor, size: 24))),
                            Positioned(bottom: 10, right: 10, child: Transform.rotate(angle: 3.1415, child: Icon(Icons.crop_free_rounded, color: theme.primaryColor, size: 24))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Align QR code inside the viewfinder to establish secure X25519 keys.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      // Mock scan targets
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white10,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onPressed: () => simulateScan('chatly:connect:@sarah_adams'),
                            child: const Text('Mock Sarah', style: TextStyle(fontSize: 11)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white10,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onPressed: () => simulateScan('chatly:connect:@marcus_collect'),
                            child: const Text('Mock Marcus', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ] else ...[
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Successfully Scanned Connection!',
                        style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        scanResult ?? '',
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ],
                    const Divider(height: 32, color: Colors.white10),
                    // Manual username entry field
                    TextField(
                      controller: usernameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Search or enter username manually...',
                        hintStyle: TextStyle(color: Colors.white30),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        suffixIcon: Icon(Icons.search, color: Colors.white30, size: 20),
                      ),
                      onChanged: (val) async {
                        final q = val.trim().replaceAll('@', '');
                        if (q.length >= 2) {
                          setState(() => isSearchingUsers = true);
                          final results = await ApiService().searchUsers(q);
                          setState(() {
                            searchResults = results;
                            isSearchingUsers = false;
                          });
                        } else {
                          setState(() {
                            searchResults = [];
                          });
                        }
                      },
                    ),
                    if (isSearchingUsers)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    if (searchResults.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 120),
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: searchResults.length,
                          itemBuilder: (context, idx) {
                            final user = searchResults[idx];
                            final uName = user['username'] ?? '';
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                              leading: CircleAvatar(
                                radius: 14,
                                backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
                                child: Text(
                                  uName.isNotEmpty ? uName[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Color(0xFF6366F1), fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text('@$uName', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              subtitle: Text(user['mood'] ?? '🎵 Vibing', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                              onTap: () {
                                usernameController.text = uName;
                                setState(() {
                                  searchResults = [];
                                });
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
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final username = usernameController.text.trim().replaceAll('@', '');
                    final target = username.isNotEmpty ? username : scanResult?.split('@').last;
                    if (target != null) {
                      final nav = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      
                      // Verify user existence on server first
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Verifying username on Chatly network...'),
                          duration: Duration(seconds: 1),
                        ),
                      );

                      final results = await ApiService().searchUsers(target);
                      final userExists = results.any((u) => u['username'].toString().toLowerCase() == target.toLowerCase());

                      if (!userExists) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('User @$target not found on the network.'),
                            backgroundColor: const Color(0xFFEF4444),
                          ),
                        );
                        return;
                      }

                      nav.pop();
                      final done = await ref.read(connectionProvider.notifier).sendInvitation(target);
                      if (done) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Connected E2E keys and sent invitation to @$target!'),
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
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
}

class _MovingLaserLine extends StatefulWidget {
  @override
  State<_MovingLaserLine> createState() => _MovingLaserLineState();
}

class _MovingLaserLineState extends State<_MovingLaserLine> with SingleTickerProviderStateMixin {
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
          alignment: Alignment(0, -1.0 + (_controller.value * 2.0)),
          child: Container(
            height: 2,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.8),
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
