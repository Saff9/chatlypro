import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

enum WallpaperCategory { whatsapp, telegram, chatly }

class WallpaperPreset {
  final String id;
  final String name;
  final WallpaperCategory category;
  final Color solidColor;
  final List<Color>? gradientColors;
  final bool hasPattern;
  final String? imagePath;

  const WallpaperPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.solidColor,
    this.gradientColors,
    this.hasPattern = false,
    this.imagePath,
  });
}

class WallpaperState {
  final String selectedPresetId;
  final Color? customSolidColor;
  final List<Color>? customGradient;

  WallpaperState({
    required this.selectedPresetId,
    this.customSolidColor,
    this.customGradient,
  });

  WallpaperState copyWith({
    String? selectedPresetId,
    Color? customSolidColor,
    List<Color>? customGradient,
  }) {
    return WallpaperState(
      selectedPresetId: selectedPresetId ?? this.selectedPresetId,
      customSolidColor: customSolidColor ?? this.customSolidColor,
      customGradient: customGradient ?? this.customGradient,
    );
  }
}

class WallpaperNotifier extends StateNotifier<WallpaperState> {
  WallpaperNotifier() : super(WallpaperState(selectedPresetId: 'chatly_obsidian')) {
    _loadWallpaper();
  }

  static const List<WallpaperPreset> presets = [
    // WhatsApp Presets (10 Presets)
    WallpaperPreset(id: 'wa_sage', name: 'WhatsApp Sage', category: WallpaperCategory.whatsapp, solidColor: Color(0xFFE5DDD5), hasPattern: true),
    WallpaperPreset(id: 'wa_teal', name: 'WhatsApp Teal', category: WallpaperCategory.whatsapp, solidColor: Color(0xFF075E54), hasPattern: true),
    WallpaperPreset(id: 'wa_blue', name: 'WhatsApp Sky Blue', category: WallpaperCategory.whatsapp, solidColor: Color(0xFFD4E6F1), hasPattern: true),
    WallpaperPreset(id: 'wa_rose', name: 'WhatsApp Soft Rose', category: WallpaperCategory.whatsapp, solidColor: Color(0xFFFADBD8), hasPattern: true),
    WallpaperPreset(id: 'wa_cream', name: 'WhatsApp Cream', category: WallpaperCategory.whatsapp, solidColor: Color(0xFFFEF9E7), hasPattern: true),
    WallpaperPreset(id: 'wa_gold', name: 'WhatsApp Gold', category: WallpaperCategory.whatsapp, solidColor: Color(0xFFFDEBD0), hasPattern: true),
    WallpaperPreset(id: 'wa_lavender', name: 'WhatsApp Lavender', category: WallpaperCategory.whatsapp, solidColor: Color(0xFFE8DAEF), hasPattern: true),
    WallpaperPreset(id: 'wa_charcoal', name: 'WhatsApp Charcoal', category: WallpaperCategory.whatsapp, solidColor: Color(0xFF2C3E50), hasPattern: true),
    WallpaperPreset(id: 'wa_sand', name: 'WhatsApp Sand', category: WallpaperCategory.whatsapp, solidColor: Color(0xFFF5F5DC), hasPattern: true),
    WallpaperPreset(id: 'wa_olive', name: 'WhatsApp Olive', category: WallpaperCategory.whatsapp, solidColor: Color(0xFFD5DBDB), hasPattern: true),

    // Telegram Presets (10 Presets)
    WallpaperPreset(id: 'tg_classic', name: 'Telegram Classic', category: WallpaperCategory.telegram, solidColor: Color(0xFF5E81AC)),
    WallpaperPreset(id: 'tg_ice', name: 'Telegram Arctic Ice', category: WallpaperCategory.telegram, solidColor: Color(0xFFD8DEE9)),
    WallpaperPreset(id: 'tg_orange', name: 'Telegram Sunset', category: WallpaperCategory.telegram, solidColor: Color(0xFFD08770)),
    WallpaperPreset(id: 'tg_midnight', name: 'Telegram Midnight', category: WallpaperCategory.telegram, solidColor: Color(0xFF2E3440)),
    WallpaperPreset(id: 'tg_emerald', name: 'Telegram Emerald', category: WallpaperCategory.telegram, solidColor: Color(0xFF8FBCBB)),
    WallpaperPreset(id: 'tg_purple', name: 'Telegram Royal Purple', category: WallpaperCategory.telegram, solidColor: Color(0xFFB48EAD)),
    WallpaperPreset(id: 'tg_lilac', name: 'Telegram Lilac', category: WallpaperCategory.telegram, solidColor: Color(0xFFEBCB8B)),
    WallpaperPreset(id: 'tg_coral', name: 'Telegram Coral', category: WallpaperCategory.telegram, solidColor: Color(0xFFBF616A)),
    WallpaperPreset(id: 'tg_peach', name: 'Telegram Peach', category: WallpaperCategory.telegram, solidColor: Color(0xFFD8D8D8)),
    WallpaperPreset(id: 'tg_forest', name: 'Telegram Mist', category: WallpaperCategory.telegram, solidColor: Color(0xFF4C566A)),

    // Chatly Custom Gradients (10 Presets)
    WallpaperPreset(id: 'chatly_obsidian', name: 'Chatly Obsidian', category: WallpaperCategory.chatly, solidColor: Color(0xFF13131B), gradientColors: [Color(0xFF13131B), Color(0xFF1B1B23)]),
    WallpaperPreset(id: 'chatly_neon', name: 'Chatly CyberNeon', category: WallpaperCategory.chatly, solidColor: Color(0xFF0B071E), gradientColors: [Color(0xFF0B071E), Color(0xFF1F0C3D)]),
    WallpaperPreset(id: 'chatly_forest', name: 'Chatly Forest', category: WallpaperCategory.chatly, solidColor: Color(0xFF050B08), gradientColors: [Color(0xFF050B08), Color(0xFF0D1F17)]),
    WallpaperPreset(id: 'chatly_sunset', name: 'Chatly Sunset Rose', category: WallpaperCategory.chatly, solidColor: Color(0xFF0F050B), gradientColors: [Color(0xFF0F050B), Color(0xFF2E0F1E)]),
    WallpaperPreset(id: 'chatly_nordic', name: 'Chatly Aurora', category: WallpaperCategory.chatly, solidColor: Color(0xFF1F232A), gradientColors: [Color(0xFF1F232A), Color(0xFF2E3842)]),
    WallpaperPreset(id: 'chatly_titanium', name: 'Chatly Metal', category: WallpaperCategory.chatly, solidColor: Color(0xFF14171A), gradientColors: [Color(0xFF14171A), Color(0xFF2A2E35)]),
    WallpaperPreset(id: 'chatly_gold', name: 'Chatly Supporter Gold', category: WallpaperCategory.chatly, solidColor: Color(0xFF1C1A0E), gradientColors: [Color(0xFF1C1A0E), Color(0xFF3F3B21)]),
    WallpaperPreset(id: 'chatly_ruby', name: 'Chatly Red Ruby', category: WallpaperCategory.chatly, solidColor: Color(0xFF240A0A), gradientColors: [Color(0xFF240A0A), Color(0xFF4A1515)]),
    WallpaperPreset(id: 'chatly_sapphire', name: 'Chatly Sapphire Blue', category: WallpaperCategory.chatly, solidColor: Color(0xFF0D1B2A), gradientColors: [Color(0xFF0D1B2A), Color(0xFF1B2E46)]),
    WallpaperPreset(id: 'chatly_emerald', name: 'Chatly Emerald Mint', category: WallpaperCategory.chatly, solidColor: Color(0xFF06231C), gradientColors: [Color(0xFF06231C), Color(0xFF104A3C)]),

    // Premium Image-Based Wallpapers (5 Presets)
    WallpaperPreset(id: 'tg_classic_doodle', name: 'Telegram Doodle Classic', category: WallpaperCategory.telegram, solidColor: Color(0xFF5E81AC), imagePath: 'assets/images/chat_bg_telegram_classic.png'),
    WallpaperPreset(id: 'chatly_obsidian_hex', name: 'Obsidian Hexagon Grid', category: WallpaperCategory.chatly, solidColor: Color(0xFF13131B), imagePath: 'assets/images/chat_bg_obsidian_hex.png'),
    WallpaperPreset(id: 'chatly_aurora_nebula', name: 'Cosmic Aurora Nebula', category: WallpaperCategory.chatly, solidColor: Color(0xFF0D1B2A), imagePath: 'assets/images/chat_bg_aurora_nebula.png'),
    WallpaperPreset(id: 'chatly_min_geom', name: 'Sleek Poly-Geom Mesh', category: WallpaperCategory.chatly, solidColor: Color(0xFF14171A), imagePath: 'assets/images/chat_bg_minimalist_geometric.png'),
    WallpaperPreset(id: 'chatly_desert_dusk', name: 'Desert Dusk Fluid Waves', category: WallpaperCategory.chatly, solidColor: Color(0xFF0F050B), imagePath: 'assets/images/chat_bg_desert_dusk.png'),
  ];

