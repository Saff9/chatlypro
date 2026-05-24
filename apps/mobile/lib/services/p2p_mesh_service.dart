import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'auth_service.dart';

class P2PPeer {
  final String username;
  final String ipAddress;
  DateTime lastSeen;

  P2PPeer({
    required this.username,
    required this.ipAddress,
    required this.lastSeen,
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
  final String text;
  final DateTime time;
  final bool isMe;

  P2PMessage({
    required this.sender,
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
      // Fail silently (e.g. port already bound)
    }
  }

  /// Broadcast presence to the local network broadcast address
  void _broadcastPresence() {
    if (_udpSocket == null) return;
    try {
      final username = AuthService().username ?? "Anonymous";
      final message = 'DISCOVER:$username';
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

    final peerUsername = payload.substring(9).trim();
    final myUsername = AuthService().username ?? "Anonymous";

    // Ignore own broadcast
    if (peerUsername == myUsername) return;

    final peer = P2PPeer(
      username: peerUsername,
      ipAddress: senderIp,
      lastSeen: DateTime.now(),
    );

    final idx = _discoveredPeers.indexOf(peer);
    if (idx != -1) {
      _discoveredPeers[idx].lastSeen = DateTime.now();
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
        clientSocket.listen((data) {
          try {
            final messageStr = utf8.decode(data);
            final payload = jsonDecode(messageStr) as Map<String, dynamic>;

            final sender = payload['sender'] as String;
            final text = payload['text'] as String;

            final msg = P2PMessage(
              sender: sender,
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

  /// Send message directly to a peer's IP address over TCP
  Future<bool> sendP2PMessage(String peerIp, String text) async {
    try {
      final socket = await Socket.connect(peerIp, 4546, timeout: const Duration(seconds: 3));
      final myUsername = AuthService().username ?? "Anonymous";

      final payload = jsonEncode({
        'sender': myUsername,
        'text': text,
      });

      socket.write(payload);
      await socket.flush();
      await socket.close();

      // Record in local P2P history
      final msg = P2PMessage(
        sender: myUsername,
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

  /// Clear the local offline message history
  void clearHistory() {
    _messageHistory.clear();
    _messageController.add([]);
  }
}
