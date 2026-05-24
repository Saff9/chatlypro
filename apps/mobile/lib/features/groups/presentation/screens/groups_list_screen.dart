import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'group_chat_screen.dart';
import '../../../../providers/layout_provider.dart';

class GroupsListScreen extends ConsumerStatefulWidget {
  const GroupsListScreen({super.key});

  @override
  ConsumerState<GroupsListScreen> createState() => _GroupsListScreenState();
}

class _GroupsListScreenState extends ConsumerState<GroupsListScreen> {
  Timer? _campfireTimer;

  // Groups are populated as the user creates or joins them.
  // Starting with an empty list is the correct production behavior.
  final List<GroupItemData> _groups = [];

  @override
  void initState() {
    super.initState();
    _campfireTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final expired = <GroupItemData>[];
      for (final g in _groups) {
        if (g.isCampfire && g.expiresAt != null && now >= g.expiresAt!) {
          expired.add(g);
        }
      }

      if (expired.isNotEmpty) {
        setState(() {
          for (final g in expired) {
            _groups.remove(g);
          }
        });
        for (final g in expired) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🔥 Campfire Group "${g.name}" dissolved and database logs shredded.'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      } else {
        if (_groups.any((g) => g.isCampfire)) {
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _campfireTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () {
              _showCreateGroupDialog(context, theme);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.primaryColor.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.security_rounded, color: Color(0xFF6366F1), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Groups are fully end-to-end encrypted and private. Supported entirely by voluntary sponsorships.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
           Expanded(
            child: _groups.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF10B981).withValues(alpha: 0.08),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.groups_outlined,
                              size: 40,
                              color: Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'No groups yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE4E1ED),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              'Create your first group or join one via a secure invite link.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFFC7C4D7),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _groups.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 80),
              itemBuilder: (context, index) {
                final group = _groups[index];
                
                Color healthColor;
                if (group.healthScore > 0.8) {
                  healthColor = const Color(0xFF10B981); // High
                } else if (group.healthScore > 0.4) {
                  healthColor = const Color(0xFFF59E0B); // Medium
                } else {
                  healthColor = const Color(0xFFEF4444); // Low
                }

                String campfireTimeLabel = '';
                if (group.isCampfire && group.expiresAt != null) {
                  final remaining = group.expiresAt! - DateTime.now().millisecondsSinceEpoch;
                  if (remaining > 0) {
                    final totalSecs = (remaining / 1000).ceil();
                    final mins = totalSecs ~/ 60;
                    final secs = totalSecs % 60;
                    campfireTimeLabel = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
                  } else {
                    campfireTimeLabel = 'Expired';
                  }
                }

                return ListTile(
                  onTap: () {
                    if (MediaQuery.of(context).size.width > 900) {
                      ref.read(selectedChatProvider.notifier).state = null;
                      ref.read(selectedGroupProvider.notifier).state = group;
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => GroupChatScreen(
                            groupName: group.name,
                            isCampfire: group.isCampfire,
                            expiresAt: group.expiresAt,
                          ),
                        ),
                      );
                    }
                  },
                  leading: CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.primaryColor.withValues(alpha: 0.08),
                    child: Text(
                      group.name[0],
                      style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (group.isCampfire) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.local_fire_department_rounded, color: Color(0xFFEF4444), size: 16),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        '(${group.membersCount} members)',
                        style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: healthColor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Health Score: ${(group.healthScore * 100).toInt()}%',
                              style: TextStyle(fontSize: 10, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  trailing: group.isCampfire
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              campfireTimeLabel,
                              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'CAMPFIRE',
                              style: TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                            ),
                          ],
                        )
                      : Text(
                          group.time,
                          style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6), fontSize: 12),
                        ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateGroupDialog(context, theme),
        backgroundColor: theme.primaryColor,
        icon: const Icon(Icons.group_add_rounded, color: Colors.white),
        label: const Text('New Group', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context, ThemeData theme) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool isCampfire = false;
    int campfireDurationMs = 60000; // Default: 1 minute (Test Mode)

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF13131B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'New Group Room',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Text(
                    'Limit: Create up to 10 groups, join up to 50. Discovery is strictly invite-only via secure QR codes or direct contacts.',
                    style: TextStyle(fontSize: 10, color: Colors.white38, height: 1.3),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Enter group room name',
                      hintStyle: const TextStyle(color: Colors.white30),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Optional description',
                      hintStyle: const TextStyle(color: Colors.white30),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('Campfire Mode (Temporary)', style: TextStyle(color: Colors.white, fontSize: 13)),
                    subtitle: const Text('Auto-dissolves group and shreds database logs', style: TextStyle(color: Colors.white30, fontSize: 10)),
                    value: isCampfire,
                    activeColor: theme.primaryColor,
                    onChanged: (val) {
                      dialogSetState(() {
                        isCampfire = val ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (isCampfire) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: campfireDurationMs,
                      dropdownColor: const Color(0xFF13131B),
                      decoration: InputDecoration(
                        labelText: 'Auto-Dissolve Duration',
                        labelStyle: const TextStyle(color: Colors.white60, fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        fillColor: Colors.white.withValues(alpha: 0.04),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: const [
                        DropdownMenuItem(value: 60000, child: Text('1 Minute (Test Mode)')),
                        DropdownMenuItem(value: 3600000, child: Text('1 Hour')),
                        DropdownMenuItem(value: 43200000, child: Text('12 Hours')),
                        DropdownMenuItem(value: 86400000, child: Text('24 Hours')),
                      ],
                      onChanged: (val) {
                        dialogSetState(() {
                          campfireDurationMs = val ?? 60000;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      final name = nameController.text.trim();
                      if (name.isNotEmpty) {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final int? expiresAt = isCampfire ? now + campfireDurationMs : null;
                        String? durationLabel;
                        if (isCampfire) {
                          if (campfireDurationMs == 60000) durationLabel = '1m';
                          if (campfireDurationMs == 3600000) durationLabel = '1h';
                          if (campfireDurationMs == 43200000) durationLabel = '12h';
                          if (campfireDurationMs == 86400000) durationLabel = '24h';
                        }

                        setState(() {
                          _groups.add(GroupItemData(
                            name: name,
                            membersCount: 1,
                            lastMessage: 'You created the group.',
                            time: 'Now',
                            healthScore: 1.0,
                            isCampfire: isCampfire,
                            expiresAt: expiresAt,
                            campfireDurationLabel: durationLabel,
                          ));
                        });
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isCampfire
                                ? 'Campfire Group "$name" created (auto-dissolves in $durationLabel).'
                                : 'Group "$name" created room.'),
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
                      }
                    },
                    child: const Text('Create Room', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      nameController.dispose();
      descController.dispose();
    });
  }
}

class GroupItemData {
  final String name;
  final int membersCount;
  final String lastMessage;
  final String time;
  final double healthScore;
  final bool isCampfire;
  final int? expiresAt;
  final String? campfireDurationLabel;

  GroupItemData({
    required this.name,
    required this.membersCount,
    required this.lastMessage,
    required this.time,
    required this.healthScore,
    this.isCampfire = false,
    this.expiresAt,
    this.campfireDurationLabel,
  });
}
