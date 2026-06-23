import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'group_chat_screen.dart';
import '../../../../core/widgets/beautiful_avatar.dart';
import '../../../../providers/layout_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/encryption_service.dart';

class GroupsListScreen extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const GroupsListScreen({super.key, this.isEmbedded = false});

  @override
  ConsumerState<GroupsListScreen> createState() => GroupsListScreenState();
}

class GroupsListScreenState extends ConsumerState<GroupsListScreen> {
  Timer? _campfireTimer;
  final List<GroupItemData> _groups = [];
  bool _isLoading = false;
  String _searchQuery = '';

  void setSearchQuery(String query) {
    if (mounted) {
      setState(() {
        _searchQuery = query.toLowerCase().trim();
      });
    }
  }


  @override
  void initState() {
    super.initState();
    _loadGroups();
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

  /// Generates a random 32-byte AES-256 group key and stores it server-side
  /// wrapped (ECIES) under the creator's own DH identity public key.
  Future<void> _initGroupKey(String groupId) async {
    try {
      final secureBox = await Hive.openBox('secure_vault');
      final myDhPriv = secureBox.get('identity_dh_private_key') as String?;
      final myDhPub = secureBox.get('identity_dh_public_key') as String?;
      if (myDhPriv == null || myDhPub == null) return;

      final random = Random.secure();
      final groupKeyBytes = List<int>.generate(32, (_) => random.nextInt(256));

      // Cache decrypted key locally so we don't need to re-wrap immediately
      await secureBox.put('group_key_dec_$groupId', base64Encode(groupKeyBytes));

      // Wrap for self and store on server
      final wrappedForSelf = await EncryptionService().wrapGroupKey(
        groupKey: groupKeyBytes,
        recipientDhPublicBase64: myDhPub,
      );
      final myUsername = AuthService().username ?? '';
      await ApiService().distributeGroupKey(groupId, myUsername, wrappedForSelf);
    } catch (e) {
      debugPrint('_initGroupKey error: $e');
    }
  }

  Future<void> _loadGroups() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final raw = await ApiService().getGroups();
    final List<GroupItemData> temp = [];
    for (final g in raw) {
      final String id = g['id'] ?? '';
      final String name = g['name'] ?? '';
      final String desc = g['description'] ?? '';
      final int membersCount = int.tryParse(g['members_count']?.toString() ?? '1') ?? 1;
      
      final expiresAtStr = g['expires_at'];
      int? expiresAt;
      bool isCampfire = false;
      String? durationLabel;

      if (expiresAtStr != null) {
        try {
          final dt = DateTime.parse(expiresAtStr.toString()).toLocal();
          expiresAt = dt.millisecondsSinceEpoch;
          isCampfire = true;
          final diff = dt.difference(DateTime.now());
          if (diff.inMinutes <= 2) {
            durationLabel = '1m';
          } else if (diff.inHours <= 2) {
            durationLabel = '1h';
          } else if (diff.inHours <= 13) {
            durationLabel = '12h';
          } else {
            durationLabel = '24h';
          }
        } catch (_) {}
      }

      temp.add(GroupItemData(
        id: id,
        name: name,
        description: desc,
        membersCount: membersCount,
        lastMessage: isCampfire ? 'Campfire active.' : 'Start group chat.',
        time: 'Now',
        healthScore: 1.0,
        isCampfire: isCampfire,
        expiresAt: expiresAt,
        campfireDurationLabel: durationLabel,
      ));
    }

    if (mounted) {
      setState(() {
        _groups.clear();
        _groups.addAll(temp);
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _campfireTimer?.cancel();
    super.dispose();
  }

  Widget _buildMainBody(BuildContext context, ThemeData theme) {
    final filteredGroups = _searchQuery.isEmpty
        ? _groups
        : _groups.where((g) => g.name.toLowerCase().contains(_searchQuery)).toList();

    return Column(
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredGroups.isEmpty
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
                          Text(
                            _searchQuery.isEmpty ? 'No groups yet' : 'No matching groups',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE4E1ED),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              _searchQuery.isEmpty
                                  ? 'Create your first group or join one via a secure invite link.'
                                  : 'Try searching for another name.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
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
              padding: const EdgeInsets.only(top: 8, bottom: 100),
              itemCount: filteredGroups.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 80),
              itemBuilder: (context, index) {
                final group = filteredGroups[index];
                
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
                            groupId: group.id,
                            groupName: group.name,
                            isCampfire: group.isCampfire,
                            expiresAt: group.expiresAt,
                          ),
                        ),
                      ).then((_) => _loadGroups());
                    }
                  },
                  leading: BeautifulAvatar(
                    name: group.name,
                    username: group.id,
                    radius: 28,
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
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mainBody = _buildMainBody(context, theme);

    if (widget.isEmbedded) {
      return mainBody;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () {
              showCreateGroupDialog(context, theme);
            },
          ),
        ],
      ),
      body: mainBody,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: FloatingActionButton(
          mini: true,
          onPressed: () => showCreateGroupDialog(context, theme),
          backgroundColor: theme.primaryColor,
          tooltip: 'New Group',
          child: const Icon(Icons.group_add_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  void showCreateGroupDialog(BuildContext context, ThemeData theme) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool isCampfire = false;
    int campfireDurationMs = 3600000;
    bool creating = false;

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
                    'Limit: Create up to 25 groups, join up to 50. Discovery is strictly invite-only via secure QR codes or direct contacts.',
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
                        DropdownMenuItem(value: 3600000, child: Text('1 Hour')),
                        DropdownMenuItem(value: 43200000, child: Text('12 Hours')),
                        DropdownMenuItem(value: 86400000, child: Text('24 Hours')),
                      ],
                      onChanged: (val) {
                        dialogSetState(() {
                          campfireDurationMs = val ?? 3600000;
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
                    onPressed: creating
                        ? null
                        : () async {
                            final name = nameController.text.trim();
                            if (name.isEmpty) return;

                            dialogSetState(() => creating = true);
                            final desc = descController.text.trim();

                            final res = await ApiService().createGroup(
                              name: name,
                              description: desc,
                              isCampfire: isCampfire,
                              durationMs: isCampfire ? campfireDurationMs : null,
                            );

                            if (res != null) {
                              final newGroupId = res['id'] as String? ?? '';
                              if (newGroupId.isNotEmpty) {
                                await _initGroupKey(newGroupId);
                              }
                              await _loadGroups();
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Group "$name" created successfully.'),
                                    backgroundColor: const Color(0xFF10B981),
                                  ),
                                );
                              }
                            } else {
                              dialogSetState(() => creating = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Failed to create group. Check limits or connection.'),
                                    backgroundColor: Color(0xFFEF4444),
                                  ),
                                );
                              }
                            }
                          },
                    child: creating
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Create Room', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
  final String id;
  final String name;
  final String description;
  final int membersCount;
  final String lastMessage;
  final String time;
  final double healthScore;
  final bool isCampfire;
  final int? expiresAt;
  final String? campfireDurationLabel;

  GroupItemData({
    required this.id,
    required this.name,
    required this.description,
    required this.membersCount,
    required this.lastMessage,
    required this.time,
    required this.healthScore,
    this.isCampfire = false,
    this.expiresAt,
    this.campfireDurationLabel,
  });
}