  Future<void> _loadWallpaper() async {
    final box = await Hive.openBox('settings');
    final storedPreset = box.get('wallpaper_preset', defaultValue: 'chatly_obsidian');
    final customSolidVal = box.get('wallpaper_custom_solid');
    final customGradientVals = box.get('wallpaper_custom_gradient');

    Color? customSolid;
    if (customSolidVal != null) customSolid = Color(customSolidVal);

    List<Color>? customGradient;
    if (customGradientVals != null) {
      customGradient = (customGradientVals as List).map((v) => Color(v as int)).toList();
    }

    state = WallpaperState(
      selectedPresetId: storedPreset,
      customSolidColor: customSolid,
      customGradient: customGradient,
    );
  }

  Future<void> selectPreset(String id) async {
    state = state.copyWith(selectedPresetId: id, customSolidColor: null, customGradient: null);
    final box = await Hive.openBox('settings');
    await box.put('wallpaper_preset', id);
    await box.delete('wallpaper_custom_solid');
    await box.delete('wallpaper_custom_gradient');
  }

  Future<void> setCustomSolidColor(Color color) async {
    state = state.copyWith(selectedPresetId: 'custom_solid', customSolidColor: color, customGradient: null);
    final box = await Hive.openBox('settings');
    await box.put('wallpaper_preset', 'custom_solid');
    await box.put('wallpaper_custom_solid', color.toARGB32());
    await box.delete('wallpaper_custom_gradient');
  }

  Future<void> setCustomGradient(Color colA, Color colB) async {
    state = state.copyWith(selectedPresetId: 'custom_gradient', customSolidColor: null, customGradient: [colA, colB]);
    final box = await Hive.openBox('settings');
    await box.put('wallpaper_preset', 'custom_gradient');
    await box.put('wallpaper_custom_gradient', [colA.toARGB32(), colB.toARGB32()]);
    await box.delete('wallpaper_custom_solid');
  }

  WallpaperPreset get activePreset {
    return presets.firstWhere(
      (p) => p.id == state.selectedPresetId,
      orElse: () => presets.first,
    );
  }
}

final wallpaperProvider = StateNotifierProvider<WallpaperNotifier, WallpaperState>((ref) {
  return WallpaperNotifier();
});
