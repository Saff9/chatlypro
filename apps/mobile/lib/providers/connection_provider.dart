import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'dart:io';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class ConnectionInvite {
  final String username;
  final String type; // 'incoming' or 'outgoing'
  final String status; // 'pending', 'accepted', 'rejected'
  final int timestamp;
  final bool isProximity; // Whether sent via UDP mesh

  ConnectionInvite({
    required this.username,
    required this.type,
    required this.status,
    required this.timestamp,
    this.isProximity = false,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'type': type,
    'status': status,
    'timestamp': timestamp,
    'isProximity': isProximity,
  };

  factory ConnectionInvite.fromJson(Map<String, dynamic> json) => ConnectionInvite(
    username: json['username'] as String,
    type: json['type'] as String,
    status: json['status'] as String,
    timestamp: json['timestamp'] as int,
    isProximity: json['isProximity'] as bool? ?? false,
  );
}

class ConnectionState {
  final List<ConnectionInvite> invitations;
  final List<String> connections;
  final ConnectionInvite? activeProximityRequest; // Floating popup request

  ConnectionState({
    required this.invitations,
    required this.connections,
    this.activeProximityRequest,
  });

  ConnectionState copyWith({
    List<ConnectionInvite>? invitations,
    List<String>? connections,
    ConnectionInvite? activeProximityRequest,
    bool clearProximity = false,
  }) {
    return ConnectionState(
      invitations: invitations ?? this.invitations,
      connections: connections ?? this.connections,
      activeProximityRequest: clearProximity ? null : (activeProximityRequest ?? this.activeProximityRequest),
    );
  }
}

class ConnectionNotifier extends StateNotifier<ConnectionState> {
  ConnectionNotifier() : super(ConnectionState(invitations: [], connections: [])) {
    _loadData();
    _startProximityListener();
    _startWebSocketListener();
  }

  RawDatagramSocket? _udpInviteSocket;

  Future<void> _loadData() async {
    final box = await Hive.openBox('settings');
    final storedInvites = box.get('connection_invitations', defaultValue: '[]');
    final storedConns = box.get('accepted_connections', defaultValue: <String>[]);

    final List<dynamic> jsonList = jsonDecode(storedInvites);
    final invites = jsonList.map((e) => ConnectionInvite.fromJson(e as Map<String, dynamic>)).toList();

    state = ConnectionState(
      invitations: invites,
      connections: List<String>.from(storedConns),
    );

    // Sync pending requests with server in background
    syncPendingInvitations();
  }

  Future<void> _saveData() async {
    final box = await Hive.openBox('settings');
    final jsonStr = jsonEncode(state.invitations.map((e) => e.toJson()).toList());
    await box.put('connection_invitations', jsonStr);
    await box.put('accepted_connections', state.connections);
  }

  Future<void> syncPendingInvitations() async {
    try {
      final raw = await ApiService().getPendingConnections();
      final List<ConnectionInvite> updatedInvites = List.from(state.invitations);
      bool changed = false;

      for (final r in raw) {
        final u = r['username']?.toString().toLowerCase().trim() ?? '';
        if (u.isEmpty) continue;

        final exists = updatedInvites.any((i) => i.username == u && i.type == 'incoming');
        if (!exists) {
          updatedInvites.add(ConnectionInvite(
            username: u,
            type: 'incoming',
            status: 'pending',
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
          changed = true;
        }
      }

      if (changed) {
        state = state.copyWith(invitations: updatedInvites);
        await _saveData();
      }
    } catch (_) {}
  }

  void _startWebSocketListener() {
    WebSocketService().messageStream.listen((payload) async {
      final type = payload['type'] as String?;
      if (type == 'incoming_connection_request') {
        final fromUsername = payload['fromUsername'] as String?;
        if (fromUsername != null) {
          final clean = fromUsername.toLowerCase().trim();

          if (state.connections.contains(clean)) return;
          final exists = state.invitations.any((i) => i.username == clean && i.type == 'incoming');
          if (exists) return;

          final invite = ConnectionInvite(
            username: clean,
            type: 'incoming',
            status: 'pending',
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );

          state = state.copyWith(invitations: [...state.invitations, invite]);
          await _saveData();
        }
      } else if (type == 'connection_accepted') {
        final fromUsername = payload['fromUsername'] as String?;
        if (fromUsername != null) {
          final clean = fromUsername.toLowerCase().trim();

          final List<String> newConns = List.from(state.connections);
          if (!newConns.contains(clean)) {
            newConns.add(clean);
          }

          final updatedInvites = state.invitations.map((i) {
            if (i.username == clean && i.type == 'outgoing') {
              return ConnectionInvite(
                username: i.username,
                type: i.type,
                status: 'accepted',
                timestamp: i.timestamp,
                isProximity: i.isProximity,
              );
            }
            return i;
          }).toList();

          state = state.copyWith(invitations: updatedInvites, connections: newConns);
          await _saveData();
        }
      }
    });
  }

  /// Sends a connection invitation by username
  Future<bool> sendInvitation(String username, {bool isProximity = false}) async {
    final clean = username.toLowerCase().trim();
    if (clean.isEmpty) return false;

    // Check if already connected or already invited
    if (state.connections.contains(clean)) return false;
    final exists = state.invitations.any((i) => i.username == clean && i.type == 'outgoing');
    if (exists) return true;

    if (!isProximity) {
      final success = await ApiService().connectToUser(clean);
      if (!success) return false;
    }

    final invite = ConnectionInvite(
      username: clean,
      type: 'outgoing',
      status: 'pending',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isProximity: isProximity,
    );

    state = state.copyWith(invitations: [...state.invitations, invite]);
    await _saveData();

    // If P2P mesh invite, broadcast to local UDP network
    if (isProximity) {
      _broadcastProximityInvite(clean);
    }

    return true;
  }

  /// Accept an incoming connection request
  Future<void> acceptInvitation(String username) async {
    final clean = username.toLowerCase().trim();

    await ApiService().acceptConnection(clean);
    
    // Update invitation status
    final updatedInvites = state.invitations.map((i) {
      if (i.username == clean && i.type == 'incoming') {
        return ConnectionInvite(
          username: i.username,
          type: i.type,
          status: 'accepted',
          timestamp: i.timestamp,
          isProximity: i.isProximity,
        );
      }
      return i;
    }).toList();

    final List<String> newConns = List.from(state.connections);
    if (!newConns.contains(clean)) {
      newConns.add(clean);
    }

    state = state.copyWith(invitations: updatedInvites, connections: newConns);
    await _saveData();
  }

  /// Reject an incoming connection request
  Future<void> rejectInvitation(String username) async {
    final clean = username.toLowerCase().trim();

    await ApiService().rejectConnection(clean);
    
    final updatedInvites = state.invitations.map((i) {
      if (i.username == clean && i.type == 'incoming') {
        return ConnectionInvite(
          username: i.username,
          type: i.type,
          status: 'rejected',
          timestamp: i.timestamp,
          isProximity: i.isProximity,
        );
      }
      return i;
    }).toList();

    state = state.copyWith(invitations: updatedInvites);
    await _saveData();
  }

  /// Clear active proximity popup request
  void clearProximityRequest() {
    state = state.copyWith(clearProximity: true);
  }

  /// Simulate receiving a proximity NFC pair request
  void simulateProximityRequest(String username) {
    final invite = ConnectionInvite(
      username: username,
      type: 'incoming',
      status: 'pending',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isProximity: true,
    );
    state = state.copyWith(
      invitations: [...state.invitations, invite],
      activeProximityRequest: invite,
    );
  }

  /// Setup a separate UDP listener on port 4547 specifically for proximity invites
  Future<void> _startProximityListener() async {
    try {
      _udpInviteSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 4547);
      _udpInviteSocket!.broadcastEnabled = true;
      _udpInviteSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpInviteSocket!.receive();
          if (datagram != null) {
            final payload = utf8.decode(datagram.data);
            _handleIncomingUdpInvite(payload);
          }
        }
      });
    } catch (_) {
      // Port conflict fallback
    }
  }

  void _handleIncomingUdpInvite(String payload) async {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'] as String;
      final sender = data['sender'] as String;
      final target = data['target'] as String;

      // Only process if it is addressed to this user (we mock username matches or process for preview)
      final box = await Hive.openBox('settings');
      final myUsername = box.get('username', defaultValue: '') as String;

      if (target.toLowerCase().trim() == myUsername.toLowerCase().trim()) {
        if (type == 'PROXIMITY_INVITE') {
          // Verify if already connected
          if (state.connections.contains(sender.toLowerCase().trim())) return;

          final invite = ConnectionInvite(
            username: sender,
            type: 'incoming',
            status: 'pending',
            timestamp: DateTime.now().millisecondsSinceEpoch,
            isProximity: true,
          );

          // Add to invitations list and update active popup trigger
          state = state.copyWith(
            invitations: [...state.invitations, invite],
            activeProximityRequest: invite,
          );
          await _saveData();
        }
      }
    } catch (_) {}
  }

  void _broadcastProximityInvite(String targetUser) async {
    if (_udpInviteSocket == null) return;
    try {
      final box = await Hive.openBox('settings');
      final myUsername = box.get('username', defaultValue: '') as String;

      final payload = jsonEncode({
        'type': 'PROXIMITY_INVITE',
        'sender': myUsername,
        'target': targetUser,
      });
      final data = utf8.encode(payload);
      _udpInviteSocket!.send(data, InternetAddress('255.255.255.255'), 4547);
    } catch (_) {}
  }

  @override
  void dispose() {
    _udpInviteSocket?.close();
    super.dispose();
  }
}

final connectionProvider = StateNotifierProvider<ConnectionNotifier, ConnectionState>((ref) {
  return ConnectionNotifier();
});
