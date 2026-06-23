import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/chat/presentation/screens/chat_list_screen.dart';
import '../features/groups/presentation/screens/groups_list_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../services/dead_mans_switch_service.dart';
import '../services/auth_service.dart';
import '../providers/layout_provider.dart';
import '../features/chat/presentation/screens/chat_screen.dart';
import '../features/groups/presentation/screens/group_chat_screen.dart';
import '../core/widgets/beautiful_avatar.dart';

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<ChatListScreenState> _chatListKey = GlobalKey<ChatListScreenState>();
  final GlobalKey<GroupsListScreenState> _groupsListKey = GlobalKey<GroupsListScreenState>();

  final _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      // Trigger rebuild to update FAB / actions when tab index changes
      if (_tabController.indexIsChanging) {
        setState(() {});
      }
    });

    _searchController.addListener(() {
      final q = _searchController.text;
      _chatListKey.currentState?.setSearchQuery(q);
      _groupsListKey.currentState?.setSearchQuery(q);
    });

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
    _tabController.dispose();
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final username = AuthService().username ?? 'Me';
    final textColor = theme.textTheme.bodyLarge?.color ?? const Color(0xFFE4E1ED);
    final subColor = theme.textTheme.bodyMedium?.color ?? const Color(0xFFC7C4D7);

    Widget buildDrawer() {
      return Drawer(
        backgroundColor: theme.scaffoldBackgroundColor,
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: theme.primaryColor,
              ),
              currentAccountPicture: BeautifulAvatar(
                name: username,
                username: username,
                radius: 36,
              ),
              accountName: Text(
                username,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
              accountEmail: const Text(
                'Signal Protocol E2EE',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.person_add_rounded, color: theme.iconTheme.color),
              title: const Text('Add Contact'),
              onTap: () {
                Navigator.of(context).pop();
                _chatListKey.currentState?.showAddContactSheet(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.group_add_rounded, color: theme.iconTheme.color),
              title: const Text('New Group'),
              onTap: () {
                Navigator.of(context).pop();
                _groupsListKey.currentState?.showCreateGroupDialog(context, theme);
              },
            ),
            ListTile(
              leading: Icon(Icons.settings_rounded, color: theme.iconTheme.color),
              title: const Text('Settings'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              },
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.of(context).pop();
                await AuthService().logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }

    Widget buildScaffold() {
      return Scaffold(
        drawer: buildDrawer(),
        appBar: AppBar(
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(color: textColor, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: _tabController.index == 0
                        ? 'Search chats or @username...'
                        : 'Search groups by name...',
                    hintStyle: TextStyle(color: subColor.withValues(alpha: 0.5)),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                )
              : Row(
                  children: [
                    const Text(
                      'Chatly',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shield_rounded, size: 10, color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Text(
                            'E2EE',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF10B981).withValues(alpha: 0.9),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
          leading: _isSearching
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () {
                    setState(() {
                      _isSearching = false;
                      _searchController.clear();
                    });
                  },
                )
              : Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                  ),
                ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: theme.primaryColor,
            indicatorSize: TabBarIndicatorSize.tab,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
            tabs: const [
              Tab(text: 'Chats'),
              Tab(text: 'Groups'),
            ],
          ),
          actions: [
            if (!_isSearching) ...[
              if (_tabController.index == 0)
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  onPressed: () {
                    _chatListKey.currentState?.scanQRCode();
                  },
                ),
              IconButton(
                icon: const Icon(Icons.search_rounded),
                onPressed: () {
                  setState(() => _isSearching = true);
                },
              ),
            ],
            if (_isSearching)
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _searchController.clear();
                },
              ),
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            ChatListScreen(key: _chatListKey, isEmbedded: true),
            GroupsListScreen(key: _groupsListKey, isEmbedded: true),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            if (_tabController.index == 0) {
              _chatListKey.currentState?.showAddContactSheet(context);
            } else {
              _groupsListKey.currentState?.showCreateGroupDialog(context, theme);
            }
          },
          backgroundColor: theme.primaryColor,
          elevation: 4,
          child: Icon(
            _tabController.index == 0 ? Icons.edit_rounded : Icons.group_add_rounded,
            color: Colors.white,
          ),
        ),
      );
    }

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
            child: buildScaffold(),
          ),
          const VerticalDivider(
              width: 1, thickness: 1, color: Colors.white10),
          Expanded(child: rightPane),
        ],
      );
    }

    // Single-pane mobile layout
    return buildScaffold();
  }
}
