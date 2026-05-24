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
      final list = box.get('tab_order', defaultValue: ['chats', 'groups', 'pulse', 'settings']) as List;
      return List<String>.from(list);
    } catch (_) {
      return ['chats', 'groups', 'pulse', 'settings'];
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
