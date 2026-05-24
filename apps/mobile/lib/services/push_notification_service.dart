import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';
import 'encryption_service.dart';
import 'websocket_service.dart';
import 'message_storage_service.dart';
import '../features/chat/data/models/message_model.dart';
import 'auth_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Already initialized or missing configuration file
  }

  // Ensure Hive is initialized in this isolate
  try {
    await Hive.initFlutter();
  } catch (_) {
    // Hive already initialized in parent
  }

  if (!Hive.isBoxOpen('secure_vault')) {
    await Hive.openBox('secure_vault');
  }

  final secureBox = Hive.box('secure_vault');
  final token = secureBox.get('jwt_token') as String?;

  if (token != null && token != 'offline-dev-token-fallback') {
    // Connect WebSocket temporarily to sync messages in background
    WebSocketService().connect(url: 'http://localhost:5000', token: token);
    
    // Maintain connection long enough to fetch offline messages (4 seconds)
    await Future.delayed(const Duration(seconds: 4));
    WebSocketService().disconnect();
  }
}

class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final _dio = Dio(BaseOptions(
    baseUrl: 'http://localhost:5000/api',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 3),
  ));

  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize Firebase Core and Messaging setup
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      if (kDebugMode) {
        print('Firebase init skipped or service file missing: $e');
      }
    }

    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize local notifications channel
    await _initializeLocalNotifications();

    // Set up foreground message handling
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        print('Received foreground push sync trigger: ${message.data}');
      }
      // Since app is foreground, we are already connected via WebSocket or should check connection
      final auth = AuthService();
      if (auth.isAuthenticated) {
        WebSocketService().connect(url: 'http://localhost:5000', token: auth.token!);
      }
    });

    // Register a global listener on the websocket message stream to decrypt and notify
    WebSocketService().messageStream.listen(_handleIncomingWebSocketMessage);

    _initialized = true;
  }

  /// Setup notifications: request permissions, get token, and upload to server
  Future<void> setupPushNotifications() async {
    try {
      final messaging = FirebaseMessaging.instance;
      
      // Request permissions
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Get FCM Token
      final token = await messaging.getToken();
      if (token != null) {
        if (kDebugMode) {
          print('FCM Token generated: $token');
        }
        await _uploadPushToken(token);
      }
    } catch (e) {
      if (kDebugMode) {
        print('FCM setup skipped (simulation mode): $e');
      }
    }
  }

  /// Upload the device push token to the backend
  Future<void> _uploadPushToken(String token) async {
    final auth = AuthService();
    if (!auth.isAuthenticated) return;

    try {
      final response = await _dio.post(
        '/auth/push-token',
        data: {'pushToken': token},
        options: Options(
          headers: {
            'Authorization': 'Bearer ${auth.token}',
          },
        ),
      );
      if (kDebugMode) {
        print('Push token uploaded successfully: ${response.data}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to upload push token: $e');
      }
    }
  }

  /// Local Notifications initialization
  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _localNotificationsPlugin.initialize(initializationSettings);
  }

  /// Listen to WebSocket messages and process decryption and notifications
  Future<void> _handleIncomingWebSocketMessage(Map<String, dynamic> payload) async {
    if (payload['type'] == 'message') {
      final senderId = payload['senderId'] as String?;
      final ciphertext = payload['ciphertext'] as String?;

      if (senderId != null && ciphertext != null) {
        // Retrieve keys from Hive to decrypt
        final secureBox = await Hive.openBox('secure_vault');
        final myPrivBase64 = secureBox.get('private_key') as String?;
        final myPubBase64 = secureBox.get('public_key') as String?;
        final recipientPublicKeyBase64 = secureBox.get('recipient_pub_$senderId') as String?;

        String decryptedText = '[Encrypted message]';
        if (myPrivBase64 != null && myPubBase64 != null && recipientPublicKeyBase64 != null) {
          try {
            final crypto = EncryptionService();
            final myKeyPair = await crypto.importKeyPair(myPubBase64, myPrivBase64);
            final sharedSessionKey = await crypto.deriveSharedSecret(
              myKeyPair: myKeyPair,
              recipientPublicBase64: recipientPublicKeyBase64,
            );

            decryptedText = await crypto.decryptMessage(
              encryptedPacketBase64: ciphertext,
              secretKey: sharedSessionKey,
            );
          } catch (e) {
            decryptedText = '[Decryption failed — secure handshake mismatch]';
          }
        }

        // Save decrypted message to database (unless it's already saved by chat screen)
        final storage = MessageStorageService();
        final existing = await storage.getMessages(senderId);
        final exists = existing.any((m) => m.text == decryptedText && m.isMe == false);
        
        if (!exists) {
          final newMsg = MessageData(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            text: decryptedText,
            isMe: false,
            time: 'Now',
            isRead: false,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
          await storage.saveMessage(senderId, newMsg);
          
          // Display the local notification securely
          await _showLocalNotification(senderId, decryptedText);
        }
      }
    }
  }

  /// Show standard secure local notification
  static Future<void> _showLocalNotification(String senderId, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'secure_sync_channel',
      'Secure Messages',
      channelDescription: 'This channel is used for secure silent sync notifications.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const DarwinNotificationDetails darwinPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: darwinPlatformChannelSpecifics,
    );

    await _localNotificationsPlugin.show(
      senderId.hashCode,
      'New Message',
      '@$senderId: $body',
      platformChannelSpecifics,
    );
  }
}
