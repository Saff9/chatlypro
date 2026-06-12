import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_list_screen.dart';
import '../../data/models/message_model.dart';
import '../../../../services/encryption_service.dart';
import '../../../../services/websocket_service.dart';
import '../../../../services/forensic_eraser_service.dart';
import '../../../../services/message_storage_service.dart';
import '../../../../core/widgets/secure_keyboard.dart';
import '../../../../providers/wallpaper_provider.dart';
import '../../../../services/p2p_mesh_service.dart';
import '../../../../core/widgets/beautiful_avatar.dart';
import '../../../../services/api_service.dart';

// ─── Reaction catalogue ─────────────────────────────────────────────────────
final _kReactions = [
  {'key': 'thumb_up',                 'icon': Icons.thumb_up_rounded,                  'label': 'Like'},
  {'key': 'favorite',                 'icon': Icons.favorite_rounded,                  'label': 'Love'},
  {'key': 'bolt',                     'icon': Icons.bolt_rounded,                      'label': 'Wow'},
  {'key': 'sentiment_very_satisfied', 'icon': Icons.sentiment_very_satisfied_rounded,  'label': 'Haha'},
  {'key': 'sentiment_dissatisfied',   'icon': Icons.sentiment_dissatisfied_rounded,    'label': 'Sad'},
  {'key': 'celebration',              'icon': Icons.celebration_rounded,               'label': 'Celebrate'},
];

// ─── Vault timer catalogue ────────────────────────────────────────────────────
final _kTimerOptions = [
  {'label': 'Off',    'ms': null},
  {'label': '30 s',   'ms': 30000},
  {'label': '1 min',  'ms': 60000},
  {'label': '5 min',  'ms': 300000},
  {'label': '1 hr',   'ms': 3600000},
];

class ChatScreen extends ConsumerStatefulWidget {
  final ChatListItemData chatData;

  const ChatScreen({super.key, required this.chatData});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with TickerProviderStateMixin {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<MessageData> _messages = [];

  bool _isVaultMode = false;
  bool _isTyping = false;
  bool _isSecureKeyboardActive = false;
  int? _vaultTimerMs; // null = no expiry

  StreamSubscription? _socketSubscription;
  StreamSubscription? _stateSubscription;
  Timer? _expiryTimer;
  DoubleRatchetSession? _session;
  bool _isServiceReady = false;

  // UI state
  int? _activeTimeLockDelayMs;
  final Map<String, bool> _isPlayingMap = {};
  final Map<String, bool> _isTranscriptExpandedMap = {};
  bool _isRecordingVoice = false;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  final List<double> _waveHeights = [10, 24, 12, 35, 18, 30, 15, 28, 8, 22, 14, 38, 20];

  @override
  void initState() {
    super.initState();
    _initializeE2E();
    _loadMessageHistory();
    // Fast periodic timer: ticks every 1s to update locked text countdowns
    int ticks = 0;
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      ticks++;
      if (ticks % 5 == 0) {
        _purgeExpired();
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  DATA LAYER
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _loadMessageHistory() async {
    // In duress mode, simply show an empty conversation
    final settingsBox = Hive.box('settings');
    final bool isDuress = settingsBox.get('is_duress_active', defaultValue: false) as bool;
    if (isDuress) {
      if (mounted) setState(() => _messages.clear());
      return;
    }

    final history = await MessageStorageService().getMessages(widget.chatData.username);
    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(history);
      });
    }
  }

  Future<void> _initializeE2E() async {
    final secureBox = await Hive.openBox('secure_vault');
    
    // Check if we already have an active Double Ratchet session
    final sessionJson = secureBox.get('session_${widget.chatData.username}') as String?;
    if (sessionJson != null && sessionJson.isNotEmpty) {
      try {
        _session = DoubleRatchetSession.fromJson(jsonDecode(sessionJson));
        if (mounted) setState(() => _isServiceReady = true);
      } catch (e) {
        debugPrint('Error loading Double Ratchet session: $e');
      }
    }

    // If session is not ready, establish the handshake (initiator side)
    if (_session == null) {
      final bundle = await ApiService().fetchPublicKey(widget.chatData.username);
      if (bundle != null && bundle['identity_key'] != null) {
        try {
          final myDhPriv = secureBox.get('identity_dh_private_key') as String?;
          final myDhPub = secureBox.get('identity_dh_public_key') as String?;
          
          if (myDhPriv != null && myDhPub != null) {
            final crypto = EncryptionService();
            _session = await crypto.initInitiatorSession(
              peerUsername: widget.chatData.username,
              myDhIdentityPrivateBase64: myDhPriv,
              myDhIdentityPublicBase64: myDhPub,
              peerIdentitySignPublicBase64: bundle['identity_key'],
              peerIdentityDhPublicBase64: bundle['dh_identity_key'],
              peerSignedPrekeyPublicBase64: bundle['signed_prekey'],
              peerSignatureBase64: bundle['prekey_signature'],
            );

            // Cache peer keys for safety numbers verification dialog
            await secureBox.put('recipient_sign_pub_${widget.chatData.username}', bundle['identity_key']);

            // Save the session
            await secureBox.put('session_${widget.chatData.username}', jsonEncode(_session!.toJson()));
            if (mounted) setState(() => _isServiceReady = true);
          }
        } catch (e) {
          debugPrint('Error initiating Double Ratchet session: $e');
        }
      }
    }

    _socketSubscription =
        WebSocketService().messageStream.listen(_handleIncomingSocketPayload);
    _stateSubscription = WebSocketService().stateStream.listen((state) {
      if (mounted) setState(() {});
    });
  }

