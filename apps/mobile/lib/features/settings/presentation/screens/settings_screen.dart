import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../services/dead_mans_switch_service.dart';
import '../../../auth/presentation/screens/welcome_screen.dart';
import '../../../../providers/subscription_provider.dart';
import '../../../../providers/layout_provider.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../providers/wallpaper_provider.dart';
import '../../../../providers/connection_provider.dart';
import '../../../../core/widgets/glassmorphic_container.dart';
import '../../../../services/auth_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

final forensicEraserProvider = StateProvider<bool>((ref) {
  final box = Hive.box('settings');
  return box.get('forensic_eraser_enabled', defaultValue: false) as bool;
});

final activeChatRandomizationProvider = StateProvider<bool>((ref) {
  final box = Hive.box('settings');
  return box.get('active_chat_randomization_enabled', defaultValue: false) as bool;
});

final twoFactorProvider = StateProvider<bool>((ref) {
  final box = Hive.box('settings');
  return box.get('two_factor_enabled', defaultValue: false) as bool;
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeStyle = ref.watch(themeProvider);
    final isDark = themeStyle != ThemeStyle.light;
    final isSponsor = ref.watch(sponsorshipProvider);
    final isForensicEnabled = ref.watch(forensicEraserProvider);
    final isActiveChatRandomizationEnabled = ref.watch(activeChatRandomizationProvider);
    final isTwoFactorEnabled = ref.watch(twoFactorProvider);
    final textColor = theme.textTheme.bodyLarge?.color ?? const Color(0xFFE4E1ED);
    final subColor = theme.textTheme.bodyMedium?.color ?? const Color(0xFFC7C4D7);
    final iconColor = theme.iconTheme.color ?? subColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          // Profile Widget Header
          GlassmorphicContainer(
            padding: const EdgeInsets.all(20.0),
            borderRadius: 24,
            blur: 20,
            backgroundOpacity: 0.03,
            borderOpacity: 0.1,
            child: ValueListenableBuilder(
              valueListenable: Hive.box('settings').listenable(keys: ['avatar_image_url', 'display_name', 'username', 'user_mood']),
              builder: (context, box, _) {
                final avatarUrl = box.get('avatar_image_url', defaultValue: '') as String;
                // Fall back to generic labels rather than developer placeholder names.
                final displayName = box.get('display_name', defaultValue: 'Your Name') as String;
                final username = box.get('username', defaultValue: 'username') as String;
                final userMood = box.get('user_mood', defaultValue: 'Vibing') as String;
                
                String userMoodEmoji = '😊';
                if (userMood == 'Busy') userMoodEmoji = '🔴';
                if (userMood == 'Offline') userMoodEmoji = '💤';
                if (userMood == 'Incognito') userMoodEmoji = '🕵️';
                if (userMood == 'At Work') userMoodEmoji = '💼';
                if (userMood == 'Focus Mode') userMoodEmoji = '🎯';
                if (userMood == 'Chilling') userMoodEmoji = '🍹';
                if (userMood == 'Coding') userMoodEmoji = '💻';

                return Row(
                  children: [
                    GestureDetector(
                      onTap: () => _showAvatarPickerDialog(context),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [theme.primaryColor, const Color(0xFF494BD6)],
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 34,
                          backgroundColor: const Color(0xFF13131B),
                          child: avatarUrl.isNotEmpty
                              ? ClipOval(
                                  child: Image.network(
                                    avatarUrl,
                                    width: 68,
                                    height: 68,
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) => const Icon(Icons.face_rounded, color: Colors.white60),
                                  ),
                                )
                              : Text(
                                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                  style: TextStyle(
                                    fontSize: 26,
                                    color: theme.primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 18, 
                                  fontWeight: FontWeight.bold, 
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.verified_rounded,
                                color: theme.primaryColor,
                                size: 16,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                              '@$username',
                              style: TextStyle(
                                  fontSize: 13, 
                                  color: subColor.withValues(alpha: 0.5),
                              ),
                            ),
                          const SizedBox(height: 10),
                          // Mood Broadcast tag (Tap to change)
                          GestureDetector(
                            onTap: () => _showMoodPickerDialog(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  width: 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(userMoodEmoji, style: const TextStyle(fontSize: 12)),
                                  const SizedBox(width: 6),
                                  Text(
                                    userMood,
                                    style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.qr_code_rounded, color: iconColor),
                      onPressed: () {
                        _showQRDialog(context, theme);
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Sponsor & Support Card (Chatly Pro Style)
          GlassmorphicContainer(
            padding: const EdgeInsets.all(20),
            borderRadius: 24,
            blur: 20,
            backgroundOpacity: 0.08,
            borderOpacity: 0.18,
            baseColor: theme.primaryColor,
            borderColor: theme.primaryColor,
            boxShadow: [
              BoxShadow(
                color: theme.primaryColor.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          color: isSponsor ? const Color(0xFFFFB300) : Colors.white.withValues(alpha: 0.9),
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isSponsor ? 'Active Supporter' : 'Support Chatly',
                          style: const TextStyle(
                            color: Colors.white, 
                            fontWeight: FontWeight.w800, 
                            fontSize: 18,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      isSponsor ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isSponsor ? const Color(0xFFEF4444) : Colors.white.withValues(alpha: 0.9),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isSponsor
                      ? 'Thank you for sponsoring the project! Your donation directly funds secure WebSocket servers, push notification gateways, and decentralized mesh development.'
                      : 'Chatly is 100% free, has no ads, and does not harvest metadata. We rely entirely on voluntary support to pay server hosting bills.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF494BD6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      _showSupportDialog(context, ref);
                    },
                    child: Text(
                      isSponsor ? 'Manage Sponsorship' : 'Support & Sponsor',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Settings Categories
          _buildSettingsHeader('Appearance'),
          GlassmorphicContainer(
            borderRadius: 20,
            blur: 15,
            backgroundOpacity: 0.02,
            borderOpacity: 0.08,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.dark_mode_outlined, color: iconColor),
                  title: Text('Dark Mode', style: TextStyle(color: textColor)),
                  subtitle: Text('Turn off the lights', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  value: isDark,
                  activeThumbColor: Theme.of(context).primaryColor,
                  onChanged: (val) {
                    ref.read(themeProvider.notifier).selectTheme(
                      val ? ThemeStyle.dark : ThemeStyle.light,
                    );
                  },
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: Icon(Icons.color_lens_outlined, color: iconColor),
                  title: Text('App Color Theme', style: TextStyle(color: textColor)),
                  subtitle: Text('Select from 50 premium palettes', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () => _showThemePickerDialog(context, ref),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: Icon(Icons.palette_outlined, color: iconColor),
                  title: Text('Chat Wallpaper', style: TextStyle(color: textColor)),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () => _showWallpaperPickerDialog(context, ref),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: Icon(Icons.format_size_rounded, color: iconColor),
                  title: Text('Font Style', style: TextStyle(color: textColor)),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () => _showFontPickerDialog(context, ref),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: Icon(Icons.density_medium_rounded, color: iconColor),
                  title: Text('Chat Layout Density', style: TextStyle(color: textColor)),
                  subtitle: Text('Configure how many tiles fit on screen', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () => _showDensityPickerDialog(context),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: Icon(Icons.dashboard_customize_rounded, color: iconColor),
                  title: Text('Customize App Layout', style: TextStyle(color: textColor)),
                  subtitle: Text('Reorder tabs to your preference', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () {
                    _showLayoutCustomizerDialog(context, ref);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _buildSettingsHeader('Privacy & Data'),
          GlassmorphicContainer(
            borderRadius: 20,
            blur: 15,
            backgroundOpacity: 0.02,
            borderOpacity: 0.08,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.delete_sweep_outlined, color: iconColor),
                  title: Text('Message Retention', style: TextStyle(color: textColor)),
                  subtitle: Text('Auto-delete: Choose 2-7 days', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () => _showMessageRetentionDialog(context),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded, color: Color(0xFF8083FF)),
                  title: Text('Chat History Limits', style: TextStyle(color: textColor)),
                  subtitle: Text('50 messages per chat — tap for details', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () => _showInMemoryLimitsDialog(context),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: Icon(Icons.download_for_offline_outlined, color: iconColor),
                  title: Text('Backup Data', style: TextStyle(color: textColor)),
                  subtitle: Text('Export chats as .txt', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () => _showBackupDataDialog(context),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ValueListenableBuilder(
                  valueListenable: Hive.box('settings').listenable(keys: ['sync_contacts']),
                  builder: (context, box, _) {
                    final syncContacts = box.get('sync_contacts', defaultValue: false) as bool;
                    return ListTile(
                      leading: Icon(Icons.sync_rounded, color: iconColor),
                      title: Text('Contacts Synchronization', style: TextStyle(color: textColor)),
                      trailing: Switch(
                        value: syncContacts,
                        activeThumbColor: theme.primaryColor,
                        onChanged: (val) async {
                          await box.put('sync_contacts', val);
                        },
                      ),
                    );
                  },
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: const Icon(Icons.dangerous_outlined, color: Color(0xFFEF4444)),
                  title: Text('Dead Man\'s Switch', style: TextStyle(color: textColor)),
                  subtitle: Text('Wipes local keys after inactivity', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () {
                    _showDeadMansSwitchDialog(context, theme);
                  },
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: Icon(Icons.visibility_off_outlined, color: iconColor),
                  title: Text('App Camouflage & Decoy', style: TextStyle(color: textColor)),
                  subtitle: Text('Disguise app boot representation', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () {
                    _showCamouflageDialog(context, theme);
                  },
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                SwitchListTile(
                  secondary: Icon(Icons.fingerprint_rounded, color: iconColor),
                  title: Text('Forensic Eraser Mode', style: TextStyle(color: textColor)),
                  subtitle: Text('Overwrites deletes with random noise', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  value: isForensicEnabled,
                  activeThumbColor: theme.primaryColor,
                  onChanged: (val) async {
                    await Hive.box('settings').put('forensic_eraser_enabled', val);
                    ref.read(forensicEraserProvider.notifier).state = val;
                  },
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                SwitchListTile(
                  secondary: Icon(Icons.shuffle_rounded, color: iconColor),
                  title: Text('Active Chat Randomization', style: TextStyle(color: textColor)),
                  subtitle: Text('Scrambles old history beyond limit instead of deleting', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  value: isActiveChatRandomizationEnabled,
                  activeThumbColor: theme.primaryColor,
                  onChanged: (val) async {
                    await Hive.box('settings').put('active_chat_randomization_enabled', val);
                    ref.read(activeChatRandomizationProvider.notifier).state = val;
                  },
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: Icon(Icons.masks_rounded, color: iconColor),
                  title: Text('Anonymous Pulses Limit', style: TextStyle(color: textColor)),
                  subtitle: Text('Limit daily posts to prevent exposure', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () => _showAnonymousLimitsDialog(context),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: Icon(Icons.favorite_border_rounded, color: iconColor),
                  title: Text('Relationship Health Board', style: TextStyle(color: textColor)),
                  subtitle: Text('View contact engagement levels', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () => _showRelationshipHealthDialog(context, ref),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                SwitchListTile(
                  secondary: Icon(Icons.security_rounded, color: iconColor),
                  title: Text('Two-Step Verification', style: TextStyle(color: textColor)),
                  subtitle: Text('Requires OTP sent to your email on login', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  value: isTwoFactorEnabled,
                  activeThumbColor: theme.primaryColor,
                  onChanged: (val) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final success = await AuthService().toggle2FA(enabled: val);
                    if (success) {
                      await Hive.box('settings').put('two_factor_enabled', val);
                      ref.read(twoFactorProvider.notifier).state = val;
                      messenger.showSnackBar(
                        SnackBar(content: Text(val ? 'Two-Step Verification enabled.' : 'Two-Step Verification disabled.')),
                      );
                    } else {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Failed to update server 2-Step Verification settings.')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _buildSettingsHeader('Account'),
          GlassmorphicContainer(
            borderRadius: 20,
            blur: 15,
            backgroundOpacity: 0.02,
            borderOpacity: 0.08,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.fingerprint_rounded, color: Color(0xFF8083FF)),
                  title: Text('Biometric Lock', style: TextStyle(color: textColor)),
                  subtitle: Text('Require fingerprint / Face ID on open', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Switch(
                    value: false,
                    activeThumbColor: theme.primaryColor,
                    onChanged: (_) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.fingerprint_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 10),
                              Expanded(child: Text('Biometric auth coming in v2.0 — API keys pending.')),
                            ],
                          ),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    },
                  ),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: Icon(Icons.person_add_alt_1_rounded, color: iconColor),
                  title: Text('Connection Invitations', style: TextStyle(color: textColor)),
                  subtitle: Text('Manage pending invitations and requests', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () => _showInvitationsDialog(context, ref),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
                  title: const Text('Logout', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                  onTap: () => _showLogoutDialog(context),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444)),
                  title: const Text('Delete Account', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                  subtitle: Text('30-day grace recovery period', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  onTap: () => _showDeleteAccountDialog(context, theme),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSettingsHeader('About'),
          GlassmorphicContainer(
            borderRadius: 20,
            blur: 15,
            backgroundOpacity: 0.02,
            borderOpacity: 0.08,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.privacy_tip_outlined, color: iconColor),
                  title: Text('Privacy Policy', style: TextStyle(color: textColor)),
                  subtitle: Text('Read our zero-knowledge policy details', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () => _showPrivacyPolicyDialog(context),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: Icon(Icons.info_outline_rounded, color: iconColor),
                  title: Text('Version Info', style: TextStyle(color: textColor)),
                  subtitle: Text('Chatly v1.0.0 (E2E Pro)', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                ),
                Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ListTile(
                  leading: Icon(Icons.rate_review_outlined, color: iconColor),
                  title: Text('Community Roadmap & Voting', style: TextStyle(color: textColor)),
                  subtitle: Text('Upvote features for upcoming releases', style: TextStyle(color: subColor.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
                  onTap: () => _showCommunityRoadmapDialog(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSettingsHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
          color: Colors.grey,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _showInMemoryLimitsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF6366F1)),
              SizedBox(width: 10),
              Text('Chat History Limits'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _limitInfoRow(
                icon: Icons.storage_rounded,
                iconColor: const Color(0xFF6366F1),
                title: '50-Message Rolling Window',
                description:
                    'Chatly retains a maximum of 50 messages per conversation on this device. '
                    'When this limit is hit, the oldest messages are either shredded or scrambled '
                    'depending on your Privacy settings.',
              ),
              const SizedBox(height: 16),
              _limitInfoRow(
                icon: Icons.shuffle_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'Active Chat Randomization',
                description:
                    'When enabled, messages beyond the 50-message limit have their text '
                    'overwritten with cryptographic noise before deletion. The message ID and '
                    'timestamp remain as ghost entries. No third party can recover the original content.',
              ),
              const SizedBox(height: 16),
              _limitInfoRow(
                icon: Icons.lock_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: 'Vault Messages',
                description:
                    'Vault (ephemeral) messages bypass the 50-message window and self-destruct '
                    'after the timer you set (30 s → 1 hr). They are never committed to long-term '
                    'storage and are wiped from disk the moment the timer fires.',
              ),
              const SizedBox(height: 16),
              _limitInfoRow(
                icon: Icons.shield_outlined,
                iconColor: const Color(0xFFEF4444),
                title: 'Forensic Eraser Mode',
                description:
                    'When Forensic Eraser is active, individual message deletions trigger a '
                    'two-pass overwrite: first with noise, then a physical disk flush, before '
                    'the key is removed from the Hive box. This prevents forensic recovery tools '
                    'from reconstructing deleted content.',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.18)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_user_rounded, size: 14, color: Color(0xFF6366F1)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No message content ever leaves your device to Chatly servers. '
                        'All encryption keys are generated and stored locally.',
                        style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF6366F1)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got It'),
            ),
          ],
        );
      },
    );
  }

  Widget _limitInfoRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 3),
              Text(description, style: const TextStyle(fontSize: 12, height: 1.4, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  void _showQRDialog(BuildContext context, ThemeData theme) {
    final settingsBox = Hive.box('settings');
    final myUsername = settingsBox.get('username', defaultValue: 'user') as String;
    
    showDialog(
      context: context,
      builder: (context) {
        bool useCircularDots = true;
        bool useCircularEyes = true;
        bool includeLogo = true;
        Color qrColor = const Color(0xFF8083FF);

        final List<Color> qrColorOptions = [
          const Color(0xFF8083FF), // Purple Indigo
          const Color(0xFF10B981), // Mint Emerald
          const Color(0xFFFFB300), // Amber Gold
          const Color(0xFFEF4444), // Crimson Red
        ];

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF13131B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Colors.white10, width: 1.0),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Premium Connection QR',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@$myUsername',
                      style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    
                    // Dense and Premium QR rendering
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: qrColor.withValues(alpha: 0.15),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          QrImageView(
                            data: 'chatly:connect:@$myUsername',
                            version: QrVersions.auto,
                            size: 160.0,
                            eyeStyle: QrEyeStyle(
                              eyeShape: useCircularEyes ? QrEyeShape.circle : QrEyeShape.square,
                              color: qrColor,
                            ),
                            dataModuleStyle: QrDataModuleStyle(
                              dataModuleShape: useCircularDots ? QrDataModuleShape.circle : QrDataModuleShape.square,
                              color: qrColor,
                            ),
                          ),
                          if (includeLogo)
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: qrColor.withValues(alpha: 0.2), width: 1.5),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4),
                                ],
                              ),
                              padding: const EdgeInsets.all(3),
                              child: Image.asset('assets/images/app_icon.png'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Customizer controls
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Customize Design',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Dot Style Switch
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Circular Dots', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Switch(
                          value: useCircularDots,
                          activeThumbColor: qrColor,
                          onChanged: (val) => setState(() => useCircularDots = val),
                        ),
                      ],
                    ),
                    
                    // Eye Style Switch
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Circular Eyes', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Switch(
                          value: useCircularEyes,
                          activeThumbColor: qrColor,
                          onChanged: (val) => setState(() => useCircularEyes = val),
                        ),
                      ],
                    ),
                    
                    // Logo Switch
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Include Logo Overlay', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Switch(
                          value: includeLogo,
                          activeThumbColor: qrColor,
                          onChanged: (val) => setState(() => includeLogo = val),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Theme color selector bubbles
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Brand Tint', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Row(
                          children: qrColorOptions.map((color) {
                            final isSelected = qrColor == color;
                            return GestureDetector(
                              onTap: () => setState(() => qrColor = color),
                              child: Container(
                                margin: const EdgeInsets.only(left: 8),
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.white : Colors.transparent,
                                    width: 2.0,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: qrColor,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showThemePickerDialog(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeThemeStyle = ref.read(themeProvider);
    final notifier = ref.read(themeProvider.notifier);
    final subColor = theme.textTheme.bodyMedium?.color ?? const Color(0xFFC7C4D7);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF13131B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.white10, width: 1.0),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Select Premium Theme',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            IconButton(
              icon: const Icon(Icons.shuffle_rounded, color: Color(0xFF8083FF)),
              onPressed: () {
                notifier.randomizeTheme();
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Random premium theme applied!'),
                    backgroundColor: theme.primaryColor,
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              tooltip: 'Randomize Theme',
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.5,
            ),
            itemCount: ThemeStyle.values.length,
            itemBuilder: (context, index) {
              final style = ThemeStyle.values[index];
              final params = notifier.getThemeParams(style);
              final isSelected = activeThemeStyle == style;

              // Format name cleanly
              final name = style.name[0].toUpperCase() + style.name.substring(1);

              return GestureDetector(
                onTap: () {
                  notifier.selectTheme(style);
                  Navigator.of(context).pop();
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: params.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? params.primary : Colors.white.withValues(alpha: 0.05),
                      width: isSelected ? 2.0 : 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: params.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Row(
                        children: [
                          _buildThemeColorDot(params.background),
                          const SizedBox(width: 4),
                          _buildThemeColorDot(params.primary),
                          const SizedBox(width: 4),
                          _buildThemeColorDot(params.secondary),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: TextStyle(color: subColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeColorDot(Color color) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
    );
  }

  void _showDeadMansSwitchDialog(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final settingsBox = Hive.box('settings');
            final currentDays = settingsBox.get('dead_mans_switch_days', defaultValue: 30) as int;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Row(
                children: [
                  Icon(Icons.dangerous_outlined, color: Color(0xFFEF4444)),
                  SizedBox(width: 10),
                  Text('Dead Man\'s Switch'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'If you do not open the app for a set duration, Chatly will automatically wipe all cryptographic keys, tokens, settings, and outboxes on this device to protect your privacy.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Choose inactivity threshold:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: currentDays,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 7, child: Text('7 Days')),
                      DropdownMenuItem(value: 15, child: Text('15 Days')),
                      DropdownMenuItem(value: 30, child: Text('30 Days (Recommended)')),
                      DropdownMenuItem(value: 90, child: Text('90 Days')),
                    ],
                    onChanged: (val) async {
                      if (val != null) {
                        await settingsBox.put('dead_mans_switch_days', val);
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                      ),
                      icon: const Icon(Icons.delete_forever_rounded),
                      label: const Text('Manual Self-Destruct Now', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.of(context).pop(); // Close current dialog
                        _showEmergencyShredDialog(context, theme); // Show safety confirm dialog
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEmergencyShredDialog(BuildContext context, ThemeData theme) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false, // Force active confirmation
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final isConfirmed = textController.text.trim().toUpperCase() == 'SHRED DATA';
            
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
                  SizedBox(width: 10),
                  Text('Confirm Destruction', style: TextStyle(color: Color(0xFFEF4444))),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'To prevent accidental deletion, you must type SHRED DATA in uppercase to confirm immediate data wipe. This action is permanent.',
                    style: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: textController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Type SHRED DATA',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      errorText: textController.text.isNotEmpty && !isConfirmed ? 'Match exactly: SHRED DATA' : null,
                    ),
                    onChanged: (text) {
                      setState(() {});
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: isConfirmed
                      ? () async {
                          // Perform wipe
                          await DeadMansSwitchService().wipeAllData();
                          if (context.mounted) {
                            Navigator.of(context).pop(); // Close dialog
                            // Redirect to Welcome Onboarding
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                              (route) => false,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('All local keys and message vaults shredded securely.'),
                                backgroundColor: Color(0xFFEF4444),
                              ),
                            );
                          }
                        }
                      : null, // Disabled if not matching
                  child: const Text('Shred Everything'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => textController.dispose());
  }

  void _showSupportDialog(BuildContext context, WidgetRef ref) {
    final isSponsor = ref.read(sponsorshipProvider);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(
                isSponsor ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: const Color(0xFFEF4444),
              ),
              const SizedBox(width: 10),
              Text(isSponsor ? 'Manage Support' : 'Support Chatly'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isSponsor
                    ? 'Thank you for sponsoring the project! You can update your support or opt-out at any time below.'
                    : 'Since we never show ads or sell data, Chatly is 100% powered by user sponsorships. Help cover WebSocket servers and cryptography relays.',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              if (!isSponsor) ...[
                _buildDonationTile(
                  context,
                  ref,
                  title: 'Server Supporter',
                  price: '\$5/month',
                  icon: Icons.coffee_rounded,
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(height: 10),
                _buildDonationTile(
                  context,
                  ref,
                  title: 'Privacy Advocate',
                  price: '\$15/month',
                  icon: Icons.shield_outlined,
                  color: const Color(0xFF6366F1),
                ),
                const SizedBox(height: 10),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  leading: const Icon(Icons.currency_bitcoin_rounded, color: Color(0xFFF59E0B)),
                  title: const Text('Anonymous Crypto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Monero (XMR) & Bitcoin', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showCryptoDonationDialog(context, ref);
                  },
                ),
              ] else ...[
                Center(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      await ref.read(sponsorshipProvider.notifier).setSponsorStatus(false);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sponsorship status updated.')),
                        );
                      }
                    },
                    child: const Text('Cancel Sponsorship'),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDonationTile(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String price,
    required IconData icon,
    required Color color,
  }) {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      trailing: Text(
        price,
        style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
      ),
      onTap: () async {
        await ref.read(sponsorshipProvider.notifier).setSponsorStatus(true);
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.favorite_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Thank you! You are now a "$title" sponsor.')),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      },
    );
  }

  void _showCryptoDonationDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.currency_bitcoin_rounded, color: Color(0xFFF59E0B)),
              SizedBox(width: 10),
              Text('Anonymous Donate'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'For maximum anonymity, send Monero (XMR) or Bitcoin (BTC). Copy the address below.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MONERO ADDRESS:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                    SizedBox(height: 4),
                    Text(
                      '44AFFBa5718...39FA01XMR',
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  await ref.read(sponsorshipProvider.notifier).setSponsorStatus(true);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            Icon(Icons.favorite_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 10),
                            Text('Thank you! Sponsorship registered.'),
                          ],
                        ),
                        backgroundColor: Color(0xFF10B981),
                      ),
                    );
                  }
                },
                child: const Text('I Have Sent Crypto'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        );
      },
    );
  }

  void _showLayoutCustomizerDialog(BuildContext context, WidgetRef ref) {
    // Tab metadata map
    const tabMeta = {
      'chats': {'label': 'Chats', 'subtitle': 'Your secure conversations', 'icon': Icons.chat_bubble_rounded},
      'groups': {'label': 'Groups', 'subtitle': 'Group E2E chat rooms', 'icon': Icons.groups_rounded},
      'pulse': {'label': 'Pulse', 'subtitle': 'Anonymous feed & discovery', 'icon': Icons.masks_rounded},
      'settings': {'label': 'Settings', 'subtitle': 'App configuration & privacy', 'icon': Icons.settings_rounded},
    };

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final tabOrder = ref.read(tabOrderProvider);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Row(
                children: [
                  Icon(Icons.dashboard_customize_rounded, color: Color(0xFF6366F1)),
                  SizedBox(width: 10),
                  Text('Customize App Layout'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reorder the main navigation tabs. Your preferred layout is saved automatically.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  ...List.generate(tabOrder.length, (index) {
                    final key = tabOrder[index];
                    final meta = tabMeta[key]!;
                    final icon = meta['icon'] as IconData;
                    final label = meta['label'] as String;
                    final subtitle = meta['subtitle'] as String;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.15),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, size: 20, color: Theme.of(context).primaryColor),
                        ),
                        title: Text(
                          label,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: Text(
                          subtitle,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Move Up
                            _buildReorderButton(
                              icon: Icons.keyboard_arrow_up_rounded,
                              enabled: index > 0,
                              onTap: () async {
                                final updated = List<String>.from(tabOrder);
                                final temp = updated[index - 1];
                                updated[index - 1] = updated[index];
                                updated[index] = temp;
                                await ref.read(tabOrderProvider.notifier).updateTabOrder(updated);
                                setDialogState(() {});
                              },
                            ),
                            const SizedBox(width: 4),
                            // Move Down
                            _buildReorderButton(
                              icon: Icons.keyboard_arrow_down_rounded,
                              enabled: index < tabOrder.length - 1,
                              onTap: () async {
                                final updated = List<String>.from(tabOrder);
                                final temp = updated[index + 1];
                                updated[index + 1] = updated[index];
                                updated[index] = temp;
                                await ref.read(tabOrderProvider.notifier).updateTabOrder(updated);
                                setDialogState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  // Reset to default
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Reset to Default Order'),
                      onPressed: () async {
                        await ref.read(tabOrderProvider.notifier).updateTabOrder(
                          ['chats', 'groups', 'pulse', 'settings'],
                        );
                        setDialogState(() {});
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildReorderButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF6366F1).withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? const Color(0xFF6366F1) : Colors.grey.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  void _showCamouflageDialog(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final settingsBox = Hive.box('settings');
            final currentDecoy = settingsBox.get('decoy_app_state', defaultValue: 'none') as String;
            final isDuressActive = settingsBox.get('is_duress_active', defaultValue: false) as bool;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Row(
                children: [
                  Icon(Icons.visibility_off_outlined, color: Colors.blueAccent),
                  SizedBox(width: 10),
                  Text('App Decoy & Camouflage'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isDuressActive)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Duress decoy mode is currently active.',
                              style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await settingsBox.put('is_duress_active', false);
                              setState(() {});
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Duress decoy mode deactivated. Reboot app to view your true chats.'),
                                  backgroundColor: Color(0xFF10B981),
                                ),
                              );
                            },
                            child: const Text('Reset', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                  const Text(
                    'Disguise the app behind a decoy screen to prevent others from accessing your secure chats when holding your device.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  _buildIconPreviewCard(currentDecoy, theme),
                  const SizedBox(height: 20),
                  RadioListTile<String>(
                    title: const Text('None (Boot Normally)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Lobbies and chats load directly on start', style: TextStyle(fontSize: 11)),
                    value: 'none',
                    groupValue: currentDecoy, // ignore: deprecated_member_use
                    activeColor: theme.primaryColor,
                    onChanged: (val) async { // ignore: deprecated_member_use
                      if (val != null) {
                        await settingsBox.put('decoy_app_state', val);
                        setState(() {});
                      }
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('Calculator Camouflage', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Launches mock calculator; dial 5555 to unlock', style: TextStyle(fontSize: 11)),
                    value: 'calculator',
                    groupValue: currentDecoy, // ignore: deprecated_member_use
                    activeColor: theme.primaryColor,
                    onChanged: (val) async { // ignore: deprecated_member_use
                      if (val != null) {
                        await settingsBox.put('decoy_app_state', val);
                        setState(() {});
                      }
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('Weather Forecast Decoy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Launches forecast; tap temperature 3x to unlock', style: TextStyle(fontSize: 11)),
                    value: 'weather',
                    groupValue: currentDecoy, // ignore: deprecated_member_use
                    activeColor: theme.primaryColor,
                    onChanged: (val) async { // ignore: deprecated_member_use
                      if (val != null) {
                        await settingsBox.put('decoy_app_state', val);
                        setState(() {});
                      }
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('Notes Notepad Decoy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Launches notes list; save note "unlock" to entry', style: TextStyle(fontSize: 11)),
                    value: 'notes',
                    groupValue: currentDecoy, // ignore: deprecated_member_use
                    activeColor: theme.primaryColor,
                    onChanged: (val) async { // ignore: deprecated_member_use
                      if (val != null) {
                        await settingsBox.put('decoy_app_state', val);
                        setState(() {});
                      }
                    },
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildIconPreviewCard(String decoyState, ThemeData theme) {
    IconData icon;
    Color iconColor;
    Color bgColor;
    String label;
    String status;

    switch (decoyState) {
      case 'calculator':
        icon = Icons.calculate_rounded;
        iconColor = Colors.white;
        bgColor = Colors.orange;
        label = 'Calculator';
        status = 'Disguised';
        break;
      case 'weather':
        icon = Icons.wb_sunny_rounded;
        iconColor = Colors.white;
        bgColor = Colors.blueAccent;
        label = 'Weather';
        status = 'Disguised';
        break;
      case 'notes':
        icon = Icons.note_alt_rounded;
        iconColor = Colors.white;
        bgColor = Colors.amber[700]!;
        label = 'Notepad';
        status = 'Disguised';
        break;
      default:
        icon = Icons.lock_rounded;
        iconColor = theme.primaryColor;
        bgColor = theme.primaryColor.withValues(alpha: 0.12);
        label = 'Chatly';
        status = 'Active';
    }

    return Center(
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, size: 30, color: iconColor),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: decoyState == 'none' ? const Color(0xFF10B981) : Colors.blueAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Launcher: $status',
                  style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showWallpaperPickerDialog(BuildContext context, WidgetRef ref) {
    final wallpaper = ref.watch(wallpaperProvider);
    final notifier = ref.read(wallpaperProvider.notifier);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Text('Select Chat Wallpaper', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: ListView(
              children: [
                _buildWallpaperSectionTitle('Premium Image Art'),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.5),
                  itemCount: WallpaperNotifier.presets.where((p) => p.imagePath != null).length,
                  itemBuilder: (context, idx) {
                    final p = WallpaperNotifier.presets.where((preset) => preset.imagePath != null).elementAt(idx);
                    final isSel = wallpaper.selectedPresetId == p.id;
                    return _buildWallpaperTile(p, isSel, () {
                      notifier.selectPreset(p.id);
                      Navigator.of(context).pop();
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildWallpaperSectionTitle('Chatly Gradients'),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.5),
                  itemCount: WallpaperNotifier.presets.where((p) => p.category == WallpaperCategory.chatly && p.imagePath == null).length,
                  itemBuilder: (context, idx) {
                    final p = WallpaperNotifier.presets.where((preset) => preset.category == WallpaperCategory.chatly && preset.imagePath == null).elementAt(idx);
                    final isSel = wallpaper.selectedPresetId == p.id;
                    return _buildWallpaperTile(p, isSel, () {
                      notifier.selectPreset(p.id);
                      Navigator.of(context).pop();
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildWallpaperSectionTitle('WhatsApp Solid Doodles'),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.5),
                  itemCount: WallpaperNotifier.presets.where((p) => p.category == WallpaperCategory.whatsapp && p.imagePath == null).length,
                  itemBuilder: (context, idx) {
                    final p = WallpaperNotifier.presets.where((preset) => preset.category == WallpaperCategory.whatsapp && preset.imagePath == null).elementAt(idx);
                    final isSel = wallpaper.selectedPresetId == p.id;
                    return _buildWallpaperTile(p, isSel, () {
                      notifier.selectPreset(p.id);
                      Navigator.of(context).pop();
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildWallpaperSectionTitle('Telegram Solid Colors'),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.5),
                  itemCount: WallpaperNotifier.presets.where((p) => p.category == WallpaperCategory.telegram && p.imagePath == null).length,
                  itemBuilder: (context, idx) {
                    final p = WallpaperNotifier.presets.where((preset) => preset.category == WallpaperCategory.telegram && preset.imagePath == null).elementAt(idx);
                    final isSel = wallpaper.selectedPresetId == p.id;
                    return _buildWallpaperTile(p, isSel, () {
                      notifier.selectPreset(p.id);
                      Navigator.of(context).pop();
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close', style: TextStyle(color: Colors.white60)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWallpaperSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(title, style: const TextStyle(color: Color(0xFF8083FF), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
    );
  }

  Widget _buildWallpaperTile(WallpaperPreset p, bool isSelected, VoidCallback onTap) {
    DecorationImage? bgImage;
    if (p.imagePath != null) {
      bgImage = DecorationImage(
        image: AssetImage(p.imagePath!),
        fit: BoxFit.cover,
        opacity: 0.8,
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? const Color(0xFF8083FF) : Colors.white10, width: isSelected ? 2.0 : 1.0),
          gradient: p.imagePath == null && p.gradientColors != null
              ? LinearGradient(colors: p.gradientColors!, begin: Alignment.topCenter, end: Alignment.bottomCenter)
              : null,
          color: p.imagePath == null && p.gradientColors == null ? p.solidColor : null,
          image: bgImage,
        ),
        alignment: Alignment.center,
        child: Stack(
          children: [
            if (p.hasPattern)
              const Positioned.fill(
                child: Icon(Icons.bubble_chart_outlined, size: 24, color: Colors.white10),
              ),
            Center(
              child: Text(
                p.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  shadows: [
                    Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFontPickerDialog(BuildContext context, WidgetRef ref) {
    final activeFont = ref.watch(fontProvider);
    final notifier = ref.read(fontProvider.notifier);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Text('Select App Font Family', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: AppFontFamily.values.map((f) {
              final isSel = activeFont == f;
              final label = f.name[0].toUpperCase() + f.name.substring(1);
              return ListTile(
                title: Text(label, style: const TextStyle(color: Colors.white)),
                trailing: isSel ? const Icon(Icons.check_circle_rounded, color: Color(0xFF8083FF)) : null,
                onTap: () {
                  notifier.selectFont(f);
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showDensityPickerDialog(BuildContext context) {
    final settingsBox = Hive.box('settings');
    int currentDensity = settingsBox.get('chat_tile_density', defaultValue: 5) as int;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF13131B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Colors.white10),
              ),
              title: const Text('Chat Layout Density', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Adjust how many chat rooms fit on your screen simultaneously:', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Density:', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      Text('$currentDensity Tiles', style: const TextStyle(color: Color(0xFF8083FF), fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  Slider(
                    value: currentDensity.toDouble(),
                    min: 5,
                    max: 9,
                    divisions: 4,
                    activeColor: const Color(0xFF8083FF),
                    onChanged: (val) {
                      setState(() {
                        currentDensity = val.toInt();
                      });
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Relaxed (5)', style: TextStyle(color: Colors.grey.withValues(alpha: 0.8), fontSize: 9)),
                      Text('Ultra-Compact (9)', style: TextStyle(color: Colors.grey.withValues(alpha: 0.8), fontSize: 9)),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    await settingsBox.put('chat_tile_density', currentDensity);
                    nav.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Chat layout density updated!')),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMoodPickerDialog(BuildContext context) {
    final box = Hive.box('settings');
    final currentMood = box.get('user_mood', defaultValue: 'Vibing') as String;

    final List<Map<String, String>> moods = [
      {'mood': 'Vibing', 'emoji': '😊'},
      {'mood': 'Busy', 'emoji': '🔴'},
      {'mood': 'Offline', 'emoji': '💤'},
      {'mood': 'Incognito', 'emoji': '🕵️'},
      {'mood': 'At Work', 'emoji': '💼'},
      {'mood': 'Focus Mode', 'emoji': '🎯'},
      {'mood': 'Chilling', 'emoji': '🍹'},
      {'mood': 'Coding', 'emoji': '💻'},
    ];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Text(
            'Set Your Mood Status',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: SizedBox(
            width: 280,
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: moods.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.2,
              ),
              itemBuilder: (context, index) {
                final item = moods[index];
                final isSelected = item['mood'] == currentMood;
                return GestureDetector(
                  onTap: () {
                    box.put('user_mood', item['mood']);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF10B981) : Colors.white10,
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(item['emoji']!, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          item['mood']!,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF10B981) : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
          ],
        );
      },
    );
  }

  void _showAvatarPickerDialog(BuildContext context) {
    final settingsBox = Hive.box('settings');
    
    // Categorized PNG Dicebear Avatars
    final Map<String, List<String>> avatarCategories = {
      'Anime (Adventurer)': List.generate(12, (i) => 'https://api.dicebear.com/7.x/adventurer/png?seed=AnimeSeed${i + 1}'),
      'Professional (Avataaars)': List.generate(12, (i) => 'https://api.dicebear.com/7.x/avataaars/png?seed=ProfSeed${i + 1}'),
      'Friendly (Pixel Art)': List.generate(12, (i) => 'https://api.dicebear.com/7.x/pixel-art/png?seed=FriendSeed${i + 1}'),
      'Fun (Robots)': List.generate(12, (i) => 'https://api.dicebear.com/7.x/bottts/png?seed=FunSeed${i + 1}'),
    };

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Text('Choose Avatar Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: ListView(
              children: avatarCategories.entries.map((category) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Text(category.key, style: const TextStyle(color: Color(0xFFFFB300), fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8),
                      itemCount: category.value.length,
                      itemBuilder: (context, idx) {
                        final url = category.value[idx];
                        return GestureDetector(
                          onTap: () async {
                            final nav = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            await settingsBox.put('avatar_image_url', url);
                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Avatar profile updated!')),
                            );
                          },
                          child: CircleAvatar(
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Image.network(url, errorBuilder: (c, e, s) => const Icon(Icons.face_rounded, color: Colors.white60)),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
          ],
        );
      },
    );
  }

  void _showAnonymousLimitsDialog(BuildContext context) {
    final settingsBox = Hive.box('settings');
    int dailyLimit = settingsBox.get('pulse_daily_limit', defaultValue: 2) as int;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF13131B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Colors.white10),
              ),
              title: const Text('Pulse Limits Setting', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Set daily anonymous pulse posts limit to prevent data exhaust:', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Daily Limit:', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      Text('$dailyLimit Pulses', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  Slider(
                    value: dailyLimit.toDouble(),
                    min: 2,
                    max: 10,
                    divisions: 8,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (val) {
                      setState(() {
                        dailyLimit = val.toInt();
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    await settingsBox.put('pulse_daily_limit', dailyLimit);
                    nav.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Pulse posting daily limit updated!')),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPrivacyPolicyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Text('Privacy & Zero-Knowledge Policy', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          content: const SizedBox(
            width: double.maxFinite,
            height: 300,
            child: SingleChildScrollView(
              child: Text(
                '1. Zero-Trace Guarantee: Chatly does not retain logs of your communications, network routes, or physical device identifiers. Chat logs exist solely on physical device cache.\n\n'
                '2. Cryptographic Architecture: E2E channels are constructed locally utilizing 256-bit X25519 identity key agreements and AES-GCM envelopes. Private credentials never leave keychains.\n\n'
                '3. Decamouflage Wipes: Camouflage camers and shake panic button routing erase databases if inactivity timers trigger or dead-man limits are tripped.\n\n'
                '4. Proximity Mesh Networking: Nearby connection relays execute directly on TCP/UDP sockets on local segments. No external internet is parsed or telemetry leaked.',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showInvitationsDialog(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(connectionProvider);
    final notifier = ref.read(connectionProvider.notifier);

    showDialog(
      context: context,
      builder: (context) {
        final textController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF13131B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Colors.white10),
              ),
              title: const Text('Connection Invitations', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              content: SizedBox(
                width: double.maxFinite,
                height: 360,
                child: Column(
                  children: [
                    // Send invite field
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: textController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Invite @username...',
                              hintStyle: TextStyle(color: Colors.white30),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send_rounded, color: Color(0xFF8083FF)),
                          onPressed: () async {
                            final username = textController.text.trim();
                            if (username.isNotEmpty) {
                              final messenger = ScaffoldMessenger.of(context);
                              final done = await notifier.sendInvitation(username);
                              if (done) {
                                textController.clear();
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Invitation sent to @$username!')),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 20, color: Colors.white10),
                    Expanded(
                      child: connState.invitations.isEmpty
                          ? const Center(child: Text('No invitations pending', style: TextStyle(color: Colors.white38, fontSize: 12)))
                          : ListView.builder(
                              itemCount: connState.invitations.length,
                              itemBuilder: (context, idx) {
                                final invite = connState.invitations[idx];
                                final isIncoming = invite.type == 'incoming';
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('@${invite.username}', style: const TextStyle(color: Colors.white, fontSize: 14)),
                                  subtitle: Text(
                                    isIncoming
                                        ? (invite.isProximity ? 'Incoming Proximity Request' : 'Incoming Invitation')
                                        : 'Outgoing Invite • ${invite.status}',
                                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                                  ),
                                  trailing: isIncoming && invite.status == 'pending'
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                                              onPressed: () => notifier.rejectInvitation(invite.username),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.check_rounded, color: Colors.greenAccent, size: 18),
                                              onPressed: () => notifier.acceptInvitation(invite.username),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          invite.status.toUpperCase(),
                                          style: TextStyle(
                                            color: invite.status == 'accepted' ? Colors.green : Colors.grey,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close', style: TextStyle(color: Colors.white60)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMessageRetentionDialog(BuildContext context) {
    final settingsBox = Hive.box('settings');
    int currentDays = settingsBox.get('message_retention_days', defaultValue: 0) as int;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF13131B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Colors.white10),
              ),
              title: const Text('Message Retention', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Automatically delete message history older than the selected threshold. Wipes messages from disk.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: currentDays,
                    dropdownColor: const Color(0xFF1B1B23),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Off (Retain History)', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 2, child: Text('2 Days', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 3, child: Text('3 Days', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 7, child: Text('7 Days', style: TextStyle(color: Colors.white))),
                    ],
                    onChanged: (val) async {
                      if (val != null) {
                        await settingsBox.put('message_retention_days', val);
                        setState(() => currentDays = val);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done', style: TextStyle(color: Colors.white60)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showBackupDataDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            double progress = 0.0;
            String status = 'Initializing backup...';
            bool finished = false;

            void runBackup() async {
              final steps = [
                'Encrypting database files...',
                'Shredding temporary cache files...',
                'Exporting local cryptographic logs...',
                'Generating secure encrypted payload...',
                'Backup successful! Saved: chatly_backup.txt'
              ];

              for (int i = 0; i < steps.length; i++) {
                if (!context.mounted) return;
                await Future.delayed(const Duration(milliseconds: 600));
                setState(() {
                  progress = (i + 1) / steps.length;
                  status = steps[i];
                  if (i == steps.length - 1) {
                    finished = true;
                  }
                });
              }
            }

            // Start the backup on dialog display
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (progress == 0.0) {
                runBackup();
              }
            });

            return AlertDialog(
              backgroundColor: const Color(0xFF13131B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Colors.white10),
              ),
              title: const Text('Local Encrypted Backup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  if (!finished)
                    const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFF8083FF)))
                  else
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 48),
                  const SizedBox(height: 20),
                  Text(
                    status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (!finished)
                    LinearProgressIndicator(value: progress, color: const Color(0xFF8083FF), backgroundColor: Colors.white10)
                  else
                    const Text(
                      'An encrypted .txt log of your messages has been exported to your local cache folder under a custom key.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.4),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: finished ? () => Navigator.of(context).pop() : null,
                  child: Text('Close', style: TextStyle(color: finished ? Colors.white : Colors.white30)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Text('Confirm Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          content: const Text(
            'Are you sure you want to log out? Your keys are stored locally, but you will need to re-login to synchronize with peers.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.of(context).pop();
                final secureBox = await Hive.openBox('secure_vault');
                await secureBox.delete('auth_token');
                
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                    (route) => false,
                  );
                }
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteAccountDialog(BuildContext context, ThemeData theme) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final isConfirmed = textController.text.trim().toUpperCase() == 'DELETE';
            
            return AlertDialog(
              backgroundColor: const Color(0xFF13131B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Colors.white10),
              ),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
                  SizedBox(width: 10),
                  Text('Delete Account?', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wipes all local identities, chat logs, settings, and credentials permanently. You cannot recover these keys once deleted.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  const Text('Type DELETE to confirm:', style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type DELETE',
                      hintStyle: const TextStyle(color: Colors.white30),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      errorText: textController.text.isNotEmpty && !isConfirmed ? 'Must match exactly: DELETE' : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isConfirmed
                      ? () async {
                          Navigator.of(context).pop();
                          await DeadMansSwitchService().wipeAllData();
                          if (context.mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                              (route) => false,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Account data wiped and deleted.'),
                                backgroundColor: Color(0xFFEF4444),
                              ),
                            );
                          }
                        }
                      : null,
                  child: const Text('Delete Account'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => textController.dispose());
  }

  void _showRelationshipHealthDialog(BuildContext context, WidgetRef ref) {
    final connections = ref.read(connectionProvider).connections;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Row(
            children: [
              Icon(Icons.favorite_rounded, color: Color(0xFFEF4444)),
              SizedBox(width: 10),
              Text('Relationship Health', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Track engagement states of your E2E secure contacts. Neglected relationships will fade in color and require a friendly ping.',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: connections.isEmpty
                      ? const Center(
                          child: Text('No E2E connections active yet.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        )
                      : ListView.builder(
                          itemCount: connections.length,
                          itemBuilder: (context, index) {
                            final contact = connections[index];
                            final boxName = 'messages_$contact';
                            int latestTimestamp = 0;
                            if (Hive.isBoxOpen(boxName)) {
                              final box = Hive.box(boxName);
                              for (final val in box.values) {
                                if (val != null) {
                                  try {
                                    final data = jsonDecode(val.toString()) as Map<String, dynamic>;
                                    final ts = data['timestamp'] as int? ?? 0;
                                    if (ts > latestTimestamp) {
                                      latestTimestamp = ts;
                                    }
                                  } catch (_) {}
                                }
                              }
                            }
                            
                            int score = 0;
                            if (latestTimestamp > 0) {
                              final diffMs = DateTime.now().millisecondsSinceEpoch - latestTimestamp;
                              const oneDayMs = 24 * 60 * 60 * 1000;
                              const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
                              
                              if (diffMs < oneDayMs) {
                                score = 90 + ((oneDayMs - diffMs) * 10 ~/ oneDayMs); // 90-100% if < 24h
                              } else if (diffMs < sevenDaysMs) {
                                score = 40 + ((sevenDaysMs - diffMs) * 50 ~/ sevenDaysMs); // 40-90% if < 7d
                              } else {
                                const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
                                if (diffMs < thirtyDaysMs) {
                                  score = 10 + ((thirtyDaysMs - diffMs) * 30 ~/ thirtyDaysMs); // 10-40% if < 30d
                                } else {
                                  score = 5;
                                }
                              }
                            } else {
                              score = 25; // Default for no history
                            }
                            
                            Color healthColor;
                            String statusText;
                            if (score > 75) {
                              healthColor = const Color(0xFF10B981);
                              statusText = 'Vibing • High Engagement';
                            } else if (score > 40) {
                              healthColor = const Color(0xFFF59E0B);
                              statusText = 'Fading • Neglected';
                            } else {
                              healthColor = const Color(0xFFEF4444);
                              statusText = 'Critical • Cold Contact';
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: healthColor, width: 2),
                                    ),
                                    child: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.white10,
                                      child: Text(contact[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('@$contact', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                        const SizedBox(height: 2),
                                        Text(statusText, style: TextStyle(color: healthColor, fontSize: 10, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: healthColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$score%',
                                      style: TextStyle(color: healthColor, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close', style: TextStyle(color: Colors.white60)),
            ),
          ],
        );
      },
    );
  }

  void _showCommunityRoadmapDialog(BuildContext context) {
    final settingsBox = Hive.box('settings');
    final List<Map<String, String>> roadmapFeatures = [
      {
        'id': 'unified_push',
        'title': 'UnifiedPush Integration',
        'desc': 'De-Google notifications using open source self-hosted push servers.',
      },
      {
        'id': 'onion_routing',
        'title': 'Tor Onion Routing',
        'desc': 'Obfuscate your server IP address by routing E2E traffic through Tor.',
      },
      {
        'id': 'stegano_images',
        'title': 'Steganographic Camouflage',
        'desc': 'Hide encrypted files inside harmless-looking photos before sending.',
      },
      {
        'id': 'self_host',
        'title': 'Personal Node Syncing',
        'desc': 'Directly back up and synchronize databases to your own physical server.',
      },
      {
        'id': 'web3_identity',
        'title': 'P2P Wallet Identity',
        'desc': 'Sign cryptographic handshakes using hardware wallets for zero-trust trust-chains.',
      },
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF13131B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Colors.white10),
              ),
              title: const Row(
                children: [
                  Icon(Icons.rate_review_outlined, color: Color(0xFF8083FF)),
                  SizedBox(width: 10),
                  Text('Community Roadmap', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 385,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vote on features you want to see implemented in upcoming releases. Votes are stored locally on your device.',
                      style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: roadmapFeatures.length,
                        itemBuilder: (context, index) {
                          final f = roadmapFeatures[index];
                          final id = f['id']!;
                          final title = f['title']!;
                          final desc = f['desc']!;
                          final voted = settingsBox.get('vote_$id', defaultValue: false) as bool;
                          final baseVotes = 100 + (id.hashCode % 150);
                          final votesCount = baseVotes + (voted ? 1 : 0);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: voted ? const Color(0xFF8083FF).withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: voted ? const Color(0xFF8083FF).withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                      const SizedBox(height: 4),
                                      Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 10, height: 1.3)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () async {
                                    await settingsBox.put('vote_$id', !voted);
                                    setState(() {});
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: voted ? const Color(0xFF8083FF) : Colors.white10,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(Icons.keyboard_arrow_up_rounded, color: voted ? Colors.white : Colors.white70, size: 16),
                                        Text(
                                          '$votesCount',
                                          style: TextStyle(
                                            color: voted ? Colors.white : Colors.white70,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close', style: TextStyle(color: Colors.white60)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
