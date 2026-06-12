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
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? aesKeyBase64;
  bool hasSecurityError = false;
  String? securityErrorMsg;

  try {
    aesKeyBase64 = await secureStorage.read(key: 'hive_aes_key');
    if (aesKeyBase64 == null) {
      final key = Hive.generateSecureKey();
      aesKeyBase64 = base64Encode(key);
      await secureStorage.write(key: 'hive_aes_key', value: aesKeyBase64);
    }
  } catch (e) {
    debugPrint('Secure storage error, attempting reset: $e');
    try {
      await secureStorage.deleteAll();
      final key = Hive.generateSecureKey();
      aesKeyBase64 = base64Encode(key);
      await secureStorage.write(key: 'hive_aes_key', value: aesKeyBase64);
    } catch (err) {
      debugPrint('Secure storage recovery failed: $err');
      hasSecurityError = true;
      securityErrorMsg = err.toString();
    }
  }

  if (hasSecurityError) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: const Color(0xFF13131B),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      size: 64,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Security Initialization Failed',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE4E1ED),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'The secure hardware storage (Keystore/Keychain) on this device could not be initialized. '
                      'To protect your privacy and keys, Chatly cannot proceed.\n\nError details: $securityErrorMsg',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  final encryptionKey = HiveAesCipher(base64Decode(aesKeyBase64!));

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
