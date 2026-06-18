import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/chat/presentation/screens/chat_list_screen.dart';
import '../features/groups/presentation/screens/groups_list_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../services/dead_mans_switch_service.dart';
import '../providers/layout_provider.dart';
import '../features/chat/presentation/screens/chat_screen.dart';
import '../features/groups/presentation/screens/group_chat_screen.dart';

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeadMansSwitchService().updateLastActive();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Three tabs: Chats · Groups · Settings
    const tabs = ['chats', 'groups', 'settings'];

    Widget getScreen(String key) {
      switch (key) {
        case 'groups':
          return const GroupsListScreen();
        case 'settings':
          return const SettingsScreen();
        case 'chats':
        default:
          return const ChatListScreen();
      }
    }

    NavigationDestination getDestination(String key) {
      switch (key) {
        case 'groups':
          return NavigationDestination(
            icon: Icon(CupertinoIcons.group,
                color: theme.textTheme.bodyMedium?.color, size: 20),
            selectedIcon: const Icon(CupertinoIcons.group_solid,
                color: Color(0xFF8083FF), size: 20),
            label: 'Groups',
          );
        case 'settings':
          return NavigationDestination(
            icon: Icon(CupertinoIcons.settings,
                color: theme.textTheme.bodyMedium?.color, size: 20),
            selectedIcon: const Icon(CupertinoIcons.settings_solid,
                color: Color(0xFF10B981), size: 20),
            label: 'Settings',
          );
        case 'chats':
        default:
          return NavigationDestination(
            icon: Icon(CupertinoIcons.chat_bubble,
                color: theme.textTheme.bodyMedium?.color, size: 20),
            selectedIcon: const Icon(CupertinoIcons.chat_bubble_fill,
                color: Color(0xFF8083FF), size: 20),
            label: 'Chats',
          );
      }
    }

    final screens = tabs.map(getScreen).toList();
    final destinations = tabs.map(getDestination).toList();

    if (_currentIndex >= screens.length) _currentIndex = 0;

    Widget buildNavBar() => Container(
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
                    const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w500),
                  ),
                ),
                child: NavigationBar(
                  height: 58.0,
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (index) {
                    setState(() => _currentIndex = index);
                  },
                  backgroundColor:
                      theme.cardColor.withValues(alpha: 0.8),
                  elevation: 0,
                  indicatorColor:
                      theme.primaryColor.withValues(alpha: 0.15),
                  labelBehavior:
                      NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: destinations,
                ),
              ),
            ),
          ),
        );

    final width = MediaQuery.of(context).size.width;

    // Wide-screen two-pane layout (tablet/desktop)
    if (width > 900) {
      final selectedChat = ref.watch(selectedChatProvider);
      final selectedGroup = ref.watch(selectedGroupProvider);

      Widget rightPane;
      if (selectedChat != null) {
        rightPane = ChatScreen(
          key: ValueKey('chat_${selectedChat.username}'),
          chatData: selectedChat,
        );
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
                    border: Border.all(
                        color: theme.primaryColor.withValues(alpha: 0.2),
                        width: 2),
                  ),
                  child: Icon(CupertinoIcons.chat_bubble,
                      size: 48, color: theme.primaryColor),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select a conversation to start messaging',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'Signal Protocol E2EE — zero-knowledge relay.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodyMedium?.color
                        ?.withValues(alpha: 0.5),
                  ),
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
              bottomNavigationBar: buildNavBar(),
            ),
          ),
          const VerticalDivider(
              width: 1, thickness: 1, color: Colors.white10),
          Expanded(child: rightPane),
        ],
      );
    }

    // Single-pane mobile layout
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: buildNavBar(),
    );
  }
}
