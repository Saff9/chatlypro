import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'api_service.dart';

enum SocketConnectionState { disconnected, connecting, connected, reconnecting }

/// Singleton WebSocket service that manages the persistent connection to the
/// Chatly relay server.
///
/// Responsibilities:
///   - Authenticate via short-lived single-use ticket (falls back to JWT in dev)
///   - Reconnect automatically with exponential back-off (1s → 2s → 4s … 30s cap)
///   - Adapt keep-alive ping frequency to network type (15 s on Wi-Fi, 60 s on mobile)
///   - Queue outbound messages in a local Hive outbox when offline; flush on reconnect
///   - Expose [messageStream] for any subscriber (chat screen, connection provider, …)
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal() {
    _monitorNetworkConnectivity();
  }

  WebSocketChannel? _channel;
  SocketConnectionState _connectionState = SocketConnectionState.disconnected;

  final StreamController<Map<String, dynamic>> _messageStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<SocketConnectionState> _stateStreamController =
      StreamController<SocketConnectionState>.broadcast();

  String? _currentToken;
  String? _currentUrl;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  // Adaptive ping: 15 s on Wi-Fi/Ethernet, 60 s on cellular to save data
  int _pingIntervalSeconds = 15;

  // Per-recipient typing throttle — prevents flooding on slow links
  // Key: recipientId, Value: time of last "isTyping: true" event sent
  final Map<String, DateTime> _lastTypingSentMap = {};

  // Public API
  Stream<Map<String, dynamic>> get messageStream => _messageStreamController.stream;
  Stream<SocketConnectionState> get stateStream => _stateStreamController.stream;
  SocketConnectionState get connectionState => _connectionState;

  void _updateState(SocketConnectionState newState) {
    _connectionState = newState;
    _stateStreamController.add(newState);

    if (newState == SocketConnectionState.connected) {
      _startAdaptivePing();
      _flushOutboxQueue();
    } else {
      _stopPingTimer();
    }

    if (kDebugMode) debugPrint('[WS] State → $newState');
  }

  /// Connect (or reconnect) to the WebSocket relay.
  ///
  /// Fetches a short-lived single-use ticket first. In production this is the
  /// only accepted auth method; in dev the raw JWT is allowed as fallback.
  void connect({required String url, required String token}) async {
    _currentToken = token;
    _currentUrl = url;
    _shouldReconnect = true;

    if (_connectionState == SocketConnectionState.connected ||
        _connectionState == SocketConnectionState.connecting) {
      return;
    }

    _updateState(SocketConnectionState.connecting);

    final ticket = await ApiService().getWsTicket();
    final String query =
        ticket != null ? '?ticket=$ticket' : '?token=$token';
    final wsUri = Uri.parse('$url/ws/chat$query');

    try {
      _channel = IOWebSocketChannel.connect(
        wsUri,
        headers: {'Authorization': 'Bearer $token'},
      );

      _channel!.stream.listen(
        (message) {
          _reconnectAttempts = 0;
          _updateState(SocketConnectionState.connected);
          try {
            final Map<String, dynamic> parsed = jsonDecode(message as String);
            _messageStreamController.add(parsed);
          } catch (e) {
            if (kDebugMode) debugPrint('[WS] Parse error: $e');
          }
        },
        onDone: () {
          _updateState(SocketConnectionState.disconnected);
          _handleDisconnect();
        },
        onError: (error) {
          if (kDebugMode) debugPrint('[WS] Stream error: $error');
          _updateState(SocketConnectionState.disconnected);
          _handleDisconnect();
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[WS] Connection failed: $e');
      _updateState(SocketConnectionState.disconnected);
      _handleDisconnect();
    }
  }

  /// Send an encrypted 1-to-1 message.
  ///
  /// If offline, the message is persisted in the Hive outbox and this method
  /// returns `false`. The outbox is automatically flushed when the connection
  /// is restored. [clientId] is echoed back in the server's `sent_ack` event
  /// so the caller can flip [MessageData.isSent] reliably.
  Future<bool> sendMessage({
    required String recipientId,
    required String ciphertext,
    String? clientId,
  }) async {
    final outboxBox = await Hive.openBox('outbox');

    final payload = {
      'recipientId': recipientId,
      'ciphertext': ciphertext,
      'clientId': clientId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    if (_connectionState != SocketConnectionState.connected ||
        _channel == null) {
      final messageId = DateTime.now().microsecondsSinceEpoch.toString();
      await outboxBox.put(messageId, jsonEncode(payload));
      if (kDebugMode) debugPrint('[WS] Offline — message queued in outbox');
      return false;
    }

    try {
      _channel!.sink.add(jsonEncode({
        'type': 'message',
        'recipientId': recipientId,
        'ciphertext': ciphertext,
        if (clientId != null) 'clientId': clientId,
      }));
      return true;
    } catch (e) {
      final messageId = DateTime.now().microsecondsSinceEpoch.toString();
      await outboxBox.put(messageId, jsonEncode(payload));
      return false;
    }
  }

  /// Send an encrypted group message.
  Future<bool> sendGroupMessage({
    required String groupId,
    required String ciphertext,
  }) async {
    if (_connectionState != SocketConnectionState.connected ||
        _channel == null) {
      return false;
    }
    try {
      _channel!.sink.add(jsonEncode({
        'type': 'group_message',
        'groupId': groupId,
        'ciphertext': ciphertext,
      }));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Drain the local outbox, respecting the server's 120 msg/min rate limit.
  ///
  /// Inserts a 550 ms gap between each send (≈ 109 msg/min), leaving headroom
  /// for concurrent typing events and pings. Stops immediately if the
  /// connection drops mid-flush.
  Future<void> _flushOutboxQueue() async {
    final outboxBox = await Hive.openBox('outbox');
    if (outboxBox.isEmpty) return;

    if (kDebugMode) {
      debugPrint('[WS] Flushing ${outboxBox.length} queued messages…');
    }

    final keys = List<String>.from(outboxBox.keys);
    for (final key in keys) {
      if (_connectionState != SocketConnectionState.connected) break;

      final value = outboxBox.get(key);
      if (value != null) {
        try {
          final data = jsonDecode(value as String) as Map<String, dynamic>;
          _channel!.sink.add(jsonEncode({
            'type': 'message',
            'recipientId': data['recipientId'],
            'ciphertext': data['ciphertext'],
            if (data['clientId'] != null) 'clientId': data['clientId'],
          }));
          await outboxBox.delete(key);
          // Rate-limit: ~109 messages/min, safely under the 120 msg/min cap
          await Future<void>.delayed(const Duration(milliseconds: 550));
        } catch (e) {
          if (kDebugMode) debugPrint('[WS] Outbox flush error: $e');
        }
      }
    }
  }

  /// Send a typing indicator for [recipientId].
  ///
  /// "isTyping: true" events are throttled to once every 8 seconds **per
  /// recipient** to prevent network churn on slow links. "isTyping: false"
  /// events are always sent immediately to clear the indicator without delay.
  void sendTypingStatus({
    required String recipientId,
    required bool isTyping,
  }) {
    if (_connectionState != SocketConnectionState.connected ||
        _channel == null) {
      return;
    }

    if (isTyping) {
      final now = DateTime.now();
      final last = _lastTypingSentMap[recipientId];
      if (last != null && now.difference(last).inSeconds < 8) return;
      _lastTypingSentMap[recipientId] = now;
    }

    try {
      _channel!.sink.add(jsonEncode({
        'type': 'typing',
        'recipientId': recipientId,
        'isTyping': isTyping,
      }));
    } catch (e) {
      if (kDebugMode) debugPrint('[WS] Typing send error: $e');
    }
  }

  void _startAdaptivePing() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(
      Duration(seconds: _pingIntervalSeconds),
      (_) {
        if (_connectionState == SocketConnectionState.connected &&
            _channel != null) {
          try {
            _channel!.sink.add(jsonEncode({'type': 'ping'}));
          } catch (e) {
            if (kDebugMode) debugPrint('[WS] Ping error: $e');
          }
        }
      },
    );
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Cleanly disconnect and stop all reconnect timers.
  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _stopPingTimer();
    _channel?.sink.close();
    _updateState(SocketConnectionState.disconnected);
  }

  /// Exponential back-off reconnect: 1 s, 2 s, 4 s, 8 s, 16 s, 30 s (cap).
  void _handleDisconnect() {
    if (!_shouldReconnect) return;

    _reconnectTimer?.cancel();
    final delaySecs = _reconnectAttempts < 6 ? (1 << _reconnectAttempts) : 30;
    _reconnectAttempts++;
    _updateState(SocketConnectionState.reconnecting);

    _reconnectTimer = Timer(Duration(seconds: delaySecs), () {
      if (_currentToken != null && _currentUrl != null) {
        if (kDebugMode) {
          debugPrint(
            '[WS] Reconnecting (attempt $_reconnectAttempts, delay ${delaySecs}s)…',
          );
        }
        connect(url: _currentUrl!, token: _currentToken!);
      }
    });
  }

  /// Adapt ping frequency and trigger a quick reconnect when the network type
  /// changes (e.g. going from airplane mode back to Wi-Fi).
  void _monitorNetworkConnectivity() {
    Connectivity().onConnectivityChanged.listen((dynamic event) {
      ConnectivityResult result;
      if (event is List<ConnectivityResult>) {
        result =
            event.isNotEmpty ? event.first : ConnectivityResult.none;
      } else if (event is ConnectivityResult) {
        result = event;
      } else {
        result = ConnectivityResult.none;
      }

      // Use slower heartbeats on cellular to conserve mobile data
      if (result == ConnectivityResult.mobile) {
        _pingIntervalSeconds = 60;
      } else {
        _pingIntervalSeconds = 15;
      }

      if (_connectionState == SocketConnectionState.connected) {
        _startAdaptivePing(); // refresh the timer with the new interval
      }

      if (result != ConnectivityResult.none &&
          _connectionState == SocketConnectionState.disconnected &&
          _currentToken != null &&
          _currentUrl != null) {
        if (kDebugMode) debugPrint('[WS] Network restored — reconnecting…');
        connect(url: _currentUrl!, token: _currentToken!);
      }
    });
  }
}
