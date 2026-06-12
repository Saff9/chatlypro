import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'encryption_service.dart';
import 'websocket_service.dart';
import 'push_notification_service.dart';
import 'api_service.dart';
import '../core/config/app_config.dart';

class AuthResult {
  final bool success;
  final bool emailVerified;
  final bool twoFactorRequired;
  final String? tempToken;
  final String? email;
  final String? errorMessage;

  AuthResult({
    required this.success,
    this.emailVerified = true,
    this.twoFactorRequired = false,
    this.tempToken,
    this.email,
    this.errorMessage,
  });
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _dio = Dio(BaseOptions(
    // Server base URL is resolved from AppConfig, which reads the --dart-define
    // BASE_URL compile-time environment variable. Falls back to localhost for
    // local development with zero configuration needed.
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: AppConfig.connectTimeout,
    receiveTimeout: AppConfig.receiveTimeout,
  ));

  final _crypto = EncryptionService();

  String? _token;
  String? _userId;
  String? _username;

  // Getters
  String? get token => _token;
  String? get userId => _userId;
  String? get username => _username;
  bool get isAuthenticated => _token != null;

  /// Setup the auth session using stored tokens
  Future<bool> tryAutoLogin() async {
    final secureBox = await Hive.openBox('secure_vault');
    _token = secureBox.get('jwt_token');
    _userId = secureBox.get('user_id');
    _username = secureBox.get('username');

    if (_token != null && _userId != null) {
      // Connect WebSocket instantly
      WebSocketService().connect(
        url: AppConfig.wsBaseUrl,
        token: _token!,
      );
      // Register push notifications
      PushNotificationService().setupPushNotifications();
      // Upload public key to server so chat partners can start E2EE sessions
      _uploadPublicKeyIfNeeded();
      return true;
    }
    return false;
  }

  /// Register a new account, generates E2E keys and pushes public key to server
  Future<AuthResult> register({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      // 1. Generate local keypair
      final keyPair = await _crypto.generateKeyPair();
      final pubKeyBase64 = await _crypto.exportPublicKey(keyPair);
      final privKeyBase64 = await _crypto.exportPrivateKey(keyPair);

      // Save keys temporarily in secure Hive so we don't lose them before verification
      final secureBox = await Hive.openBox('secure_vault');
      await secureBox.put('public_key', pubKeyBase64);
      await secureBox.put('private_key', privKeyBase64);

      // 2. API Signup Call
      final response = await _dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        'username': username,
        'avatarColor': '#6366F1',
      });

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = response.data;
        final tempToken = data['token'];
        final emailVerified = data['emailVerified'] ?? false;

        if (!emailVerified) {
          return AuthResult(
            success: true,
            emailVerified: false,
            email: email,
            tempToken: tempToken,
          );
        }

        _token = data['token'];
        _userId = data['userId'];
        _username = data['username'];

        await secureBox.put('jwt_token', _token);
        await secureBox.put('user_id', _userId);
        await secureBox.put('username', _username);

        // Connect WebSockets
        WebSocketService().connect(url: AppConfig.wsBaseUrl, token: _token!);
        // Register push notifications
        PushNotificationService().setupPushNotifications();
        // Upload public key so chat partners can find us
        _uploadPublicKeyIfNeeded();

