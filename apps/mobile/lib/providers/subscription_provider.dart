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

  // Feature Flag Helpers
  bool get hasUnlimitedAnonymous => state;
  bool get canCreateGroups => true;
  bool get canUseCustomThemes => state;
  int get maxGroupCreationLimit => state ? 999 : 3;
  int get anonymousLimitPerWeek => state ? 9999 : 5;
  int get retentionDays => 2; // Auto-delete choice
}

final sponsorshipProvider = StateNotifierProvider<SponsorshipNotifier, bool>((ref) {
  return SponsorshipNotifier();
});
