import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:hive/hive.dart';
import 'auth_service.dart';
import 'encryption_service.dart';

class P2PPeer {
  final String username;
  final String ipAddress;
  DateTime lastSeen;
  final String? publicKey;

  P2PPeer({
    required this.username,
    required this.ipAddress,
    required this.lastSeen,
    this.publicKey,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is P2PPeer &&
          runtimeType == other.runtimeType &&
          ipAddress == other.ipAddress;

  @override
  int get hashCode => ipAddress.hashCode;
}

class P2PMessage {
  final String sender;
  final String peerUsername;
  final String text;
  final DateTime time;
  final bool isMe;

  P2PMessage({
    required this.sender,
    required this.peerUsername,
    required this.text,
    required this.time,
    required this.isMe,
  });
}

class P2PMeshService {
  static final P2PMeshService _instance = P2PMeshService._internal();
  factory P2PMeshService() => _instance;
  P2PMeshService._internal();

  RawDatagramSocket? _udpSocket;
  ServerSocket? _tcpServer;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;

  final List<P2PPeer> _discoveredPeers = [];
  final List<P2PMessage> _messageHistory = [];

  final _peersController = StreamController<List<P2PPeer>>.broadcast();
  final _messageController = StreamController<List<P2PMessage>>.broadcast();

  // Local key pair caches
  String? _myPublicKey;
  SimpleKeyPair? _myKeyPair;

  // Getters
  Stream<List<P2PPeer>> get peersStream => _peersController.stream;
  Stream<List<P2PMessage>> get messageStream => _messageController.stream;
  List<P2PPeer> get discoveredPeers => List.unmodifiable(_discoveredPeers);
  List<P2PMessage> get messageHistory => List.unmodifiable(_messageHistory);

  bool _isListening = false;

  /// Start P2P Discovery (UDP) and Messaging Server (TCP)
  Future<void> startP2P() async {
    if (_isListening) return;
    _isListening = true;

    // Load local E2E key pair once from Hive
    try {
      final secureBox = await Hive.openBox('secure_vault');
      _myPublicKey = secureBox.get('public_key') as String?;
      final privKey = secureBox.get('private_key') as String?;
      if (_myPublicKey != null && privKey != null) {
        _myKeyPair = await EncryptionService().importKeyPair(_myPublicKey!, privKey);
      }
    } catch (_) {
      // Fail silently
    }

    await _initUdpDiscovery();
    await _initTcpServer();

    // Start periodic heartbeats (every 4 seconds)
    _broadcastTimer = Timer.periodic(const Duration(seconds: 4), (_) => _broadcastPresence());

    // Clean up inactive peers (older than 12 seconds)
    _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) => _cleanupInactivePeers());
  }

  /// Stop all sockets and timers
  void stopP2P() {
    _isListening = false;
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    
    _udpSocket?.close();
    _udpSocket = null;
    
    _tcpServer?.close();
    _tcpServer = null;

    _discoveredPeers.clear();
    _peersController.add([]);
  }