        return AuthResult(success: true, emailVerified: true);
      }
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['error'] ?? 'Registration failed. Please try again.';
      return AuthResult(success: false, errorMessage: errorMsg);
    } catch (e) {
      debugPrint('register: unexpected error: $e');
      return AuthResult(success: false, errorMessage: 'Network error. Please check your connection and try again.');
    }
    return AuthResult(success: false, errorMessage: 'Unknown error occurred.');
  }

  /// Logs user in, downloads details, and starts active WS session
  Future<AuthResult> login({required String email, required String password}) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        
        if (data['twoFactorRequired'] == true) {
          return AuthResult(
            success: true,
            twoFactorRequired: true,
            tempToken: data['tempToken'],
            email: email,
          );
        }

        _token = data['token'];
        _userId = data['userId'];
        _username = data['username'];

        final secureBox = await Hive.openBox('secure_vault');
        await secureBox.put('jwt_token', _token);
        await secureBox.put('user_id', _userId);
        await secureBox.put('username', _username);

        // If keys don't exist locally, generate them (recovery fallback)
        if (!secureBox.containsKey('private_key')) {
          final keyPair = await _crypto.generateKeyPair();
          final pubKeyBase64 = await _crypto.exportPublicKey(keyPair);
          final privKeyBase64 = await _crypto.exportPrivateKey(keyPair);
          await secureBox.put('public_key', pubKeyBase64);
          await secureBox.put('private_key', privKeyBase64);
        }

        WebSocketService().connect(url: AppConfig.wsBaseUrl, token: _token!);
        PushNotificationService().setupPushNotifications();
        _uploadPublicKeyIfNeeded();
        return AuthResult(success: true, emailVerified: true);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        final data = e.response?.data;
        if (data != null && data['emailVerified'] == false) {
          return AuthResult(
            success: false,
            emailVerified: false,
            email: email,
            errorMessage: data['error'],
          );
        }
      }
      final errorMsg = e.response?.data?['error'] ?? 'Invalid email or password.';
      return AuthResult(success: false, errorMessage: errorMsg);
    } catch (e) {
      debugPrint('login: unexpected error: $e');
      return AuthResult(success: false, errorMessage: 'Network error. Please check your connection and try again.');
    }
    return AuthResult(success: false, errorMessage: 'Unknown error occurred.');
  }

  /// Verify verification code sent to email
  Future<bool> verifyEmail({required String email, required String code}) async {
    try {
      final response = await _dio.post('/auth/verify-email', data: {
        'email': email,
        'code': code,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        _token = data['token'];
        _userId = data['userId'];
        _username = data['username'];

        final secureBox = await Hive.openBox('secure_vault');
        await secureBox.put('jwt_token', _token);
        await secureBox.put('user_id', _userId);
        await secureBox.put('username', _username);

        WebSocketService().connect(url: AppConfig.wsBaseUrl, token: _token!);
        PushNotificationService().setupPushNotifications();
        return true;
      }
    } catch (e) {
      debugPrint('verifyEmail error: $e');
    }
    return false;
  }

  /// Resend verification code
  Future<bool> resendVerification({required String email}) async {
    try {
      final response = await _dio.post('/auth/resend-verification', data: {
        'email': email,
      });
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('resendVerification error: $e');
    }
    return false;
  }

  /// Verify 2FA verification code
  Future<bool> verify2FA({required String tempToken, required String code}) async {
    try {
      final response = await _dio.post('/auth/verify-2fa', data: {
        'tempToken': tempToken,
        'code': code,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        _token = data['token'];
        _userId = data['userId'];
        _username = data['username'];

        final secureBox = await Hive.openBox('secure_vault');
        await secureBox.put('jwt_token', _token);
        await secureBox.put('user_id', _userId);
        await secureBox.put('username', _username);

        WebSocketService().connect(url: AppConfig.wsBaseUrl, token: _token!);
        PushNotificationService().setupPushNotifications();
        return true;
      }
    } catch (e) {
      debugPrint('verify2FA error: $e');
    }
    return false;
  }

  /// Toggle 2FA state (requires authenticated session)
  Future<bool> toggle2FA({required bool enabled}) async {
    if (_token == null) return false;
    try {
      final response = await _dio.post(
        '/auth/toggle-2fa',
        data: {'enabled': enabled},
        options: Options(headers: {
          'Authorization': 'Bearer $_token',
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('toggle2FA error: $e');
    }
    return false;
  }

  /// Check 2FA toggle status (read from server or local mock fallback)
  Future<bool> get2FAStatus() async {
    // For local mock, we can save 2fa status in Hive or retrieve it.
    // Let's check from memory/Hive.
    final secureBox = await Hive.openBox('secure_vault');
    return secureBox.get('two_factor_enabled', defaultValue: false) as bool;
  }

  Future<void> save2FAStatus(bool enabled) async {
    final secureBox = await Hive.openBox('secure_vault');
    await secureBox.put('two_factor_enabled', enabled);
  }

  /// Check if a username is available on the server
  Future<bool> isUsernameAvailable(String username) async {
    try {
      final response = await _dio.get(
        '/auth/username-check',
        queryParameters: {'username': username},
      );
      if (response.statusCode == 200) {
        return response.data['available'] == true;
      }
    } catch (e) {
      debugPrint('isUsernameAvailable error: $e');
    }
    return false;
  }

  /// Upload public key to server if one exists locally.
  /// Fire-and-forget: failures are logged but do not block the auth flow.
  void _uploadPublicKeyIfNeeded() async {
    try {
      final secureBox = await Hive.openBox('secure_vault');
      final pubKey = secureBox.get('public_key') as String?;
      if (pubKey != null && pubKey.isNotEmpty) {
        await ApiService().uploadPublicKey(pubKey);
      }
    } catch (e) {
      debugPrint('_uploadPublicKeyIfNeeded: $e');
    }
  }

  /// Disconnects socket and wipes stored session tokens
  Future<void> logout() async {
    WebSocketService().disconnect();
    final secureBox = await Hive.openBox('secure_vault');
    await secureBox.delete('jwt_token');
    await secureBox.delete('user_id');
    await secureBox.delete('username');
    _token = null;
    _userId = null;
    _username = null;
  }
}
