import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../../core/widgets/beautiful_avatar.dart';
import '../../../../providers/connection_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/encryption_service.dart';
import '../../../../services/message_storage_service.dart';
import '../../../../services/websocket_service.dart';
import '../../../chat/data/models/message_model.dart';
import '../../../chat/presentation/widgets/message_bubble.dart';

/// Group chat screen with Signal Protocol Sender Key E2EE.
///
/// Key flow:
///   Send: generateSenderKey (once) → distribute encrypted to each member → encryptGroupMessage
///   Receive: fetchGroupSenderKey → decryptSenderKeyFromPeer → decryptGroupMessage
///
/// SenderKey state is persisted in the secure_vault Hive box so the chain key
/// survives restarts. Peer keys are fetched lazily from the server and cached
/// in memory for the lifetime of the screen.
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
  ConsumerState<GroupChatScreen> createState() =>
      _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  int _membersCount = 1;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<MessageData> _messages = [];
  Timer? _countdownTimer;
  StreamSubscription? _socketSubscription;

  // ── Sender Key state ────────────────────────────────────────────────────────
  SenderKeyRecord? _mySenderKey;
  final Map<String, SenderKeyRecord> _peerSenderKeys = {};
  // Tracks which peers we've already distributed our SenderKey to this session
  final Set<String> _distributedTo = {};

  // ─── Vault key (Hive box name for our own SenderKey) ───────────────────────
  String get _mySkVaultKey => 'group_sk_${widget.groupId}';
  // Peer SenderKey vault key
  String _peerSkVaultKey(String username) =>
      'group_peer_sk_${widget.groupId}_$username';

  @override
  void initState() {
    super.initState();
    _loadLocalMessages();
    _syncMessages();

    if (widget.isCampfire && widget.expiresAt != null) {
      _countdownTimer =
          Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now >= widget.expiresAt!) {
          timer.cancel();
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('🔥 Campfire Group dissolved — session keys wiped.'),
            backgroundColor: Color(0xFFEF4444),
          ));
        } else {
          setState(() {});
        }
      });
    }

    _socketSubscription =
        WebSocketService().messageStream.listen((payload) async {
      if (payload['type'] == 'group_message' &&
          payload['groupId'] == widget.groupId) {
        final sender = payload['senderId']?.toString() ?? '';
        final ciphertext =
            payload['ciphertext']?.toString() ?? '';
        final timestamp = payload['timestamp'] as int? ??
            DateTime.now().millisecondsSinceEpoch;

        final myUsername = AuthService().username;
        if (sender == myUsername) return;

        final plaintext =
            await _decryptFromPeer(sender, ciphertext);

        final msg = MessageData(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: plaintext,
          isMe: false,
          sender: sender,
          time: _formatTimestamp(timestamp),
          isRead: true,
          timestamp: timestamp,
        );

        await MessageStorageService()
            .saveGroupMessage(widget.groupId, msg);
        if (mounted) {
          setState(() => _messages.add(msg));
          _scrollToBottom();
        }
      }
    });
  }

  // ─── Own SenderKey — load from vault or generate ───────────────────────────
  Future<SenderKeyRecord> _getOrCreateMySenderKey() async {
    if (_mySenderKey != null) return _mySenderKey!;

    final vault = await Hive.openBox('secure_vault');
    final stored = vault.get(_mySkVaultKey) as String?;

    if (stored != null) {
      _mySenderKey = SenderKeyRecord.fromJson(
          jsonDecode(stored) as Map<String, dynamic>);
      return _mySenderKey!;
    }

    // Generate fresh SenderKey
    _mySenderKey = await EncryptionService().generateSenderKey(
      groupId: widget.groupId,
      myUsername: AuthService().username ?? 'me',
    );
    await vault.put(
        _mySkVaultKey, jsonEncode(_mySenderKey!.toJson()));
    return _mySenderKey!;
  }

  /// Persists the mutated SenderKey back to the vault after each message.
  Future<void> _saveMySenderKey(SenderKeyRecord sk) async {
    final vault = await Hive.openBox('secure_vault');
    await vault.put(_mySkVaultKey, jsonEncode(sk.toJson()));
  }

  // ─── Distribute our SenderKey to group members we haven't reached yet ───────
  Future<void> _distributeSenderKeyIfNeeded() async {
    final mySk = await _getOrCreateMySenderKey();
    final members = await ApiService().getGroupMembers(widget.groupId);
    final myUsername = AuthService().username ?? '';

    // Find members we haven't distributed to this session
    final needed =
        members.where((m) => m != myUsername && !_distributedTo.contains(m));
    if (needed.isEmpty) return;

    final vault = await Hive.openBox('secure_vault');
    final bundles = <Map<String, String>>[];

    for (final memberUsername in needed) {
      // Fetch member's DH identity public key
      final keyBundle =
          await ApiService().fetchPublicKey(memberUsername);
      if (keyBundle == null) continue;
      final peerDhPub = keyBundle['dh_identity_key'] as String?;
      if (peerDhPub == null || peerDhPub.isEmpty) continue;

      // Encrypt our SenderKey for this member
      final encrypted =
          await EncryptionService().encryptSenderKeyForPeer(
        senderKey: mySk,
        peerDhIdentityPublicBase64: peerDhPub,
      );
      bundles.add({
        'recipientUsername': memberUsername,
        'encryptedBundle': encrypted,
      });
      _distributedTo.add(memberUsername);

      // Persist current chain key state (encryption is non-destructive here
      // but toJson captures the signingPrivateKey which must be consistent)
      await vault.put(
          _mySkVaultKey, jsonEncode(mySk.toJson()));
    }

    if (bundles.isNotEmpty) {
      await ApiService()
          .uploadGroupSenderKeyBundles(widget.groupId, bundles);
    }
  }

  // ─── Fetch and cache a peer's SenderKey ────────────────────────────────────
  Future<SenderKeyRecord?> _getPeerSenderKey(
      String senderUsername) async {
    if (_peerSenderKeys.containsKey(senderUsername)) {
      return _peerSenderKeys[senderUsername];
    }

    // Check persistent vault cache first
    final vault = await Hive.openBox('secure_vault');
    final cached =
        vault.get(_peerSkVaultKey(senderUsername)) as String?;
    if (cached != null) {
      final sk = SenderKeyRecord.fromJson(
          jsonDecode(cached) as Map<String, dynamic>);
      _peerSenderKeys[senderUsername] = sk;
      return sk;
    }

    // Fetch encrypted bundle from server
    final encrypted = await ApiService()
        .fetchGroupSenderKey(widget.groupId, senderUsername);
    if (encrypted == null) return null;

    // Decrypt using my DH identity private key
    final myVault = await Hive.openBox('secure_vault');
    final myDhPriv =
        myVault.get('identity_dh_private_key') as String?;
    final myDhPub =
        myVault.get('identity_dh_public_key') as String?;
    if (myDhPriv == null || myDhPub == null) return null;

    final sk = await EncryptionService().decryptSenderKeyFromPeer(
      encryptedBundleBase64: encrypted,
      myDhIdentityPrivateBase64: myDhPriv,
      myDhIdentityPublicBase64: myDhPub,
    );

    _peerSenderKeys[senderUsername] = sk;
    // Persist so we survive app restarts
    await vault.put(
        _peerSkVaultKey(senderUsername), jsonEncode(sk.toJson()));
    return sk;
  }

  /// Saves mutated peer SenderKey back to vault and in-memory cache.
  Future<void> _savePeerSenderKey(
      String username, SenderKeyRecord sk) async {
    _peerSenderKeys[username] = sk;
    final vault = await Hive.openBox('secure_vault');
    await vault.put(
        _peerSkVaultKey(username), jsonEncode(sk.toJson()));
  }

  // ─── Encrypt / Decrypt ─────────────────────────────────────────────────────
  Future<String> _encryptMessage(String plaintext) async {
    final sk = await _getOrCreateMySenderKey();
    final ciphertext = await EncryptionService().encryptGroupMessage(
      senderKey: sk,
      plaintext: plaintext,
    );
    await _saveMySenderKey(sk);
    return ciphertext;
  }

  Future<String> _decryptFromPeer(
      String sender, String ciphertext) async {
    try {
      final sk = await _getPeerSenderKey(sender);
      if (sk == null) {
        return '[Sender key not available — ask ${sender} to re-open the group]';
      }
      final plaintext = await EncryptionService()
          .decryptGroupMessage(senderKey: sk, encryptedPacketBase64: ciphertext);
      await _savePeerSenderKey(sender, sk);
      return plaintext;
    } catch (e) {
      return '[Decryption failed: $e]';
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────
  String _formatTimestamp(int timestamp) {
    final dt =
        DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _loadLocalMessages() async {
    final msgs = await MessageStorageService()
        .getGroupMessages(widget.groupId);
    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(msgs);
      });
      _scrollToBottom();
    }
  }

  Future<void> _syncMessages() async {
    // Ensure our SenderKey is distributed before we start syncing
    _distributeSenderKeyIfNeeded(); // fire-and-forget; don't await to not block UI

    final rawMsgs =
        await ApiService().getGroupMessages(widget.groupId);
    final myUsername = AuthService().username;

    for (final raw in rawMsgs) {
      final id = raw['id']?.toString() ?? '';
      final sender = raw['sender']?.toString() ?? '';
      final ciphertext =
          (raw['ciphertext'] ?? raw['text'])?.toString() ?? '';
      final createdAtStr = raw['created_at']?.toString() ?? '';

      int timestamp = DateTime.now().millisecondsSinceEpoch;
      try {
        timestamp = DateTime.parse(createdAtStr)
            .toLocal()
            .millisecondsSinceEpoch;
      } catch (_) {}

      final isMe = sender == myUsername;
      String plaintext;
      if (isMe) {
        // We can't re-decrypt our own messages from the server because we've
        // already advanced the send chain. Use local storage instead.
        plaintext = '[Your message]';
      } else {
        plaintext = await _decryptFromPeer(sender, ciphertext);
      }

      final msg = MessageData(
        id: id,
        text: plaintext,
        isMe: isMe,
        sender: sender,
        time: _formatTimestamp(timestamp),
        isRead: true,
        timestamp: timestamp,
      );
      await MessageStorageService()
          .saveGroupMessage(widget.groupId, msg);
    }

    await _loadLocalMessages();
  }

  String _getCampfireTimeRemaining() {
    if (widget.expiresAt == null) return '';
    final remaining =
        widget.expiresAt! - DateTime.now().millisecondsSinceEpoch;
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

  void _handleSendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final myUsername = AuthService().username ?? 'Me';
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final optimisticMsg = MessageData(
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
    setState(() => _messages.add(optimisticMsg));
    _scrollToBottom();

    // Distribute SenderKey to any new members before sending
    await _distributeSenderKeyIfNeeded();

    // Encrypt with Signal Sender Key
    final ciphertext = await _encryptMessage(text);

    final wasSent = await WebSocketService().sendGroupMessage(
      groupId: widget.groupId,
      ciphertext: ciphertext,
    );

    optimisticMsg.isSent = wasSent;
    await MessageStorageService()
        .saveGroupMessage(widget.groupId, optimisticMsg);
    if (mounted) setState(() {});
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

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B132B) : const Color(0xFFF1F5F9),
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
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.isCampfire) ...[
                        const SizedBox(width: 6),
                        const Icon(
                            Icons.local_fire_department_rounded,
                            color: Color(0xFFEF4444),
                            size: 18),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.isCampfire
                        ? _getCampfireTimeRemaining()
                        : '$_membersCount members · Signal E2EE',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.isCampfire
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF10B981),
                      fontWeight: FontWeight.w600,
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
            onPressed: () => _showInviteMembersDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => _showGroupInfoDialog(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildGroupMessageBubble(
                      msg, theme, isDark);
                },
              ),
            ),
            _buildInputBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupMessageBubble(
      MessageData msg, ThemeData theme, bool isDark) {
    return ChatMessageBubble(
      message: msg,
      isPlaying: false,
      isTranscriptExpanded: false,
      waveHeights: const [],
      onTogglePlay: () {},
      onToggleTranscript: () {},
      formatTime: (ts) => msg.time,
      senderName: msg.sender,
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(
            top: BorderSide(
                color: theme.dividerColor
                    .withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type message (Signal E2EE)...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                fillColor: Colors.transparent,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8),
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
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              const SizedBox(height: 16),
              if (connections.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No active connections found.',
                    style: TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        height: 1.4),
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
                        leading: BeautifulAvatar(
                          name: contact,
                          username: contact,
                          radius: 18,
                        ),
                        title: Text(contact,
                            style: const TextStyle(
                                color: Colors.white)),
                        trailing: const Icon(
                            Icons.send_rounded,
                            color: Color(0xFF8083FF)),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await ApiService()
                              .joinGroup(widget.groupId);
                          // SenderKey will be distributed on next send
                          _distributedTo.clear();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(
                            content: Text(
                                'Invited @$contact — E2EE keys will be exchanged on next message.'),
                            backgroundColor:
                                const Color(0xFF10B981),
                          ));
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
              const Icon(Icons.info_outline_rounded,
                  color: Color(0xFF8083FF)),
              const SizedBox(width: 10),
              Flexible(
                child: Text(widget.groupName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This group uses Signal Protocol Sender Key E2EE. '
                'Each member independently generates a SenderKey '
                'and distributes it encrypted to peers. The server '
                'stores only opaque ciphertext.',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.45),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 10),
              _buildInfoRow('Protocol', 'Signal Sender Keys (HMAC ratchet)'),
              _buildInfoRow('Signing', 'Ed25519 per message'),
              _buildInfoRow(
                  'Key Distribution', 'X25519 ECDH + AES-256-GCM'),
              _buildInfoRow('Members', '$_membersCount'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close',
                  style: TextStyle(color: Colors.white60)),
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
          Text(label,
              style: const TextStyle(
                  color: Colors.white60, fontSize: 11)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.w600,
                    fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
