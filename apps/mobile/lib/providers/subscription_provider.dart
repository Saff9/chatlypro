import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

class SponsorshipNotifier extends StateNotifier<bool> {
  SponsorshipNotifier() : super(false) {
    _loadSponsorStatus();
  }

  Future<void> _loadSponsorStatus() async {
    try {
      final settingsBox = await Hive.openBox('settings');
      state = settingsBox.get('is_sponsor', defaultValue: false) as bool;
    } catch (_) {
      state = false;
    }
  }

  /// Updates the user's sponsorship/support status in local settings.
  Future<void> setSponsorStatus(bool isSponsor) async {
    state = isSponsor;
    try {
      final settingsBox = await Hive.openBox('settings');
      await settingsBox.put('is_sponsor', isSponsor);
    } catch (_) {
      // Fail silently
    }
  }

  // Feature Flag Helpers (All features are fully unlocked for all users!)
  bool get hasUnlimitedAnonymous => true;
  bool get canCreateGroups => true;
  bool get canUseCustomThemes => true;
  int get maxGroupCreationLimit => 999;
  int get anonymousLimitPerWeek => 9999;
  int get retentionDays => 2; // Auto-delete choice
}

final sponsorshipProvider = StateNotifierProvider<SponsorshipNotifier, bool>((ref) {
  return SponsorshipNotifier();
});
