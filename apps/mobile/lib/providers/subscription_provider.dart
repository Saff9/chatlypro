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

  // Feature Flag Helpers (all now free/unlocked)
  bool get hasUnlimitedAnonymous => true;
  bool get canCreateGroups => true;
  bool get canUseCustomThemes => true;
  int get maxGroupCreationLimit => 25;
  int get anonymousLimitPerWeek => 21;
  int get retentionDays => 7;
}

final sponsorshipProvider = StateNotifierProvider<SponsorshipNotifier, bool>((ref) {
  return SponsorshipNotifier();
});