  /// Initialize UDP socket for discovery
  Future<void> _initUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 4545);
      _udpSocket!.broadcastEnabled = true;

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            final payload = utf8.decode(datagram.data);
            _handleDiscoveryMessage(payload, datagram.address.address);
          }
        }
      });
    } catch (_) {
      // Fail silently
    }
  }

  /// Broadcast presence to the local network broadcast address
  void _broadcastPresence() {
    if (_udpSocket == null) return;
    try {
      final username = AuthService().username ?? "Anonymous";
      final keyString = _myPublicKey ?? "";
      final message = 'DISCOVER:$username:$keyString';
      final data = utf8.encode(message);

      // Broadcast to standard IPv4 local subnet broadcast address
      _udpSocket!.send(data, InternetAddress('255.255.255.255'), 4545);
    } catch (_) {
      // Fail silently
    }
  }

  /// Handle incoming UDP presence heartbeats
  void _handleDiscoveryMessage(String payload, String senderIp) {
    if (!payload.startsWith('DISCOVER:')) return;

    final parts = payload.substring(9).split(':');
    if (parts.isEmpty) return;
    final peerUsername = parts[0].trim();
    final peerPublicKey = parts.length > 1 ? parts[1].trim() : null;
    final myUsername = AuthService().username ?? "Anonymous";

    // Ignore own broadcast
    if (peerUsername == myUsername) return;

    final peer = P2PPeer(
      username: peerUsername,
      ipAddress: senderIp,
      lastSeen: DateTime.now(),
      publicKey: peerPublicKey,
    );

    final idx = _discoveredPeers.indexOf(peer);
    if (idx != -1) {
      _discoveredPeers[idx].lastSeen = DateTime.now();
      if (peerPublicKey != null) {
        _discoveredPeers[idx] = peer;
      }
    } else {
      _discoveredPeers.add(peer);
    }

    _peersController.add(List.from(_discoveredPeers));
  }

  /// Remove peers that haven't sent a heartbeat recently
  void _cleanupInactivePeers() {
    final now = DateTime.now();
    _discoveredPeers.removeWhere((peer) => now.difference(peer.lastSeen).inSeconds > 12);
    _peersController.add(List.from(_discoveredPeers));
  }

  /// Initialize TCP socket server for message receiving
  Future<void> _initTcpServer() async {
    try {
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, 4546);
      _tcpServer!.listen((Socket clientSocket) {
        clientSocket.listen((data) async {
          try {
            final messageStr = utf8.decode(data);
            final payload = jsonDecode(messageStr) as Map<String, dynamic>;

            final sender = payload['sender'] as String;
            final senderPublicKey = payload['senderPublicKey'] as String?;
            final isEncrypted = payload['isEncrypted'] as bool? ?? false;
            var text = payload['text'] as String;

            if (isEncrypted && _myKeyPair != null && senderPublicKey != null && senderPublicKey.isNotEmpty) {
              try {
                final sharedSecret = await EncryptionService().deriveSharedSecret(
                  myKeyPair: _myKeyPair!,
                  recipientPublicBase64: senderPublicKey,
                );
                text = await EncryptionService().decryptMessage(
                  encryptedPacketBase64: text,
                  secretKey: sharedSecret,
                );
              } catch (_) {
                text = '[Decryption Failed: Key mismatch or tampered packet]';
              }
            }

            final msg = P2PMessage(
              sender: sender,
              peerUsername: sender,
              text: text,
              time: DateTime.now(),
              isMe: false,
            );

            _messageHistory.add(msg);
            _messageController.add(List.from(_messageHistory));
          } catch (_) {
            // Bad payload format
          }
        });
      });
    } catch (_) {
      // Fail silently
    }
  }

  /// Send message directly to a peer over TCP with E2E Encryption
  Future<bool> sendP2PMessage(P2PPeer peer, String text) async {
    try {
      final socket = await Socket.connect(peer.ipAddress, 4546, timeout: const Duration(seconds: 3));
      final myUsername = AuthService().username ?? "Anonymous";

      String payloadText = text;
      bool isEncrypted = false;

      if (_myKeyPair != null && peer.publicKey != null && peer.publicKey!.isNotEmpty) {
        try {
          final sharedSecret = await EncryptionService().deriveSharedSecret(
            myKeyPair: _myKeyPair!,
            recipientPublicBase64: peer.publicKey!,
          );
          payloadText = await EncryptionService().encryptMessage(
            plaintext: text,
            secretKey: sharedSecret,
          );
          isEncrypted = true;
        } catch (_) {
          // Fall back to plaintext if key agreement fails
        }
      }

      final payload = jsonEncode({
        'sender': myUsername,
        'senderPublicKey': _myPublicKey ?? '',
        'text': payloadText,
        'isEncrypted': isEncrypted,
      });

      socket.write(payload);
      await socket.flush();
      await socket.close();

      // Record in local P2P history
      final msg = P2PMessage(
        sender: myUsername,
        peerUsername: peer.username,
        text: text,
        time: DateTime.now(),
        isMe: true,
      );

      _messageHistory.add(msg);
      _messageController.add(List.from(_messageHistory));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get message stream filtered by peer username
  Stream<List<P2PMessage>> getPeerMessagesStream(String peerUsername) {
    return _messageController.stream.map((messages) =>
        messages.where((m) => m.peerUsername == peerUsername).toList());
  }

  /// Get message history filtered by peer username
  List<P2PMessage> getPeerMessageHistory(String peerUsername) {
    return _messageHistory.where((m) => m.peerUsername == peerUsername).toList();
  }

  /// Clear the local offline message history
  void clearHistory() {
    _messageHistory.clear();
    _messageController.add([]);
  }
}
