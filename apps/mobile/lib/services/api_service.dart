import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../core/config/app_config.dart';

/// Central service for all REST API calls beyond auth.
/// Uses the same Render backend URL as AuthService.
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Returns the stored JWT token, or null if not logged in.
  Future<String?> _token() async {
    final box = await Hive.openBox('secure_vault');
    return box.get('jwt_token') as String?;
  }

  Future<Options> _auth() async {
    final t = await _token();
    return Options(headers: {'Authorization': 'Bearer $t'});
  }

  // ─── User Search & Profile ───────────────────────────────────────────────────

  /// Search users by username fragment.
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final opts = await _auth();
      final res = await _dio.get(
        '/users/search',
        queryParameters: {'username': query},
        options: opts,
      );
      final List list = res.data['users'] ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('searchUsers error: $e');
      return [];
    }
  }

  /// Fetch current user's profile from the server.
  Future<Map<String, dynamic>?> getMyProfile() async {
    try {
      final opts = await _auth();
      final res = await _dio.get('/users/profile', options: opts);
      return res.data['profile'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('getMyProfile error: $e');
      return null;
    }
  }

  /// Update username, bio, mood, or avatar color on the server.
  Future<bool> updateProfile({String? username, String? bio, String? mood, String? avatarColor}) async {
    try {
      final opts = await _auth();
      final body = <String, dynamic>{};
      if (username != null) body['username'] = username;
      if (bio != null) body['bio'] = bio;
      if (mood != null) body['mood'] = mood;
      if (avatarColor != null) body['avatarColor'] = avatarColor;
      if (body.isEmpty) return false;
      await _dio.put('/users/profile', data: body, options: opts);
      return true;
    } catch (e) {
      debugPrint('updateProfile error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getGroups() async {
    try {
      final opts = await _auth();
      final res = await _dio.get('/groups', options: opts);
      final List list = res.data['groups'] ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('getGroups error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> createGroup({
    required String name,
    String? description,
    bool isCampfire = false,
    int? durationMs,
  }) async {
    try {
      final opts = await _auth();
      final res = await _dio.post(
        '/groups',
        data: {
          'name': name,
          'description': description ?? '',
          'isCampfire': isCampfire,
          'durationMs': durationMs,
        },
        options: opts,
      );
      return res.data['group'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('createGroup error: $e');
      return null;
    }
  }

  Future<bool> joinGroup(String groupId) async {
    try {
      final opts = await _auth();
      final res = await _dio.post('/groups/$groupId/join', options: opts);
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('joinGroup error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getGroupMessages(String groupId) async {
    try {
      final opts = await _auth();
      final res = await _dio.get('/groups/$groupId/messages', options: opts);
      final List list = res.data['messages'] ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('getGroupMessages error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getPendingConnections() async {
    try {
      final opts = await _auth();
      final res = await _dio.get('/users/connections/pending', options: opts);
      final List list = res.data['requests'] ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('getPendingConnections error: $e');
      return [];
    }
  }

  Future<bool> connectToUser(String username) async {
    try {
      final opts = await _auth();
      final res = await _dio.post('/users/connect/$username', options: opts);
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('connectToUser error: $e');
      return false;
    }
  }

  Future<bool> acceptConnection(String username) async {
    try {
      final opts = await _auth();
      final res = await _dio.post('/users/connections/accept/$username', options: opts);
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('acceptConnection error: $e');
      return false;
    }
  }

  Future<bool> rejectConnection(String username) async {
    try {
      final opts = await _auth();
      final res = await _dio.post('/users/connections/reject/$username', options: opts);
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('rejectConnection error: $e');
      return false;
    }
  }

  // ─── E2E Key Exchange ───────────────────────────────────────────────────────────────────

  /// Upload the local user's prekey bundle to the server.
  Future<bool> uploadPublicKey({
    required String identityKey,
    required String dhIdentityKey,
    required String signedPrekey,
    required String prekeySignature,
  }) async {
    try {
      final opts = await _auth();
      await _dio.post(
        '/keys/upload',
        data: {
          'identity_key': identityKey,
          'dh_identity_key': dhIdentityKey,
          'signed_prekey': signedPrekey,
          'prekey_signature': prekeySignature,
        },
        options: opts,
      );
      return true;
    } catch (e) {
      debugPrint('uploadPublicKey error: $e');
      return false;
    }
  }

  /// Fetch the prekey bundle for a given username.
  Future<Map<String, dynamic>?> fetchPublicKey(String username) async {
    try {
      final opts = await _auth();
      final res = await _dio.get('/keys/$username', options: opts);
      final found = res.data['found'] as bool? ?? false;
      if (!found) return null;
      return res.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('fetchPublicKey error: $e');
      return null;
    }
  }

  // ─── Group Key Distribution ─────────────────────────────────────────────────

  /// Store an ECIES-wrapped group key for [username] on the server.
  Future<bool> distributeGroupKey(String groupId, String username, String encryptedKey) async {
    try {
      final opts = await _auth();
      await _dio.post(
        '/groups/$groupId/keys',
        data: {'username': username, 'encrypted_key': encryptedKey},
        options: opts,
      );
      return true;
    } catch (e) {
      debugPrint('distributeGroupKey error: $e');
      return false;
    }
  }

  /// Fetch the ECIES-wrapped group key for the current user.
  Future<String?> fetchGroupKey(String groupId) async {
    try {
      final opts = await _auth();
      final res = await _dio.get('/groups/$groupId/keys/my', options: opts);
      return res.data['encrypted_key'] as String?;
    } catch (e) {
      debugPrint('fetchGroupKey error: $e');
      return null;
    }
  }

  /// Request a short-lived WebSocket authentication ticket.
  Future<String?> getWsTicket() async {
    try {
      final opts = await _auth();
      final res = await _dio.post('/auth/ws-ticket', options: opts);
      return res.data['ticket'] as String?;
    } catch (e) {
      debugPrint('getWsTicket error: $e');
      return null;
    }
  }

  // ─── Signal Group Sender Key Distribution ───────────────────────────────────

  /// Returns the list of member usernames for a group.
  Future<List<String>> getGroupMembers(String groupId) async {
    try {
      final opts = await _auth();
      final res = await _dio.get('/groups/$groupId/members', options: opts);
      final List list = res.data['members'] ?? [];
      return list.cast<String>();
    } catch (e) {
      debugPrint('getGroupMembers error: $e');
      return [];
    }
  }

  /// Uploads encrypted SenderKey bundles to the server for each group member.
  /// [bundles] = [{'recipientUsername': '...', 'encryptedBundle': '...'}]
  Future<bool> uploadGroupSenderKeyBundles(
    String groupId,
    List<Map<String, String>> bundles,
  ) async {
    try {
      final opts = await _auth();
      await _dio.post(
        '/groups/$groupId/sender-key',
        data: {'bundles': bundles},
        options: opts,
      );
      return true;
    } catch (e) {
      debugPrint('uploadGroupSenderKeyBundles error: $e');
      return false;
    }
  }

  /// Fetches the encrypted SenderKey bundle that [senderUsername] uploaded
  /// specifically for the requesting user.  Returns null if not found.
  Future<String?> fetchGroupSenderKey(
      String groupId, String senderUsername) async {
    try {
      final opts = await _auth();
      final res = await _dio.get(
        '/groups/$groupId/sender-key/$senderUsername',
        options: opts,
      );
      final found = res.data['found'] as bool? ?? false;
      if (!found) return null;
      return res.data['encryptedBundle'] as String?;
    } catch (e) {
      debugPrint('fetchGroupSenderKey error: $e');
      return null;
    }
  }
}
