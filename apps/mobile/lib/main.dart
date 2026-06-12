import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'features/auth/presentation/screens/splash_screen.dart';
import 'providers/theme_provider.dart';
import 'services/dead_mans_switch_service.dart';
import 'services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Local Encrypted Storage (Hive)
  await Hive.initFlutter();

  // ─── Encrypted Hive Setup ─────────────────────────────────────────────────
  // Generate or retrieve a 256-bit AES key from the platform keychain.
  // On Android this uses the Android Keystore system.
  // On iOS this uses the Secure Enclave / Keychain.
  // The key never leaves the secure hardware enclave.
  const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? aesKeyBase64 = await _secureStorage.read(key: 'hive_aes_key');
  if (aesKeyBase64 == null) {
    final key = Hive.generateSecureKey();
    aesKeyBase64 = base64Encode(key);
    await _secureStorage.write(key: 'hive_aes_key', value: aesKeyBase64);
  }
  final encryptionKey = HiveAesCipher(base64Decode(aesKeyBase64));

  // Open settings unencrypted (no secrets stored there)
  await Hive.openBox('settings');

  // Open secure_vault encrypted (stores JWT tokens, private keys, recipient public keys)
  await Hive.openBox('secure_vault', encryptionCipher: encryptionKey);

  // Initialize secure push notification service
  await PushNotificationService().initialize();

  // Check and trigger Dead Man's Switch (Auto-wipe on 30-day inactivity)
  await DeadMansSwitchService().checkAndTrigger();

  runApp(
    const ProviderScope(
      child: ChatlyApp(),
    ),
  );
}

class ChatlyApp extends ConsumerWidget {
  const ChatlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeProvider);
    final fontStyle = ref.watch(fontProvider);
    final themeData = ref.read(themeProvider.notifier).getThemeData(fontStyle);

    return MaterialApp(
      title: 'Chatly',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      home: const SplashScreen(),
    );
  }
}
