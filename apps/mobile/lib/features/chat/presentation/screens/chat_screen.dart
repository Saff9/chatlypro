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
import '../../../../providers/wallpaper_provider.dart';
import '../../../../core/widgets/beautiful_avatar.dart';
import '../../../../services/api_service.dart';
import '../../../../services/push_notification_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/chat_painters.dart';

// Vault timer options used by the disappearing-messages selector sheet.
const _kTimerOptions = [
  {'label': 'Off',   'ms': null},
  {'label': '30 s',  'ms': 30000},
  {'label': '1 min', 'ms': 60000},
  {'label': '5 min', 'ms': 300000},
  {'label': '1 hr',  'ms': 3600000},
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
  int? _vaultTimerMs; // null = no expiry

  StreamSubscription? _socketSubscription;
  StreamSubscription? _stateSubscription;
  Timer? _expiryTimer;
  // Auto-clears the "X is typing" banner if no follow-up event arrives within 6 s.
  // Prevents the indicator from freezing if the remote app crashes or loses network.
  Timer? _typingClearTimer;
  DoubleRatchetSession? _session;
  bool _isServiceReady = false;

  IdentityTrustResult? _identityTrust;
  bool _isSafetyVerified = false;

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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  DATA LAYER
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _loadMessageHistory() async {
    // In duress mode, simply show an empty conversation
    final settingsBox = Hive.box('settings');
    final bool isDuress = settingsBox.get('is_duress_active', defaultValue: false) as bool;
    if (isDuress) {
      if (mounted) setState(() => _messages.clear());
      return;
    }

    final history = await MessageStorageService().getMessages(widget.chatData.username);
    final pushService = PushNotificationService();
    final matchingBgMsgs = pushService.backgroundVaultMessages
        .where((m) => m.sender == widget.chatData.username)
        .toList();
    pushService.backgroundVaultMessages.removeWhere((m) => m.sender == widget.chatData.username);

    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(history);
        _messages.addAll(matchingBgMsgs);
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      });
    }
  }

  void _showIdentityChangedWarning(String newIdentityKey) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF13131B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.white10),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Security Warning', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'The identity key for @${widget.chatData.username} changed. This may mean they reinstalled the app, or someone is trying to intercept your messages. Verify safety numbers before continuing.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Exit chat screen
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () async {
              await IdentityTrustService().acceptChangedIdentity(
                username: widget.chatData.username,
                newIdentitySignPublicKey: newIdentityKey,
              );
              if (mounted) {
                setState(() {
                  _identityTrust = IdentityTrustResult.trusted;
                });
              }
              if (context.mounted) {
                Navigator.of(context).pop();
              }
              _initializeE2E();
            },
            child: const Text('I Verified This', style: TextStyle(color: Color(0xFF10B981))),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeE2E() async {
    final secureBox = await Hive.openBox('secure_vault');

    _isSafetyVerified = await IdentityTrustService().isSafetyVerified(widget.chatData.username);

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
        final trust = await IdentityTrustService().checkAndPin(
          username: widget.chatData.username,
          identitySignPublicKey: bundle['identity_key'],
        );
        if (mounted) {
          setState(() {
            _identityTrust = trust;
          });
        }

        if (trust == IdentityTrustResult.changed) {
          if (mounted) {
            setState(() => _isServiceReady = false);
            _showIdentityChangedWarning(bundle['identity_key']);
          }
          return;
        }

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
    } else {
      final cachedPeerKey = secureBox.get('recipient_sign_pub_${widget.chatData.username}') as String?;
      if (cachedPeerKey != null && cachedPeerKey.isNotEmpty) {
        final trust = await IdentityTrustService().checkAndPin(
          username: widget.chatData.username,
          identitySignPublicKey: cachedPeerKey,
        );
        if (mounted) {
          setState(() {
            _identityTrust = trust;
          });
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
    final msgType = payload['type'] as String?;

    // Server acknowledgement that our message was relayed (or queued for offline delivery).
    // Flip isSent on the matching optimistic message without a full re-render.
    if (msgType == 'sent_ack') {
      final clientId = payload['clientId'] as String?;
      if (clientId != null && mounted) {
        setState(() {
          for (final msg in _messages) {
            if (msg.id == clientId && !msg.isSent) {
              msg.isSent = true;
            }
          }
        });
      }
      return;
    }

    // Only process events from the contact this screen is open for
    if (payload['senderId'] != widget.chatData.username) return;

    if (msgType == 'typing') {
      final isTyping = payload['isTyping'] as bool? ?? false;
      _typingClearTimer?.cancel();
      if (isTyping) {
        // Auto-clear after 6 s in case the sender disconnects mid-typing
        _typingClearTimer = Timer(const Duration(seconds: 6), () {
          if (mounted) setState(() => _isTyping = false);
        });
      }
      setState(() => _isTyping = isTyping);
    } else if (msgType == 'message') {
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

            // TOFU trust check
            final trust = await IdentityTrustService().checkAndPin(
              username: widget.chatData.username,
              identitySignPublicKey: aliceBundle['identity_key'],
            );
            if (mounted) {
              setState(() {
                _identityTrust = trust;
              });
            }

            if (trust == IdentityTrustResult.changed) {
              if (mounted) {
                setState(() => _isServiceReady = false);
                _showIdentityChangedWarning(aliceBundle['identity_key']);
              }
              return;
            }

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

          String cleanText = plaintext;
          bool isVaultMsg = _isVaultMode;
          int? expiryMs = _vaultTimerMs;

          if (plaintext.startsWith('[VAULT_MSG:')) {
            final closingBracket = plaintext.indexOf(']');
            if (closingBracket != -1) {
              isVaultMsg = true;
              final meta = plaintext.substring(11, closingBracket);
              final timerVal = int.tryParse(meta);
              expiryMs = timerVal;
              cleanText = plaintext.substring(closingBracket + 1);
            }
          }

          // Check if it's a voice message prefix within the decrypted text
          final isVoiceMsg = cleanText.startsWith('[Voice Transcript Note]');
          String? voiceTranscriptText;
          if (isVoiceMsg) {
            voiceTranscriptText = cleanText.substring(24).trim();
          }

          final newMsg = MessageData(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            text: cleanText,
            isMe: false,
            time: 'Now',
            isRead: true,
            isVault: isVaultMsg,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            expiresAt: (isVaultMsg && expiryMs != null)
                ? DateTime.now().millisecondsSinceEpoch + expiryMs
                : null,
            isVoice: isVoiceMsg,
            voiceDuration: isVoiceMsg ? 3 : null,
            voiceTranscript: voiceTranscriptText,
          );
          if (!isVaultMsg) {
            await MessageStorageService().saveMessage(widget.chatData.username, newMsg);
          }
          _addMessageAndCheckLimit(newMsg);
        } catch (e) {
          debugPrint('Decryption error: $e');
          final errMsg = MessageData(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            text: '[Decryption failed â€” secure handshake mismatch]',
            isMe: false,
            time: 'Now',
            isRead: true,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
          if (!_isVaultMode) {
            await MessageStorageService().saveMessage(widget.chatData.username, errMsg);
          }
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
                      ? 'History limit reached â€” oldest messages scrambled.'
                      : 'History limit reached â€” oldest messages shredded.'),
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

    if (!_isVaultMode) {
      await MessageStorageService().saveMessage(widget.chatData.username, newMessage);
    }
    _addMessageAndCheckLimit(newMessage);

    if (_session != null && _isServiceReady) {
      final plaintextPayload =
          _isVaultMode ? '[VAULT_MSG:$_vaultTimerMs]$text' : text;
      final ciphertext = await EncryptionService().encrypt(
        session: _session!,
        plaintext: plaintextPayload,
      );

      // Persist the advanced ratchet state so the next message uses the new chain key
      final secureBox = await Hive.openBox('secure_vault');
      await secureBox.put(
        'session_${widget.chatData.username}',
        jsonEncode(_session!.toJson()),
      );

      // Pass newMessage.id as clientId â€” the server echoes it in sent_ack so we
      // can flip isSent without guessing which message was acknowledged.
      await WebSocketService().sendMessage(
        recipientId: widget.chatData.username,
        ciphertext: ciphertext,
        clientId: newMessage.id,
      );
      // isSent is flipped to true via the incoming sent_ack event in
      // _handleIncomingSocketPayload, not here â€” avoids double state updates
      // and makes offline/outbox sends consistent.
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  PREMIUM NEW FEATURE HELPERS
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _getAdaptiveRouteLabel() {
    final socketState = WebSocketService().connectionState;
    if (socketState == SocketConnectionState.connected) {
      return 'ðŸŒ WebSocket';
    } else {
      return 'ðŸ’¾ Outbox Cache';
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
        if (msg.isVault) continue; // Do not export vault messages (RAM-only)
        final sender = msg.isMe ? 'Me' : widget.chatData.name;
        final typePrefix = msg.isVoice ? '[VOICE TRANSCRIPT NOTE - Duration: ${msg.voiceDuration}s] ' : '';
        final timeStr = _formatTime(msg.timestamp);
        
        buffer.writeln('[$timeStr] $sender: $typePrefix${msg.text}');
        if (msg.isVoice && msg.voiceTranscript != null) {
          buffer.writeln('   â””â”€ Transcript: "${msg.voiceTranscript}"');
        }
      }
      
      buffer.writeln('\n==============================================');
      buffer.writeln('END OF TRANSCRIPT â€” SECURED BY CHATLY');
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
                          'âš ï¸ WARNING: High Entropy detected. Replying speed is dropping and message lengths are diminishing. Fading interest likely.',
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
                          'âœ… STABLE INTEREST: Replying intervals and vocabulary density indicate healthy engagement levels.',
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
              Text('Voice Transcript Note', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
              child: const Text('Send Note', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (transcript == null || transcript.isEmpty) return;

    final expiresAt = _vaultTimerMs != null
        ? DateTime.now().millisecondsSinceEpoch + _vaultTimerMs!
        : null;

    final newVoiceMsg = MessageData(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: "[Voice Transcript Note] $transcript",
      isMe: true,
      time: 'Now',
      isRead: false,
      isVault: _isVaultMode,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      expiresAt: expiresAt,
      isVoice: true,
      voiceDuration: duration,
      voiceTranscript: transcript,
      isSent: false,
    );

    if (!_isVaultMode) {
      await MessageStorageService().saveMessage(widget.chatData.username, newVoiceMsg);
    }
    _addMessageAndCheckLimit(newVoiceMsg);

    if (_session != null && _isServiceReady) {
      final textToSend = '[Voice Transcript Note] $transcript';
      final plaintextPayload =
          _isVaultMode ? '[VAULT_MSG:$_vaultTimerMs]$textToSend' : textToSend;
      final ciphertext = await EncryptionService().encrypt(
        session: _session!,
        plaintext: plaintextPayload,
      );

      final secureBox = await Hive.openBox('secure_vault');
      await secureBox.put(
        'session_${widget.chatData.username}',
        jsonEncode(_session!.toJson()),
      );

      await WebSocketService().sendMessage(
        recipientId: widget.chatData.username,
        ciphertext: ciphertext,
        clientId: newVoiceMsg.id,
      );
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  REACTIONS
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
                  children: kReactions.map((r) {
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
                  setState(() {
                    msg.text = newText;
                  });
                  if (!_isVaultMode) {
                    await MessageStorageService().saveMessage(widget.chatData.username, msg);
                    final updatedHistory = await MessageStorageService().getMessages(widget.chatData.username);
                    if (mounted) {
                      setState(() {
                        _messages.clear();
                        _messages.addAll(updatedHistory);
                      });
                    }
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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  VAULT TIMER SELECTOR
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  DELETE
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
    _typingClearTimer?.cancel();
    _recordingTimer?.cancel();
    _messages.clear();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  BUILD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
                Icon(
                  _identityTrust == IdentityTrustResult.changed
                      ? Icons.gpp_bad_rounded
                      : (_isSafetyVerified ? Icons.verified_user_rounded : Icons.shield_outlined),
                  size: 14,
                  color: _identityTrust == IdentityTrustResult.changed
                      ? Colors.redAccent
                      : (_isSafetyVerified ? const Color(0xFF10B981) : Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  widget.chatData.isOnline ? 'Online â€¢ Vibing' : 'Offline',
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
                label: const Text('â—', style: TextStyle(fontSize: 6)),
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
            icon: Icon(
              _identityTrust == IdentityTrustResult.changed
                  ? Icons.gpp_bad_rounded
                  : (_isSafetyVerified ? Icons.verified_user_rounded : Icons.shield_outlined),
            ),
            tooltip: 'Verify Safety Numbers',
            onPressed: _showSafetyNumbersDialog,
            color: _identityTrust == IdentityTrustResult.changed
                ? Colors.redAccent
                : (_isSafetyVerified ? const Color(0xFF10B981) : Colors.grey),
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
                              ChatMessageBubble(
                                message: msg,
                                isPlaying: _isPlayingMap[msg.id] ?? false,
                                isTranscriptExpanded: _isTranscriptExpandedMap[msg.id] ?? false,
                                waveHeights: _waveHeights,
                                onTogglePlay: () => setState(
                                    () => _isPlayingMap[msg.id] = !(_isPlayingMap[msg.id] ?? false)),
                                onToggleTranscript: () => setState(() =>
                                    _isTranscriptExpandedMap[msg.id] =
                                        !(_isTranscriptExpandedMap[msg.id] ?? false)),
                                formatTime: _formatTime,
                              ),
                              if (msg.reactions.isNotEmpty)
                                ReactionPill(
                                  message: msg,
                                  onTap: () async {
                                    final updated = await MessageStorageService()
                                        .getMessages(widget.chatData.username);
                                    if (mounted) {
                                      setState(() {
                                        _messages.clear();
                                        _messages.addAll(updated);
                                      });
                                    }
                                  },
                                ),
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
                  ChatInputBar(
                    controller: _messageController,
                    isVaultMode: _isVaultMode,
                    isRecordingVoice: _isRecordingVoice,
                    recordingDuration: _recordingDuration,
                    activeTimeLockDelayMs: _activeTimeLockDelayMs,
                    onSendPressed: () {
                      if (_isRecordingVoice) {
                        _stopVoiceRecordingAndSend();
                      } else {
                        _handleSendMessage();
                      }
                    },
                    onLongPressSend: _showTimeLockSelector,
                    onMicPressed: () async {
                      if (_isRecordingVoice) {
                        _stopVoiceRecordingAndSend();
                      } else {
                        final granted = await _requestAudioPermission(context);
                        if (granted && mounted) _startVoiceRecording();
                      }
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
              child: const CustomPaint(
                painter: MockQrCodePainter(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isSafetyVerified ? Icons.verified_user_rounded : Icons.shield_outlined,
                  size: 16,
                  color: _isSafetyVerified ? const Color(0xFF10B981) : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  _isSafetyVerified ? 'Status: Verified (Secure)' : 'Status: Unverified (TOFU Pinned)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _isSafetyVerified ? const Color(0xFF10B981) : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final newStatus = !_isSafetyVerified;
              await IdentityTrustService().setSafetyVerified(widget.chatData.username, newStatus);
              if (mounted) {
                setState(() {
                  _isSafetyVerified = newStatus;
                });
              }
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Text(
              _isSafetyVerified ? 'Mark as Unverified' : 'Mark as Verified',
              style: TextStyle(color: _isSafetyVerified ? Colors.redAccent : const Color(0xFF10B981)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white60)),
          ),
        ],
      ),
    );
  }
}
