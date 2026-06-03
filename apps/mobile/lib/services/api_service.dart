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

  // ─── Lucky Pulse ────────────────────────────────────────────────────────────

  /// Fetch all active pulse posts (last 7 days).
  Future<List<Map<String, dynamic>>> getPulses() async {
    try {
      final opts = await _auth();
      final res = await _dio.get('/pulse', options: opts);
      final List list = res.data['pulses'] ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('getPulses error: $e');
      return [];
    }
  }

  /// Create a new anonymous pulse post.
  Future<bool> createPulse({required String text, required List<String> topics}) async {
    try {
      final opts = await _auth();
      await _dio.post(
        '/pulse',
        data: {'text': text, 'topics': topics},
        options: opts,
      );
      return true;
    } catch (e) {
      debugPrint('createPulse error: $e');
      return false;
    }
  }

  /// Increment the seen counter for a pulse.
  Future<void> markPulseSeen(String pulseId) async {
    try {
      final opts = await _auth();
      await _dio.post('/pulse/$pulseId/seen', options: opts);
    } catch (_) {}
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

  /// Request E2E connection with anonymous author of a pulse post
  Future<bool> connectToPulseAuthor(String pulseId) async {
    try {
      final opts = await _auth();
      final res = await _dio.post('/pulse/$pulseId/connect', options: opts);
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('connectToPulseAuthor error: $e');
      return false;
    }
  }
}
