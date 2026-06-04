import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/chat/presentation/screens/chat_list_screen.dart';
import '../features/groups/presentation/screens/groups_list_screen.dart';
import '../features/anonymous/presentation/screens/anonymous_feed_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../services/shake_service.dart';
import '../features/auth/presentation/screens/calculator_screen.dart';
import '../services/dead_mans_switch_service.dart';
import '../providers/layout_provider.dart';
import '../features/chat/presentation/screens/chat_screen.dart';
import '../features/groups/presentation/screens/group_chat_screen.dart';

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation> with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    DeadMansSwitchService().updateLastActive();

    ShakeService().startListening(() {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const CalculatorScreen()),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DeadMansSwitchService().updateLastActive();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShakeService().stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabOrder = ref.watch(tabOrderProvider);

    Widget getScreen(String key) {
      switch (key) {
        case 'chats':
          return const ChatListScreen();
        case 'groups':
          return const GroupsListScreen();
        case 'pulse':
          return const AnonymousFeedScreen();
        case 'settings':
          return const SettingsScreen();
        default:
          return const ChatListScreen();
      }
    }

    NavigationDestination getDestination(String key) {
      switch (key) {
        case 'chats':
          return NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded, color: theme.textTheme.bodyMedium?.color, size: 20),
            selectedIcon: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF6366F1), size: 20),
            label: 'Chats',
          );
        case 'groups':
          return NavigationDestination(
            icon: Icon(Icons.groups_outlined, color: theme.textTheme.bodyMedium?.color, size: 20),
            selectedIcon: const Icon(Icons.groups_rounded, color: Color(0xFF6366F1), size: 20),
            label: 'Groups',
          );
        case 'pulse':
          return NavigationDestination(
            icon: Icon(Icons.masks_outlined, color: theme.textTheme.bodyMedium?.color, size: 20),
            selectedIcon: const Icon(Icons.masks_rounded, color: Color(0xFFF59E0B), size: 20),
            label: 'Pulse',
          );
        case 'settings':
          return NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: theme.textTheme.bodyMedium?.color, size: 20),
            selectedIcon: const Icon(Icons.settings_rounded, color: Color(0xFF10B981), size: 20),
            label: 'Settings',
          );
        default:
          return NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded, color: theme.textTheme.bodyMedium?.color, size: 20),
            selectedIcon: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF6366F1), size: 20),
            label: 'Chats',
          );
      }
    }

    final screens = tabOrder.map((key) => getScreen(key)).toList();
    final destinations = tabOrder.map((key) => getDestination(key)).toList();

    if (_currentIndex >= screens.length) {
      _currentIndex = 0;
    }

    final width = MediaQuery.of(context).size.width;

    if (width > 900) {
      final selectedChat = ref.watch(selectedChatProvider);
      final selectedGroup = ref.watch(selectedGroupProvider);

      Widget rightPane;
      if (selectedChat != null) {
        rightPane = ChatScreen(key: ValueKey('chat_${selectedChat.username}'), chatData: selectedChat);
      } else if (selectedGroup != null) {
        rightPane = GroupChatScreen(
          key: ValueKey('group_${selectedGroup.id}'),
          groupId: selectedGroup.id,
          groupName: selectedGroup.name,
          isCampfire: selectedGroup.isCampfire,
          expiresAt: selectedGroup.expiresAt,
        );
      } else {
        rightPane = Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.primaryColor.withValues(alpha: 0.08),
                    border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2), width: 2),
                  ),
                  child: Icon(Icons.chat_bubble_outline_rounded, size: 48, color: theme.primaryColor),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select a conversation to start messaging',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'Fully encrypted and zero-knowledge.',
                  style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
        );
      }

      return Row(
        children: [
          SizedBox(
            width: 420,
            child: Scaffold(
              body: IndexedStack(
                index: _currentIndex,
                children: screens,
              ),
              bottomNavigationBar: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: NavigationBarTheme(
                      data: NavigationBarThemeData(
                        labelTextStyle: WidgetStateProperty.all(
                          const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                      ),
                      child: NavigationBar(
                        height: 58.0,
                        selectedIndex: _currentIndex,
                        onDestinationSelected: (index) {
                          setState(() {
                            _currentIndex = index;
                          });
                        },
                        backgroundColor: theme.cardColor.withValues(alpha: 0.8),
                        elevation: 0,
                        indicatorColor: theme.primaryColor.withValues(alpha: 0.15),
                        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                        destinations: destinations,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: Colors.white10),
          Expanded(child: rightPane),
        ],
      );
    }

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                labelTextStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                ),
              ),
              child: NavigationBar(
                height: 58.0,
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                backgroundColor: theme.cardColor.withValues(alpha: 0.8),
                elevation: 0,
                indicatorColor: theme.primaryColor.withValues(alpha: 0.15),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: destinations,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