  void _handleIncomingSocketPayload(Map<String, dynamic> payload) async {
    if (payload['senderId'] != widget.chatData.username) {
      return;
    }

    if (payload['type'] == 'typing') {
      setState(() => _isTyping = payload['isTyping'] ?? false);
    } else if (payload['type'] == 'message') {
      final ciphertext = payload['ciphertext'];
      if (ciphertext != null) {
        try {
          final secureBox = await Hive.openBox('secure_vault');
          String? sessionJson = secureBox.get('session_${widget.chatData.username}') as String?;
          DoubleRatchetSession session;

          if (sessionJson != null && sessionJson.isNotEmpty) {
            session = DoubleRatchetSession.fromJson(jsonDecode(sessionJson));
          } else {
            // Handshake Receiver initialization
            // First decode the header to get Alice's ephemeral key
            final decodedJson = utf8.decode(base64Decode(ciphertext));
            final packet = jsonDecode(decodedJson) as Map<String, dynamic>;
            final headerJson = utf8.decode(base64Decode(packet['header']));
            final header = jsonDecode(headerJson) as Map<String, dynamic>;
            final peerEphemeralPub = header['dh_pub'] as String;

            // Fetch Alice's prekey bundle from server to get her identity keys
            final aliceBundle = await ApiService().fetchPublicKey(widget.chatData.username);
            if (aliceBundle == null) throw Exception('Handshake failed: cannot fetch sender bundle.');

            // Read my keys
            final myDhPriv = secureBox.get('identity_dh_private_key') as String;
            final myDhPub = secureBox.get('identity_dh_public_key') as String;
            final mySpkPriv = secureBox.get('signed_prekey_private_key') as String;
            final mySpkPub = secureBox.get('signed_prekey_public_key') as String;

            session = await EncryptionService().initReceiverSession(
              peerUsername: widget.chatData.username,
              myDhIdentityPrivateBase64: myDhPriv,
              myDhIdentityPublicBase64: myDhPub,
              mySignedPrekeyPrivateBase64: mySpkPriv,
              mySignedPrekeyPublicBase64: mySpkPub,
              peerIdentityDhPublicBase64: aliceBundle['dh_identity_key'],
              peerEphemeralPublicBase64: peerEphemeralPub,
            );

            // Cache peer keys for safety numbers verification dialog
            await secureBox.put('recipient_sign_pub_${widget.chatData.username}', aliceBundle['identity_key']);
          }

          // Decrypt the message using Double Ratchet
          final plaintext = await EncryptionService().decrypt(
            session: session,
            encryptedPacketBase64: ciphertext,
          );

          // Save the advanced session state
          await secureBox.put('session_${widget.chatData.username}', jsonEncode(session.toJson()));
          _session = session;
          _isServiceReady = true;

          final newMsg = MessageData(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            text: plaintext,
            isMe: false,
            time: 'Now',
            isRead: true,
            isVault: _isVaultMode,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            expiresAt: _vaultTimerMs != null
                ? DateTime.now().millisecondsSinceEpoch + _vaultTimerMs!
                : null,
          );
          await MessageStorageService().saveMessage(widget.chatData.username, newMsg);
          _addMessageAndCheckLimit(newMsg);
        } catch (e) {
          debugPrint('Decryption error: $e');
          final errMsg = MessageData(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            text: '[Decryption failed — secure handshake mismatch]',
            isMe: false,
            time: 'Now',
            isRead: true,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
          await MessageStorageService().saveMessage(widget.chatData.username, errMsg);
          _addMessageAndCheckLimit(errMsg);
        }
      }
    }
  }

  void _addMessageAndCheckLimit(MessageData msg) {
    setState(() => _messages.add(msg));
    _enforceSlidingLimit();
    // Auto-scroll to bottom
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

  void _enforceSlidingLimit() async {
    await MessageStorageService().enforceLimit(widget.chatData.username);
    final updatedHistory = await MessageStorageService().getMessages(widget.chatData.username);
    if (mounted) {
      final oldLength = _messages.length;
      setState(() {
        _messages.clear();
        _messages.addAll(updatedHistory);
      });
      if (oldLength > 50) {
        final isRandomizationEnabled = ForensicEraserService().isActiveChatRandomizationEnabled();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isRandomizationEnabled ? Icons.shuffle_rounded : Icons.delete_sweep_outlined,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(isRandomizationEnabled
                      ? 'History limit reached — oldest messages scrambled.'
                      : 'History limit reached — oldest messages shredded.'),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF6366F1),
          ),
        );
      }
    }
  }

  Future<void> _purgeExpired() async {
    final purged = await MessageStorageService().purgeExpiredMessages(widget.chatData.username);
    if (purged.isNotEmpty && mounted) {
      setState(() {
        _messages.removeWhere((m) => purged.contains(m.id));
      });
    }
  }

  void _handleSendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;



    final settingsBox = Hive.box('settings');
    final bool isDuress = settingsBox.get('is_duress_active', defaultValue: false) as bool;

    if (isDuress) {
      final newMessage = MessageData(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text,
        isMe: true,
        time: 'Now',
        isRead: false,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      _messageController.clear();
      setState(() => _isTyping = false);
      _addMessageAndCheckLimit(newMessage);
      return;
    }

    final expiresAt = _vaultTimerMs != null
        ? DateTime.now().millisecondsSinceEpoch + _vaultTimerMs!
        : null;

    final bool isTimeLocked = _activeTimeLockDelayMs != null;
    final int? unlocksAt = isTimeLocked
        ? DateTime.now().millisecondsSinceEpoch + _activeTimeLockDelayMs!
        : null;

    // Reset one-shot reveal delay
    _activeTimeLockDelayMs = null;

    final newMessage = MessageData(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text,
      isMe: true,
      time: 'Now',
      isRead: false,
      isVault: _isVaultMode,
      isSent: false,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      expiresAt: expiresAt,
      isTimeLocked: isTimeLocked,
      unlocksAt: unlocksAt,
    );

    _messageController.clear();
    setState(() => _isTyping = false);

    await MessageStorageService().saveMessage(widget.chatData.username, newMessage);
    _addMessageAndCheckLimit(newMessage);

    if (_session != null && _isServiceReady) {
      final ciphertext = await EncryptionService().encrypt(
        session: _session!,
        plaintext: text,
      );
      
      // Save updated Double Ratchet session state
      final secureBox = await Hive.openBox('secure_vault');
      await secureBox.put('session_${widget.chatData.username}', jsonEncode(_session!.toJson()));

      final wasSent = await WebSocketService().sendMessage(
        recipientId: widget.chatData.username,
        ciphertext: ciphertext,
      );
      if (wasSent) {
        newMessage.isSent = true;
        await MessageStorageService().saveMessage(widget.chatData.username, newMessage);
        if (mounted) setState(() {});
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  PREMIUM NEW FEATURE HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  String _getAdaptiveRouteLabel() {
    final socketState = WebSocketService().connectionState;
    final isPeerNearby = P2PMeshService().discoveredPeers.any((p) => p.username == widget.chatData.username);
    if (isPeerNearby) {
      return '📡 P2P Mesh';
    } else if (socketState == SocketConnectionState.connected) {
      return '🌐 WebSocket';
    } else {
      return '💾 Outbox Cache';
    }
  }

  Future<void> _exportChatTranscript() async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('==============================================');
      buffer.writeln('CHATLY CONVERSATION TRANSCRIPT');
      buffer.writeln('Export Date: ${DateTime.now().toLocal()}');
      buffer.writeln('Chat Partner: @${widget.chatData.username} (${widget.chatData.name})');
      buffer.writeln('Encryption: X25519 E2E Cryptography');
      buffer.writeln('==============================================\n');
      
      for (final msg in _messages) {
        final sender = msg.isMe ? 'Me' : widget.chatData.name;
        final typePrefix = msg.isVoice ? '[VOICE MESSAGE - Duration: ${msg.voiceDuration}s] ' : '';
        final timeStr = _formatTime(msg.timestamp);
        
        buffer.writeln('[$timeStr] $sender: $typePrefix${msg.text}');
        if (msg.isVoice && msg.voiceTranscript != null) {
          buffer.writeln('   └─ Transcript: "${msg.voiceTranscript}"');
        }
      }
      
      buffer.writeln('\n==============================================');
      buffer.writeln('END OF TRANSCRIPT — SECURED BY CHATLY');
      buffer.writeln('==============================================');
      
      final text = buffer.toString();
      
      // Save locally to sandboxed temporary directory
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/chat_with_${widget.chatData.username}.txt');
      await file.writeAsString(text);

      // Copy to Clipboard
      await Clipboard.setData(ClipboardData(text: text));

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF13131B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Colors.white10),
            ),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
                SizedBox(width: 10),
                Text('Transcript Exported', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'Successfully generated transcript file at:\n\n${file.absolute.path}\n\nAll content has also been copied to your clipboard!',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export transcript: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showEntropyDialog() {
    int userMsgCount = 0;
    int partnerMsgCount = 0;
    int userWordCount = 0;
    int partnerWordCount = 0;
    
    for (final m in _messages) {
      if (m.isMe) {
        userMsgCount++;
        userWordCount += m.text.split(' ').length;
      } else {
        partnerMsgCount++;
        partnerWordCount += m.text.split(' ').length;
      }
    }

    final double avgUserLen = userMsgCount > 0 ? userWordCount / userMsgCount : 0.0;
    final double avgPartnerLen = partnerMsgCount > 0 ? partnerWordCount / partnerMsgCount : 0.0;
    
    double entropyScore = 12.5; // Base entropy
    if (avgPartnerLen > 0 && avgPartnerLen < 3) {
      entropyScore += 35.0; // short responses like "k", "ok"
    }
    if (avgUserLen > 0 && avgUserLen < 3) {
      entropyScore += 20.0;
    }
    
    final bool fadingInterest = entropyScore > 40.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF13131B),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.analytics_rounded, color: Color(0xFF8083FF)),
                  const SizedBox(width: 10),
                  Text(
                    'Conversation Entropy Analyzer',
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Text(
                      '${entropyScore.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: fadingInterest ? Colors.redAccent : const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Signal Entropy Index',
                      style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.0),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatItem('My Msg Count', '$userMsgCount'),
                  _buildStatItem('My Avg Words', avgUserLen.toStringAsFixed(1)),
                  _buildStatItem('Partner Msg Count', '$partnerMsgCount'),
                  _buildStatItem('Partner Avg Words', avgPartnerLen.toStringAsFixed(1)),
                ],
              ),
              const SizedBox(height: 24),
              if (fadingInterest)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '⚠️ WARNING: High Entropy detected. Replying speed is dropping and message lengths are diminishing. Fading interest likely.',
                          style: TextStyle(color: Colors.redAccent, fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '✅ STABLE INTEREST: Replying intervals and vocabulary density indicate healthy engagement levels.',
                          style: TextStyle(color: Color(0xFF10B981), fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white30, fontSize: 9),
        ),
      ],
    );
  }

  void _showTimeLockSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF13131B),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.lock_clock_rounded, color: Colors.orange),
                  SizedBox(width: 10),
                  Text('Set Time-Locked Reveal Delay', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              const Text('The message will be encrypted and hidden until the delay passes.', style: TextStyle(color: Colors.white30, fontSize: 11)),
              const SizedBox(height: 16),
              _buildDelayTile(context, 'No Lock', null),
              _buildDelayTile(context, '10 Seconds (Test Mode)', 10000),
              _buildDelayTile(context, '1 Minute', 60000),
              _buildDelayTile(context, '5 Minutes', 300000),
              _buildDelayTile(context, '1 Hour', 3600000),
              _buildDelayTile(context, '24 Hours', 86400000),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDelayTile(BuildContext context, String label, int? delayMs) {
    final isSelected = _activeTimeLockDelayMs == delayMs;
    return ListTile(
      title: Text(label, style: TextStyle(color: isSelected ? Colors.orange : Colors.white70, fontSize: 14)),
      trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: Colors.orange) : null,
      onTap: () {
        setState(() {
          _activeTimeLockDelayMs = delayMs;
        });
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(delayMs == null ? 'Time-Lock disabled.' : 'Time-Lock activated for next message: $label'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  Future<bool> _requestAudioPermission(BuildContext context) async {
    final box = Hive.box('settings');
    final alreadyGranted = box.get('audio_permission_granted', defaultValue: false) as bool;
    if (alreadyGranted) {
      return true;
    }

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
              Icon(Icons.mic_rounded, color: theme.primaryColor),
              const SizedBox(width: 12),
              const Text('Microphone Permission', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: const Text(
            'Chatly requires access to your microphone to record and send voice notes. Do you want to grant this permission?',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                completer.complete(false);
              },
              child: const Text('Deny', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                await box.put('audio_permission_granted', true);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
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

  void _startVoiceRecording() {
    setState(() {
      _isRecordingVoice = true;
      _recordingDuration = 0;
    });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordingDuration++;
        });
      }
    });
  }

  void _stopVoiceRecordingAndSend() async {
    _recordingTimer?.cancel();
    if (!_isRecordingVoice) return;
    
    final duration = _recordingDuration > 0 ? _recordingDuration : 3;
    setState(() {
      _isRecordingVoice = false;
    });

    final controller = TextEditingController();
    final transcript = await showDialog<String>(
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
          title: const Row(
            children: [
              Icon(Icons.mic_rounded, color: Color(0xFF8083FF)),
              SizedBox(width: 8),
              Text('Voice Transcript', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter or dictate the transcript for your voice message (tap your keyboard microphone to dictate):',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Speak or type here...',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(context).pop(controller.text.trim());
              },
              child: const Text('Send Voice', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (transcript == null || transcript.isEmpty) return;

    final newVoiceMsg = MessageData(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: "[Voice Message] $transcript",
      isMe: true,
      time: 'Now',
      isRead: false,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isVoice: true,
      voiceDuration: duration,
      voiceTranscript: transcript,
      isSent: false,
    );

    final settingsBox = Hive.box('settings');
    final bool isDuress = settingsBox.get('is_duress_active', defaultValue: false) as bool;
    
    if (!isDuress) {
      await MessageStorageService().saveMessage(widget.chatData.username, newVoiceMsg);
    }
    _addMessageAndCheckLimit(newVoiceMsg);

    if (_session != null && _isServiceReady) {
      final ciphertext = await EncryptionService().encrypt(
        session: _session!,
        plaintext: "[Voice Message] $transcript",
      );
      
      // Save updated Double Ratchet session state
      final secureBox = await Hive.openBox('secure_vault');
      await secureBox.put('session_${widget.chatData.username}', jsonEncode(_session!.toJson()));
      final wasSent = await WebSocketService().sendMessage(
        recipientId: widget.chatData.username,
        ciphertext: ciphertext,
      );
      if (wasSent) {
        newVoiceMsg.isSent = true;
        if (!isDuress) {
          await MessageStorageService().saveMessage(widget.chatData.username, newVoiceMsg);
        }
        if (mounted) setState(() {});
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  REACTIONS
  // ──────────────────────────────────────────────────────────────────────────

  void _showMessageOptions(int index) {
    final msg = _messages[index];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 30, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Reaction row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _kReactions.map((r) {
                    final key = r['key'] as String;
                    final icon = r['icon'] as IconData;
                    final label = r['label'] as String;
                    final alreadyReacted = msg.reactions.containsKey(key);

                    return GestureDetector(
                      onTap: () async {
                        Navigator.of(context).pop();
                        await MessageStorageService()
                            .saveReaction(widget.chatData.username, msg.id, key);
                        final updated = await MessageStorageService().getMessages(widget.chatData.username);
                        if (mounted) {
                          setState(() {
                            _messages.clear();
                            _messages.addAll(updated);
                          });
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: alreadyReacted
                              ? const Color(0xFF6366F1).withValues(alpha: 0.15)
                              : theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: alreadyReacted
                                ? const Color(0xFF6366F1)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 26,
                              color: alreadyReacted
                                  ? const Color(0xFF6366F1)
                                  : theme.iconTheme.color?.withValues(alpha: 0.7),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: alreadyReacted ? FontWeight.bold : FontWeight.normal,
                                color: alreadyReacted ? const Color(0xFF6366F1) : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 1),
              Builder(
                builder: (context) {
                  final now = DateTime.now().millisecondsSinceEpoch;
                  final ageMs = now - msg.timestamp;
                  final canModify = ageMs < 1.5 * 60 * 60 * 1000; // 90 minutes

                  if (msg.isMe) {
                    if (canModify) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.edit_rounded, color: Color(0xFF8083FF)),
                            title: const Text('Edit Message'),
                            onTap: () {
                              Navigator.of(context).pop();
                              _showEditMessageDialog(index);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                            title: const Text('Delete Message', style: TextStyle(color: Color(0xFFEF4444))),
                            onTap: () {
                              Navigator.of(context).pop();
                              _showDeleteMessageDialog(index);
                            },
                          ),
                        ],
                      );
                    } else {
                      return const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: Icon(Icons.edit_rounded, color: Colors.grey),
                            title: Text('Edit Message (Locked)', style: TextStyle(color: Colors.grey)),
                            subtitle: Text('Locked after 1.5 hours', style: TextStyle(color: Colors.grey, fontSize: 10)),
                            enabled: false,
                          ),
                          ListTile(
                            leading: Icon(Icons.delete_outline_rounded, color: Colors.grey),
                            title: Text('Delete Message (Locked)', style: TextStyle(color: Colors.grey)),
                            subtitle: Text('Locked after 1.5 hours', style: TextStyle(color: Colors.grey, fontSize: 10)),
                            enabled: false,
                          ),
                        ],
                      );
                    }
                  } else {
                    return ListTile(
                      leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                      title: const Text('Delete Locally', style: TextStyle(color: Color(0xFFEF4444))),
                      onTap: () {
                        Navigator.of(context).pop();
                        _showDeleteMessageDialog(index);
                      },
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showEditMessageDialog(int index) {
    final msg = _messages[index];
    final editController = TextEditingController(text: msg.text);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10, width: 1.0),
          ),
          title: const Text('Edit Message', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: editController,
            maxLines: null,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Edit your message...',
              hintStyle: TextStyle(color: Colors.white30),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final nav = Navigator.of(context);
                final newText = editController.text.trim();
                if (newText.isNotEmpty && newText != msg.text) {
                  msg.text = newText;
                  await MessageStorageService().saveMessage(widget.chatData.username, msg);
                  final updatedHistory = await MessageStorageService().getMessages(widget.chatData.username);
                  if (mounted) {
                    setState(() {
                      _messages.clear();
                      _messages.addAll(updatedHistory);
                    });
                  }
                }
                nav.pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  VAULT TIMER SELECTOR
  // ──────────────────────────────────────────────────────────────────────────

  void _showVaultTimerSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Icon(Icons.timer_rounded, color: Color(0xFFF59E0B)),
                    SizedBox(width: 10),
                    Text(
                      'Disappearing Messages Timer',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'New messages in Vault Mode will auto-delete after this duration.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
              const SizedBox(height: 16),
              ..._kTimerOptions.map((opt) {
                final ms = opt['ms'] as int?;
                final isSelected = _vaultTimerMs == ms;
                return ListTile(
                  leading: Icon(
                    ms == null ? Icons.timer_off_rounded : Icons.timer_rounded,
                    color: isSelected ? const Color(0xFFF59E0B) : null,
                  ),
                  title: Text(
                    opt['label'] as String,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? const Color(0xFFF59E0B) : null,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_rounded, color: Color(0xFFF59E0B))
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    setState(() => _vaultTimerMs = ms);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.timer_rounded, color: Colors.white, size: 16),
                            const SizedBox(width: 10),
                            Text(ms == null
                                ? 'Disappearing timer disabled.'
                                : 'Messages will vanish after ${opt['label']}.'),
                          ],
                        ),
                        backgroundColor: const Color(0xFFF59E0B),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  DELETE
  // ──────────────────────────────────────────────────────────────────────────

  void _showDeleteMessageDialog(int index) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Delete Message?'),
          content: const Text(
            'Are you sure you want to delete this message? If Forensic Eraser Mode is active, the data blocks will be shredded before deletion.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteMessage(index);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _deleteMessage(int index) async {
    final msg = _messages[index];
    final isForensic = ForensicEraserService().isForensicEraserEnabled();

    await MessageStorageService().deleteMessage(widget.chatData.username, msg.id);
    final updatedHistory = await MessageStorageService().getMessages(widget.chatData.username);

    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(updatedHistory);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isForensic ? Icons.shield_outlined : Icons.delete_outline_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 10),
              Text(isForensic ? 'Message shredded and deleted from disk.' : 'Message deleted.'),
            ],
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _stateSubscription?.cancel();
    _expiryTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final wallpaperState = ref.watch(wallpaperProvider);
    final activePreset = ref.read(wallpaperProvider.notifier).activePreset;

    BoxDecoration bodyDecoration;
    if (_isVaultMode) {
      bodyDecoration = BoxDecoration(
        color: isDark ? const Color(0xFF1A120B) : const Color(0xFFFFFBEB),
      );
    } else if (activePreset.imagePath != null) {
      bodyDecoration = BoxDecoration(
        image: DecorationImage(
          image: AssetImage(activePreset.imagePath!),
          fit: BoxFit.cover,
          opacity: isDark ? 0.35 : 0.65,
        ),
        color: activePreset.solidColor,
      );
    } else {
      if (wallpaperState.customGradient != null || activePreset.gradientColors != null) {
        bodyDecoration = BoxDecoration(
          gradient: LinearGradient(
            colors: wallpaperState.customGradient ?? activePreset.gradientColors!,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        );
      } else {
        bodyDecoration = BoxDecoration(
          color: wallpaperState.customSolidColor ?? activePreset.solidColor,
        );
      }
    }

    return Scaffold(
      backgroundColor: _isVaultMode
          ? (isDark ? const Color(0xFF1A120B) : const Color(0xFFFFFBEB))
          : (wallpaperState.customSolidColor ?? activePreset.solidColor),
      appBar: AppBar(
        backgroundColor: _isVaultMode
            ? (isDark ? const Color(0xFF2C1B0F) : const Color(0xFFFEF3C7))
            : theme.cardColor,
        leadingWidth: 70,
        leading: InkWell(
          onTap: () => Navigator.of(context).pop(),
          borderRadius: BorderRadius.circular(30),
          child: Row(
            children: [
              const SizedBox(width: 4),
              const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              const SizedBox(width: 4),
              BeautifulAvatar(
                name: widget.chatData.name,
                username: widget.chatData.username,
                radius: 18,
              ),
            ],
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.chatData.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                Icon(Icons.verified_user_rounded, size: 14, color: theme.primaryColor),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  widget.chatData.isOnline ? 'Online • Vibing' : 'Offline',
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.chatData.isOnline
                        ? const Color(0xFF10B981)
                        : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getAdaptiveRouteLabel(),
                    style: const TextStyle(fontSize: 8, color: Colors.white60, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Vault Chat Mode Toggle
          IconButton(
            icon: Icon(
              _isVaultMode ? Icons.lock_open_rounded : Icons.lock_rounded,
              color: _isVaultMode ? const Color(0xFFF59E0B) : theme.iconTheme.color,
            ),
            tooltip: 'Toggle Vault Chat (Self-Destructing)',
            onPressed: () {
              setState(() => _isVaultMode = !_isVaultMode);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(
                        _isVaultMode ? Icons.lock_rounded : Icons.lock_open_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      Text(_isVaultMode
                          ? 'Vault Chat Activated. Messages will self-destruct.'
                          : 'Vault Chat Deactivated.'),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                  backgroundColor: _isVaultMode ? const Color(0xFFF59E0B) : theme.primaryColor,
                ),
              );
            },
          ),
          // Disappearing message timer (only visible in vault mode)
          if (_isVaultMode)
            IconButton(
              icon: Badge(
                isLabelVisible: _vaultTimerMs != null,
                backgroundColor: const Color(0xFFF59E0B),
                label: const Text('●', style: TextStyle(fontSize: 6)),
                child: const Icon(Icons.timer_rounded),
              ),
              tooltip: 'Disappearing Messages Timer',
              onPressed: _showVaultTimerSelector,
              color: _vaultTimerMs != null ? const Color(0xFFF59E0B) : theme.iconTheme.color,
            ),
          IconButton(
            icon: const Icon(Icons.analytics_rounded),
            tooltip: 'Conversation Entropy',
            onPressed: _showEntropyDialog,
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export Transcript',
            onPressed: _exportChatTranscript,
          ),
          IconButton(
            icon: const Icon(Icons.verified_user_rounded),
            tooltip: 'Verify Safety Numbers',
            onPressed: _showSafetyNumbersDialog,
            color: const Color(0xFF10B981),
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          decoration: bodyDecoration,
          child: Stack(
            children: [
              if (!_isVaultMode && activePreset.imagePath == null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: ChatWallpaperPainter(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              Column(
                children: [
                  // Cryptography Trust Notice Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    color: theme.primaryColor.withValues(alpha: 0.06),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.security_rounded, size: 14, color: Color(0xFF6366F1)),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Messages are end-to-end encrypted with Signal Protocol.',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                        if (_isVaultMode) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.hourglass_bottom_rounded, size: 10, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 4),
                                Text(
                                  _vaultTimerMs == null
                                      ? 'Vault On'
                                      : 'Vanish: ${_kTimerOptions.firstWhere((o) => o['ms'] == _vaultTimerMs)['label']}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFFF59E0B),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Conversation Body
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return GestureDetector(
                          onLongPress: () => _showMessageOptions(index),
                          child: Column(
                            crossAxisAlignment:
                                msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              _buildMessageBubble(msg, theme),
                              if (msg.reactions.isNotEmpty)
                                _buildReactionPill(msg, theme),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Typing Indicator
                  if (_isTyping)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                      child: Row(
                        children: [
                          Text(
                            '${widget.chatData.name} is typing',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        ],
                      ),
                    ),

                  // Input Bar
                  _buildInputBar(theme),

                  // Secure Keyboard
                  if (_isSecureKeyboardActive)
                    SecureKeyboard(
                      controller: _messageController,
                      onSend: _handleSendMessage,
                      onClose: () {
                        setState(() {
                          _isSecureKeyboardActive = false;
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  WIDGETS
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildMessageBubble(MessageData message, ThemeData theme) {
    final isMe = message.isMe;
    final isDark = theme.brightness == Brightness.dark;

    // Check if locked
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

      final bubbleColor = isMe
          ? theme.primaryColor
          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0));
      final textColor = isMe ? Colors.white : (isDark ? Colors.white : Colors.black87);

      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
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
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_rounded, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                    'Time-Locked Message',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
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
        ),
      );
    }

    // Check if voice message
    if (message.isVoice) {
      final bubbleColor = isMe
          ? theme.primaryColor
          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0));
      final textColor = isMe ? Colors.white : (isDark ? Colors.white : Colors.black87);
      
      final bool isPlaying = _isPlayingMap[message.id] ?? false;
      final bool isExpanded = _isTranscriptExpandedMap[message.id] ?? false;

      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                            size: 32,
                            color: isMe ? Colors.white : theme.primaryColor,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setState(() {
                              _isPlayingMap[message.id] = !isPlaying;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        // Mock wave lines
                        Expanded(
                          child: SizedBox(
                            height: 24,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: _waveHeights.map((h) {
                                return Container(
                                  width: 2.5,
                                  height: h,
                                  decoration: BoxDecoration(
                                    color: (isMe ? Colors.white : theme.primaryColor).withValues(alpha: isPlaying ? 0.9 : 0.4),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isPlaying ? '0:01' : '0:${message.voiceDuration?.toString().padLeft(2, '0') ?? '03'}',
                          style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _isTranscriptExpandedMap[message.id] = !isExpanded;
                            });
                          },
                          child: Row(
                            children: [
                              Icon(
                                isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: isMe ? Colors.white70 : (isDark ? Colors.white70 : Colors.black54),
                              ),
                              Text(
                                'Whisper Transcript',
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : (isDark ? Colors.white70 : Colors.black54),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatTime(message.timestamp),
                          style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 9),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isExpanded)
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

    String displayText = message.text;
    double emojiSize = 15;
    bool isSizedEmoji = false;

    if (displayText.startsWith('[size:')) {
      final match = RegExp(r'^\[size:(\w+)\](.*)').firstMatch(displayText);
      if (match != null) {
        final sizeType = match.group(1);
        final content = match.group(2) ?? '';
        displayText = content;
        isSizedEmoji = true;

        if (sizeType == 'small') {
          emojiSize = 16;
        } else if (sizeType == 'large') {
          emojiSize = 48;
        } else if (sizeType == 'xlarge') {
          emojiSize = 72;
        } else {
          emojiSize = 30; // medium
        }
      }
    }

    final bool isSingleEmoji = isSizedEmoji && displayText.trim().length <= 4;

    Color bubbleColor;
    if (isSingleEmoji) {
      bubbleColor = Colors.transparent;
    } else if (message.isVault) {
      bubbleColor = isMe
          ? const Color(0xFFF59E0B)
          : (isDark ? const Color(0xFF2C1B0F) : const Color(0xFFFEF3C7));
    } else {
      bubbleColor = isMe
          ? theme.primaryColor
          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0));
    }

    final textColor = isMe ? Colors.white : (isDark ? Colors.white : Colors.black87);

    // Compute remaining life for vault messages
    String? expiryLabel;
    if (message.expiresAt != null) {
      final remaining = message.expiresAt! - DateTime.now().millisecondsSinceEpoch;
      if (remaining > 0) {
        final secs = (remaining / 1000).ceil();
        expiryLabel = secs >= 60 ? '${(secs / 60).ceil()}m' : '${secs}s';
      }
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: isSingleEmoji ? const EdgeInsets.symmetric(horizontal: 4, vertical: 4) : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 20),
          ),
          boxShadow: isSingleEmoji ? [] : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              displayText,
              style: TextStyle(
                color: isSingleEmoji ? Colors.white : textColor, 
                fontSize: isSingleEmoji ? emojiSize : 15, 
                height: 1.4
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
                  Icon(Icons.timer_outlined, size: 10, color: isMe ? Colors.white60 : Colors.amber),
                  const SizedBox(width: 2),
                  Text(expiryLabel,
                      style: TextStyle(
                          fontSize: 9,
                          color: isMe ? Colors.white60 : Colors.amber,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                ],
                Text(
                  _formatTime(message.timestamp),
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
                        : (message.isRead ? Icons.done_all_rounded : Icons.done_rounded),
                    size: 12,
                    color: Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionPill(MessageData message, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: message.reactions.entries.map((entry) {
          final meta = _kReactions.firstWhere(
            (r) => r['key'] == entry.key,
            orElse: () => {'icon': Icons.circle, 'label': ''},
          );
          return GestureDetector(
            onTap: () async {
              await MessageStorageService()
                  .saveReaction(widget.chatData.username, message.id, entry.key);
              final updated = await MessageStorageService().getMessages(widget.chatData.username);
              if (mounted) {
                setState(() {
                  _messages.clear();
                  _messages.addAll(updated);
                });
              }
            },
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

  Widget _buildInputBar(ThemeData theme) {
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
              _isSecureKeyboardActive ? Icons.shield_rounded : Icons.shield_outlined,
              color: _isSecureKeyboardActive ? const Color(0xFF10B981) : theme.primaryColor,
            ),
            onPressed: () {
              setState(() {
                _isSecureKeyboardActive = !_isSecureKeyboardActive;
                if (_isSecureKeyboardActive) {
                  FocusScope.of(context).unfocus();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.sentiment_satisfied_alt_rounded),
            color: theme.primaryColor,
            onPressed: () {
              setState(() {
                _isSecureKeyboardActive = true;
                FocusScope.of(context).unfocus();
              });
            },
          ),
          IconButton(
            icon: Icon(
              _isRecordingVoice ? Icons.mic_rounded : Icons.mic_none_rounded,
              color: _isRecordingVoice ? Colors.redAccent : theme.primaryColor,
            ),
            onPressed: () async {
              if (_isRecordingVoice) {
                _stopVoiceRecordingAndSend();
              } else {
                final granted = await _requestAudioPermission(context);
                if (granted && mounted) {
                  _startVoiceRecording();
                }
              }
            },
          ),
          Expanded(
            child: _isRecordingVoice
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          'Recording... 0:${_recordingDuration.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: _RecordingWaveform(),
                        ),
                      ],
                    ),
                  )
                : TextField(
                    controller: _messageController,
                    readOnly: _isSecureKeyboardActive,
                    decoration: InputDecoration(
                      hintText: _isVaultMode ? 'Type ephemeral message...' : 'Type secure message...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      fillColor: Colors.transparent,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
          ),
          GestureDetector(
            onLongPress: () {
              if (!_isRecordingVoice) {
                _showTimeLockSelector();
              }
            },
            child: IconButton(
              icon: Icon(
                _activeTimeLockDelayMs != null ? Icons.lock_clock_rounded : Icons.send_rounded,
              ),
              color: _activeTimeLockDelayMs != null
                  ? Colors.orange
                  : (_isVaultMode ? const Color(0xFFF59E0B) : theme.primaryColor),
              onPressed: () {
                if (_isRecordingVoice) {
                  _stopVoiceRecordingAndSend();
                } else {
                  _handleSendMessage();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showSafetyNumbersDialog() async {
    final secureBox = await Hive.openBox('secure_vault');
    final mySignPub = secureBox.get('identity_sign_public_key') as String?;
    final peerSignPub = secureBox.get('recipient_sign_pub_${widget.chatData.username}') as String?;

    if (!mounted) return;

    if (mySignPub == null || peerSignPub == null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Text('Safety Numbers', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Safety numbers cannot be computed because a secure handshake has not been fully completed yet. Please send or receive a message first.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: Color(0xFF6366F1))),
            ),
          ],
        ),
      );
      return;
    }

    final fingerprint = EncryptionService().deriveFingerprint(mySignPub, peerSignPub);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF13131B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.white10),
        ),
        title: const Row(
          children: [
            Icon(Icons.verified_user_rounded, color: Color(0xFF10B981)),
            SizedBox(width: 10),
            Text('Verify Safety Numbers', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Safety numbers verify that messages and calls with this contact are end-to-end encrypted with Double Ratchet. To verify, compare these numbers with their device.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.45),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                fingerprint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF10B981),
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // High-tech stylized mock QR code
            Container(
              width: 140,
              height: 140,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: CustomPaint(
                painter: _MockQrCodePainter(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white60)),
          ),
        ],
      ),
    );
  }
}

class _RecordingWaveform extends StatefulWidget {
  const _RecordingWaveform();

  @override
  State<_RecordingWaveform> createState() => _RecordingWaveformState();
}

class _RecordingWaveformState extends State<_RecordingWaveform> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _heights = List.generate(25, (index) => 4.0 + (index % 5) * 4.0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat(reverse: true);
    
    _timer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
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

class ChatWallpaperPainter extends CustomPainter {
  final Color color;
  ChatWallpaperPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw repeating pattern of bubbles and locks
    const step = 80.0;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        // Draw speech bubble contour
        final rect = Rect.fromLTWH(x + 10, y + 10, 24, 16);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
        final path = Path()
          ..moveTo(x + 12, y + 26)
          ..lineTo(x + 8, y + 28)
          ..lineTo(x + 14, y + 26);
        canvas.drawPath(path, paint);

        // Draw tiny lock
        canvas.drawCircle(Offset(x + 45, y + 35), 3, paint);
        canvas.drawRect(Rect.fromLTWH(x + 43, y + 35, 4, 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MockQrCodePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    // Draw the three corner squares of a QR code
    final squareSize = size.width * 0.25;
    
    // Top-left
    canvas.drawRect(Rect.fromLTWH(0, 0, squareSize, squareSize), paint);
    canvas.drawRect(Rect.fromLTWH(squareSize * 0.2, squareSize * 0.2, squareSize * 0.6, squareSize * 0.6), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(squareSize * 0.35, squareSize * 0.35, squareSize * 0.3, squareSize * 0.3), paint);

    // Top-right
    canvas.drawRect(Rect.fromLTWH(size.width - squareSize, 0, squareSize, squareSize), paint);
    canvas.drawRect(Rect.fromLTWH(size.width - squareSize + squareSize * 0.2, squareSize * 0.2, squareSize * 0.6, squareSize * 0.6), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(size.width - squareSize + squareSize * 0.35, squareSize * 0.35, squareSize * 0.3, squareSize * 0.3), paint);

    // Bottom-left
    canvas.drawRect(Rect.fromLTWH(0, size.height - squareSize, squareSize, squareSize), paint);
    canvas.drawRect(Rect.fromLTWH(squareSize * 0.2, size.height - squareSize + squareSize * 0.2, squareSize * 0.6, squareSize * 0.6), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(squareSize * 0.35, size.height - squareSize + squareSize * 0.35, squareSize * 0.3, squareSize * 0.3), paint);

    // Draw some random smaller mock blocks in the center and bottom-right
    final random = [
      Rect.fromLTWH(size.width * 0.4, size.height * 0.1, 8, 8),
      Rect.fromLTWH(size.width * 0.5, size.height * 0.2, 12, 6),
      Rect.fromLTWH(size.width * 0.45, size.height * 0.35, 6, 12),
      Rect.fromLTWH(size.width * 0.6, size.height * 0.4, 8, 8),
      Rect.fromLTWH(size.width * 0.35, size.height * 0.6, 10, 10),
      Rect.fromLTWH(size.width * 0.7, size.height * 0.6, 6, 16),
      Rect.fromLTWH(size.width * 0.6, size.height * 0.75, 12, 12),
      Rect.fromLTWH(size.width * 0.75, size.height * 0.75, 8, 8),
      Rect.fromLTWH(size.width * 0.8, size.height * 0.45, 12, 8),
      Rect.fromLTWH(size.width * 0.4, size.height * 0.8, 14, 6),
    ];

    for (final r in random) {
      canvas.drawRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
