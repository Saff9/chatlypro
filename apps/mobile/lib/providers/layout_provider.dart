import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../features/chat/presentation/screens/chat_list_screen.dart';

// Selection providers for desktop/web split-screen layout
final selectedChatProvider = StateProvider<ChatListItemData?>((ref) => null);
final selectedGroupProvider = StateProvider<dynamic>((ref) => null);

final tabOrderProvider = StateNotifierProvider<TabOrderNotifier, List<String>>((ref) {
  return TabOrderNotifier();
});

class TabOrderNotifier extends StateNotifier<List<String>> {
  TabOrderNotifier() : super(_loadTabOrder());

  static List<String> _loadTabOrder() {
    try {
      final box = Hive.box('settings');
      final raw = box.get('tab_order', defaultValue: ['chats', 'groups', 'settings']) as List;
      // Filter out removed tabs (pulse) from any persisted settings
      final allowed = {'chats', 'groups', 'settings'};
      final filtered = raw.cast<String>().where((t) => allowed.contains(t)).toList();
      return filtered.isNotEmpty ? filtered : ['chats', 'groups', 'settings'];
    } catch (_) {
      return ['chats', 'groups', 'settings'];
    }
  }

  Future<void> updateTabOrder(List<String> newOrder) async {
    state = newOrder;
    try {
      final box = Hive.box('settings');
      await box.put('tab_order', newOrder);
    } catch (_) {
      // Fail silently to prevent database lock crash
    }
  }
}
