import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

enum SocketConnectionState { disconnected, connecting, connected, reconnecting }

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal() {
    _monitorNetworkConnectivity();
  }

  WebSocketChannel? _channel;
  SocketConnectionState _connectionState = SocketConnectionState.disconnected;
  
  final StreamController<Map<String, dynamic>> _messageStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<SocketConnectionState> _stateStreamController = StreamController<SocketConnectionState>.broadcast();

  String? _currentToken;
  String? _currentUrl;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  // Bandwidth Adaptation Settings
  int _pingIntervalSeconds = 15; // Default: 15 seconds on fast links
  DateTime? _lastTypingSent;

  // Public Getters
  Stream<Map<String, dynamic>> get messageStream => _messageStreamController.stream;
  Stream<SocketConnectionState> get stateStream => _stateStreamController.stream;
  SocketConnectionState get connectionState => _connectionState;

  void _updateState(SocketConnectionState state) {
    _connectionState = state;
    _stateStreamController.add(state);
    
    if (state == SocketConnectionState.connected) {
      _startAdaptivePing();
      _flushOutboxQueue(); // Sync local drafts automatically on link-up
    } else {
      _stopPingTimer();
    }

    if (kDebugMode) {
      print('WebSocket Connection State: $state');
    }
  }

  /// Initialize and connect WebSocket channel
  void connect({required String url, required String token}) {
    _currentToken = token;
    _currentUrl = url;
    _shouldReconnect = true;

    if (_connectionState == SocketConnectionState.connected || 
        _connectionState == SocketConnectionState.connecting) {
      return;
    }

    _updateState(SocketConnectionState.connecting);
    final wsUri = Uri.parse('$url/ws/chat');

    try {
      _channel = IOWebSocketChannel.connect(
        wsUri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      _channel!.stream.listen(
        (message) {
          _reconnectAttempts = 0;
          _updateState(SocketConnectionState.connected);
          try {
            final Map<String, dynamic> parsedData = jsonDecode(message);
            _messageStreamController.add(parsedData);
          } catch (e) {
            if (kDebugMode) print('Error parsing WebSocket data: $e');
          }
        },
        onDone: () {
          _updateState(SocketConnectionState.disconnected);
          _handleDisconnect();
        },
        onError: (error) {
          _updateState(SocketConnectionState.disconnected);
          if (kDebugMode) print('WebSocket stream error: $error');
          _handleDisconnect();
        },
      );
    } catch (e) {
      _updateState(SocketConnectionState.disconnected);
      if (kDebugMode) print('Error establishing WebSocket connection: $e');
      _handleDisconnect();
    }
  }

  /// Send message payload. Queues in local Hive outbox if connection is unavailable.
  Future<bool> sendMessage({required String recipientId, required String ciphertext}) async {
    final outboxBox = await Hive.openBox('outbox');
    
    final payload = {
      'recipientId': recipientId,
      'ciphertext': ciphertext,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    if (_connectionState != SocketConnectionState.connected || _channel == null) {
      // 0 Data or low link: Save in local outbox out-of-the-box
      final messageId = DateTime.now().microsecondsSinceEpoch.toString();
      await outboxBox.put(messageId, jsonEncode(payload));
      if (kDebugMode) {
        print('Offline: Encrypted message packet queued in Hive Outbox.');
      }
      return false; // Renders as pending (clock) in UI
    }

    try {
      final messagePayload = {
        'type': 'message',
        'recipientId': recipientId,
        'ciphertext': ciphertext,
      };
      _channel!.sink.add(jsonEncode(messagePayload));
      return true; // Sent successfully
    } catch (e) {
      // Send failed, fallback to outbox
      final messageId = DateTime.now().microsecondsSinceEpoch.toString();
      await outboxBox.put(messageId, jsonEncode(payload));
      return false;
    }
  }

  /// Automatically flushes queued outbox messages once connection is established
  Future<void> _flushOutboxQueue() async {
    final outboxBox = await Hive.openBox('outbox');
    if (outboxBox.isEmpty) return;

    if (kDebugMode) {
      print('Flushing ${outboxBox.length} queued messages from outbox...');
    }

    final keys = List<String>.from(outboxBox.keys);
    for (final key in keys) {
      if (_connectionState != SocketConnectionState.connected) break;
      
      final value = outboxBox.get(key);
      if (value != null) {
        try {
          final data = jsonDecode(value);
          final messagePayload = {
            'type': 'message',
            'recipientId': data['recipientId'],
            'ciphertext': data['ciphertext'],
          };
          _channel!.sink.add(jsonEncode(messagePayload));
          await outboxBox.delete(key); // Remove from queue (Zero trace)
        } catch (e) {
          if (kDebugMode) print('Failed to sync outbox message: $e');
        }
      }
    }
  }

  /// Send real-time typing indicators with throttling to save 2G data
  void sendTypingStatus({required String recipientId, required bool isTyping}) {
    if (_connectionState != SocketConnectionState.connected || _channel == null) return;

    // Rate-limiting typing indicators to once per 8 seconds to prevent network bloat on 2G
    final now = DateTime.now();
    if (_lastTypingSent != null && now.difference(_lastTypingSent!).inSeconds < 8 && isTyping) {
      return;
    }

    _lastTypingSent = now;

    final payload = {
      'type': 'typing',
      'recipientId': recipientId,
      'isTyping': isTyping,
    };

    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      if (kDebugMode) print('Failed to send typing indicator: $e');
    }
  }

  /// Starts adaptive keep-alive pings based on current network bandwidth profile
  void _startAdaptivePing() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(Duration(seconds: _pingIntervalSeconds), (timer) {
      if (_connectionState == SocketConnectionState.connected && _channel != null) {
        try {
          _channel!.sink.add(jsonEncode({'type': 'ping'}));
        } catch (e) {
          if (kDebugMode) print('Ping error: $e');
        }
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Disconnect and clean connections
  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _stopPingTimer();
    _channel?.sink.close();
    _updateState(SocketConnectionState.disconnected);
  }

  /// Handle auto-reconnections with exponential backoff
  void _handleDisconnect() {
    if (!_shouldReconnect) return;

    _reconnectTimer?.cancel();
    
    final delaySeconds = (_reconnectAttempts < 6) ? (1 << _reconnectAttempts) : 30;
    _reconnectAttempts++;

    _updateState(SocketConnectionState.reconnecting);

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_currentToken != null && _currentUrl != null) {
        if (kDebugMode) {
          print('Reconnecting to server (Attempt $_reconnectAttempts, Delay ${delaySeconds}s)...');
        }
        connect(url: _currentUrl!, token: _currentToken!);
      }
    });
  }

  /// Network status check for quick reconnection and ping-rate adaptation
  void _monitorNetworkConnectivity() {
    Connectivity().onConnectivityChanged.listen((dynamic event) {
      ConnectivityResult result;
      if (event is List<ConnectivityResult>) {
        result = event.isNotEmpty ? event.first : ConnectivityResult.none;
      } else if (event is ConnectivityResult) {
        result = event;
      } else {
        result = ConnectivityResult.none;
      }

      // Adaptive heartbeats: Slow down pings on mobile connections to preserve data
      if (result == ConnectivityResult.mobile) {
        _pingIntervalSeconds = 60; // 2G/Mobile gets 60-second pings to save data
        if (_connectionState == SocketConnectionState.connected) {
          _startAdaptivePing(); // Refresh ping scheduler
        }
      } else {
        _pingIntervalSeconds = 15; // Fast connections use 15s heartbeats
        if (_connectionState == SocketConnectionState.connected) {
          _startAdaptivePing();
        }
      }

      if (result != ConnectivityResult.none && 
          _connectionState == SocketConnectionState.disconnected && 
          _currentToken != null && 
          _currentUrl != null) {
        if (kDebugMode) print('Network restored. Re-establishing connection...');
        connect(url: _currentUrl!, token: _currentToken!);
      }
    });
  }
}
