import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'features/auth/presentation/screens/splash_screen.dart';
import 'providers/theme_provider.dart';
import 'services/dead_mans_switch_service.dart';
import 'services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Local Encrypted Storage (Hive)
  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('secure_vault');

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
    // Observe theme & font updates
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
