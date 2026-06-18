import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class ConnectionInvite {
  final String username;
  final String type; // 'incoming' or 'outgoing'
  final String status; // 'pending', 'accepted', 'rejected'
  final int timestamp;

  ConnectionInvite({
    required this.username,
    required this.type,
    required this.status,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'type': type,
    'status': status,
    'timestamp': timestamp,
  };

  factory ConnectionInvite.fromJson(Map<String, dynamic> json) => ConnectionInvite(
    username: json['username'] as String,
    type: json['type'] as String,
    status: json['status'] as String,
    timestamp: json['timestamp'] as int,
  );
}

class ConnectionState {
  final List<ConnectionInvite> invitations;
  final List<String> connections;

  ConnectionState({
    required this.invitations,
    required this.connections,
  });

  ConnectionState copyWith({
    List<ConnectionInvite>? invitations,
    List<String>? connections,
  }) {
    return ConnectionState(
      invitations: invitations ?? this.invitations,
      connections: connections ?? this.connections,
    );
  }
}

class ConnectionNotifier extends StateNotifier<ConnectionState> {
  ConnectionNotifier() : super(ConnectionState(invitations: [], connections: [])) {
    _loadData();
    _startWebSocketListener();
  }

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
        if (state.connections.contains(u)) continue; // already accepted

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
          if (!newConns.contains(clean)) newConns.add(clean);

          // Remove the outgoing invite — it's been accepted, no need to keep it
          final updatedInvites = state.invitations
              .where((i) => !(i.username == clean && i.type == 'outgoing'))
              .toList();

          state = state.copyWith(invitations: updatedInvites, connections: newConns);
          await _saveData();
        }
      }
    });
  }

  Future<bool> sendInvitation(String username) async {
    final clean = username.toLowerCase().trim();
    if (clean.isEmpty) return false;

    if (state.connections.contains(clean)) return false;
    final exists = state.invitations.any((i) => i.username == clean && i.type == 'outgoing');
    if (exists) return true;

    final success = await ApiService().connectToUser(clean);
    if (!success) return false;

    final invite = ConnectionInvite(
      username: clean,
      type: 'outgoing',
      status: 'pending',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    state = state.copyWith(invitations: [...state.invitations, invite]);
    await _saveData();
    return true;
  }

  Future<void> acceptInvitation(String username) async {
    final clean = username.toLowerCase().trim();

    await ApiService().acceptConnection(clean);

    // Remove invite from list and add to connections
    final updatedInvites = state.invitations
        .where((i) => !(i.username == clean && i.type == 'incoming'))
        .toList();

    final List<String> newConns = List.from(state.connections);
    if (!newConns.contains(clean)) newConns.add(clean);

    state = state.copyWith(invitations: updatedInvites, connections: newConns);
    await _saveData();
  }

  Future<void> rejectInvitation(String username) async {
    final clean = username.toLowerCase().trim();

    await ApiService().rejectConnection(clean);

    // Remove invite from list entirely
    final updatedInvites = state.invitations
        .where((i) => !(i.username == clean && i.type == 'incoming'))
        .toList();

    state = state.copyWith(invitations: updatedInvites);
    await _saveData();
  }
}

final connectionProvider = StateNotifierProvider<ConnectionNotifier, ConnectionState>((ref) {
  return ConnectionNotifier();
});
