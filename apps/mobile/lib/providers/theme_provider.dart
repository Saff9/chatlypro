import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'dart:math';

enum ThemeStyle {
  light, dark, ocean, forest, sunset, custom,
  charcoal, obsidian, amberglow, midnight, deeppurple,
  nordic, dracula, solarized, monokai, cyberpunk,
  rosegold, platinum, champagne, copper, titanium,
  emerald, cobalt, amethyst, sapphire, ruby,
  plum, lavender, mint, forestgreen, olive,
  cream, mocha, latte, chocolate, terracotta,
  slate, steel, ice, neon, retro,
  vaporwave, sakura, tea, apricot, coral,
  peach, bronze, silver, gold
}

class ThemeParams {
  final Brightness brightness;
  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color text;
  final Color textSecondary;

  ThemeParams({
    required this.brightness,
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.text,
    required this.textSecondary,
  });
}

class ThemeNotifier extends StateNotifier<ThemeStyle> {
  ThemeNotifier() : super(ThemeStyle.dark) {
    _loadTheme();
  }

  Color _customPrimaryColor = const Color(0xFF6366F1);
  Color _customSecondaryColor = const Color(0xFF10B981);

  Color get customPrimary => _customPrimaryColor;
  Color get customSecondary => _customSecondaryColor;

  Future<void> _loadTheme() async {
    final settingsBox = await Hive.openBox('settings');
    final storedStyle = settingsBox.get('theme_style', defaultValue: 'dark');
    final primaryHex = settingsBox.get('custom_primary_color');
    final secondaryHex = settingsBox.get('custom_secondary_color');

    if (primaryHex != null) _customPrimaryColor = Color(primaryHex);
    if (secondaryHex != null) _customSecondaryColor = Color(secondaryHex);

    final resolvedStyle = ThemeStyle.values.firstWhere(
      (e) => e.name == storedStyle,
      orElse: () => ThemeStyle.dark,
    );
    state = resolvedStyle;
  }

  Future<void> selectTheme(ThemeStyle style) async {
    state = style;
    final settingsBox = await Hive.openBox('settings');
    await settingsBox.put('theme_style', style.name);
  }

  Future<void> setCustomColors(Color primary, Color secondary) async {
    _customPrimaryColor = primary;
    _customSecondaryColor = secondary;
    state = ThemeStyle.custom;

    final settingsBox = await Hive.openBox('settings');
    await settingsBox.put('theme_style', ThemeStyle.custom.name);
    // Store colors as their ARGB integer value (toARGB32 is the non-deprecated
    // replacement for the removed .value accessor on Color).
    await settingsBox.put('custom_primary_color', primary.toARGB32());
    await settingsBox.put('custom_secondary_color', secondary.toARGB32());
  }

  /// Selects a random theme from the 50 pre-built styles
  Future<void> randomizeTheme() async {
    // Avoid selecting 'custom' as a random preset
    final List<ThemeStyle> selectable = ThemeStyle.values.where((t) => t != ThemeStyle.custom).toList();
    final random = Random();
    final selected = selectable[random.nextInt(selectable.length)];
    await selectTheme(selected);
  }

  ThemeParams getThemeParams(ThemeStyle style) {
    switch (style) {
      case ThemeStyle.light:
        return ThemeParams(
          brightness: Brightness.light,
          primary: const Color(0xFF2481cc),
          secondary: const Color(0xFF527fa6),
          background: const Color(0xFFf0f5fa),
          surface: Colors.white,
          text: const Color(0xFF000000),
          textSecondary: const Color(0xFF707f8c),
        );
      case ThemeStyle.dark:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF5288c1),
          secondary: const Color(0xFF2f6ea5),
          background: const Color(0xFF17212b),
          surface: const Color(0xFF1e2b38),
          text: const Color(0xFFf5f6f7),
          textSecondary: const Color(0xFF7f8c9a),
        );
      case ThemeStyle.ocean:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF06B6D4),
          secondary: const Color(0xFF14B8A6),
          background: const Color(0xFF020617),
          surface: const Color(0xFF0F172A),
          text: const Color(0xFFF8FAFC),
          textSecondary: const Color(0xFF94A3B8),
        );
      case ThemeStyle.forest:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF10B981),
          secondary: const Color(0xFF84CC16),
          background: const Color(0xFF050B08),
          surface: const Color(0xFF0A1410),
          text: const Color(0xFFF0FDF4),
          textSecondary: const Color(0xFF86EFAC),
        );
      case ThemeStyle.sunset:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFF43F5E),
          secondary: const Color(0xFFF59E0B),
          background: const Color(0xFF0F050B),
          surface: const Color(0xFF1B0B14),
          text: const Color(0xFFFFF1F2),
          textSecondary: const Color(0xFFFDA4AF),
        );
      case ThemeStyle.custom:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: _customPrimaryColor,
          secondary: _customSecondaryColor,
          background: const Color(0xFF0B0F19),
          surface: const Color(0xFF141B2D),
          text: Colors.white,
          textSecondary: Colors.white70,
        );
      case ThemeStyle.charcoal:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF94A3B8),
          secondary: const Color(0xFF475569),
          background: const Color(0xFF0F172A),
          surface: const Color(0xFF1E293B),
          text: const Color(0xFFF8FAFC),
          textSecondary: const Color(0xFF94A3B8),
        );
      case ThemeStyle.obsidian:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF818CF8),
          secondary: const Color(0xFF34D399),
          background: const Color(0xFF0B0F19),
          surface: const Color(0xFF161F30),
          text: const Color(0xFFF8FAFC),
          textSecondary: const Color(0xFF94A3B8),
        );
      case ThemeStyle.amberglow:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFF59E0B),
          secondary: const Color(0xFFD97706),
          background: const Color(0xFF1C1917),
          surface: const Color(0xFF292524),
          text: const Color(0xFFFAFAF9),
          textSecondary: const Color(0xFFD6D3D1),
        );
      case ThemeStyle.midnight:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF3B82F6),
          secondary: const Color(0xFF1D4ED8),
          background: const Color(0xFF090D16),
          surface: const Color(0xFF111827),
          text: const Color(0xFFF9FAFB),
          textSecondary: const Color(0xFF9CA3AF),
        );
      case ThemeStyle.deeppurple:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF8B5CF6),
          secondary: const Color(0xFF6D28D9),
          background: const Color(0xFF120E2E),
          surface: const Color(0xFF1D174A),
          text: const Color(0xFFF5F3FF),
          textSecondary: const Color(0xFFC084FC),
        );
      case ThemeStyle.nordic:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF88C0D0),
          secondary: const Color(0xFF81A1C1),
          background: const Color(0xFF2E3440),
          surface: const Color(0xFF3B4252),
          text: const Color(0xFFECEFF4),
          textSecondary: const Color(0xFFD8DEE9),
        );
      case ThemeStyle.dracula:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFBD93F9),
          secondary: const Color(0xFFFF79C6),
          background: const Color(0xFF282A36),
          surface: const Color(0xFF44475A),
          text: const Color(0xFFF8F8F2),
          textSecondary: const Color(0xFF6272A4),
        );
      case ThemeStyle.solarized:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF2AA198),
          secondary: const Color(0xFF859900),
          background: const Color(0xFF002B36),
          surface: const Color(0xFF073642),
          text: const Color(0xFF93A1A1),
          textSecondary: const Color(0xFF586E75),
        );
      case ThemeStyle.monokai:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFA6E22E),
          secondary: const Color(0xFFF92672),
          background: const Color(0xFF272822),
          surface: const Color(0xFF3E3D32),
          text: const Color(0xFFF8F8F2),
          textSecondary: const Color(0xFF75715E),
        );
      case ThemeStyle.cyberpunk:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF00F0FF),
          secondary: const Color(0xFFFF007F),
          background: const Color(0xFF0B071E),
          surface: const Color(0xFF1B0F3A),
          text: const Color(0xFFF0F6FC),
          textSecondary: const Color(0xFFB1BAC4),
        );
      case ThemeStyle.rosegold:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFE0A96D),
          secondary: const Color(0xFFD8A7B1),
          background: const Color(0xFF2C1E21),
          surface: const Color(0xFF3D2C2F),
          text: const Color(0xFFFFF0F5),
          textSecondary: const Color(0xFFFFD1DC),
        );
      case ThemeStyle.platinum:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFE5E7EB),
          secondary: const Color(0xFF9CA3AF),
          background: const Color(0xFF111827),
          surface: const Color(0xFF1F2937),
          text: const Color(0xFFF9FAFB),
          textSecondary: const Color(0xFF9CA3AF),
        );
      case ThemeStyle.champagne:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFF3E5AB),
          secondary: const Color(0xFFC5B358),
          background: const Color(0xFF1A1916),
          surface: const Color(0xFF2B2822),
          text: const Color(0xFFFFFDD0),
          textSecondary: const Color(0xFFE6D690),
        );
      case ThemeStyle.copper:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFB87333),
          secondary: const Color(0xFF8C4C10),
          background: const Color(0xFF171210),
          surface: const Color(0xFF2B1F1B),
          text: const Color(0xFFFFF5F0),
          textSecondary: const Color(0xFFD4A373),
        );
      case ThemeStyle.titanium:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF8A95A5),
          secondary: const Color(0xFF5C6573),
          background: const Color(0xFF14171A),
          surface: const Color(0xFF202429),
          text: const Color(0xFFF1F2F5),
          textSecondary: const Color(0xFFA6AEB9),
        );
      case ThemeStyle.emerald:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF059669),
          secondary: const Color(0xFF10B981),
          background: const Color(0xFF06231C),
          surface: const Color(0xFF0A3E30),
          text: const Color(0xFFECFDF5),
          textSecondary: const Color(0xFFA7F3D0),
        );
      case ThemeStyle.cobalt:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF1E40AF),
          secondary: const Color(0xFF3B82F6),
          background: const Color(0xFF0F1E36),
          surface: const Color(0xFF1B3154),
          text: const Color(0xFFEFF6FF),
          textSecondary: const Color(0xFFBFDBFE),
        );
      case ThemeStyle.amethyst:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF9333EA),
          secondary: const Color(0xFFA855F7),
          background: const Color(0xFF1C0D2E),
          surface: const Color(0xFF2E1B4E),
          text: const Color(0xFFFAF5FF),
          textSecondary: const Color(0xFFE9D5FF),
        );
      case ThemeStyle.sapphire:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF2563EB),
          secondary: const Color(0xFF60A5FA),
          background: const Color(0xFF0D1B2A),
          surface: const Color(0xFF1B263B),
          text: const Color(0xFFE0E1DD),
          textSecondary: const Color(0xFF778DA9),
        );
      case ThemeStyle.ruby:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFDC2626),
          secondary: const Color(0xFFEF4444),
          background: const Color(0xFF240A0A),
          surface: const Color(0xFF3F1414),
          text: const Color(0xFFFEF2F2),
          textSecondary: const Color(0xFFFCA5A5),
        );
      case ThemeStyle.plum:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF800080),
          secondary: const Color(0xFFDA70D6),
          background: const Color(0xFF1E0A1E),
          surface: const Color(0xFF341434),
          text: const Color(0xFFFFF0FF),
          textSecondary: const Color(0xFFEE82EE),
        );
      case ThemeStyle.lavender:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFE6E6FA),
          secondary: const Color(0xFFB0C4DE),
          background: const Color(0xFF1F1F2E),
          surface: const Color(0xFF2E2E42),
          text: const Color(0xFFF5F5FA),
          textSecondary: const Color(0xFFD8D8E6),
        );
      case ThemeStyle.mint:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF3EB489),
          secondary: const Color(0xFF7FFFD4),
          background: const Color(0xFF0E1F1A),
          surface: const Color(0xFF1A362E),
          text: const Color(0xFFF5FFFA),
          textSecondary: const Color(0xFFE0FFFF),
        );
      case ThemeStyle.forestgreen:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF228B22),
          secondary: const Color(0xFF00FF00),
          background: const Color(0xFF091F09),
          surface: const Color(0xFF143B14),
          text: const Color(0xFFF0FFF0),
          textSecondary: const Color(0xFF98FB98),
        );
      case ThemeStyle.olive:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF808000),
          secondary: const Color(0xFF9ACD32),
          background: const Color(0xFF17170E),
          surface: const Color(0xFF2B2B1B),
          text: const Color(0xFFFFFFF0),
          textSecondary: const Color(0xFFEEE8AA),
        );
      case ThemeStyle.cream:
        return ThemeParams(
          brightness: Brightness.light,
          primary: const Color(0xFF8B5A2B),
          secondary: const Color(0xFFCDAA7D),
          background: const Color(0xFFFFFDD0),
          surface: const Color(0xFFFFFFF0),
          text: const Color(0xFF4A2F13),
          textSecondary: const Color(0xFF8B7355),
        );
      case ThemeStyle.mocha:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFC7A75C),
          secondary: const Color(0xFF8B5A2B),
          background: const Color(0xFF1C1412),
          surface: const Color(0xFF2E201B),
          text: const Color(0xFFFDFBF7),
          textSecondary: const Color(0xFFD2B48C),
        );
      case ThemeStyle.latte:
        return ThemeParams(
          brightness: Brightness.light,
          primary: const Color(0xFF6F4E37),
          secondary: const Color(0xFFA67C00),
          background: const Color(0xFFF3E5D8),
          surface: const Color(0xFFFFFBF0),
          text: const Color(0xFF3E2723),
          textSecondary: const Color(0xFF795548),
        );
      case ThemeStyle.chocolate:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF7B3F00),
          secondary: const Color(0xFFD2691E),
          background: const Color(0xFF1A0E08),
          surface: const Color(0xFF2D1B11),
          text: const Color(0xFFFFF5F0),
          textSecondary: const Color(0xFFF4A460),
        );
      case ThemeStyle.terracotta:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFE2725B),
          secondary: const Color(0xFFCD5C5C),
          background: const Color(0xFF2B1814),
          surface: const Color(0xFF3F2621),
          text: const Color(0xFFFFF0EC),
          textSecondary: const Color(0xFFE09F90),
        );
      case ThemeStyle.slate:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF708090),
          secondary: const Color(0xFF778899),
          background: const Color(0xFF1E242B),
          surface: const Color(0xFF2A313C),
          text: const Color(0xFFF5F6F8),
          textSecondary: const Color(0xFFC0C5CE),
        );
      case ThemeStyle.steel:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF4682B4),
          secondary: const Color(0xFFB0C4DE),
          background: const Color(0xFF151B24),
          surface: const Color(0xFF222B3A),
          text: const Color(0xFFF0F4F8),
          textSecondary: const Color(0xFFA0B2C6),
        );
      case ThemeStyle.ice:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFAFEEEE),
          secondary: const Color(0xFFE0FFFF),
          background: const Color(0xFF0F1D23),
          surface: const Color(0xFF1D333D),
          text: const Color(0xFFF0FFFF),
          textSecondary: const Color(0xFFB0E0E6),
        );
      case ThemeStyle.neon:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFF39FF14),
          secondary: const Color(0xFF00FFFF),
          background: const Color(0xFF080D08),
          surface: const Color(0xFF142414),
          text: const Color(0xFFF0FFF0),
          textSecondary: const Color(0xFF7FFF00),
        );
      case ThemeStyle.retro:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFFF5E7E),
          secondary: const Color(0xFFFFBB00),
          background: const Color(0xFF251B35),
          surface: const Color(0xFF3B2E54),
          text: const Color(0xFFFFEBF0),
          textSecondary: const Color(0xFFFF94B8),
        );
      case ThemeStyle.vaporwave:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFE024C3),
          secondary: const Color(0xFF24E0D2),
          background: const Color(0xFF120324),
          surface: const Color(0xFF2A0F4D),
          text: const Color(0xFFFFF0FA),
          textSecondary: const Color(0xFFF2A3EB),
        );
      case ThemeStyle.sakura:
        return ThemeParams(
          brightness: Brightness.light,
          primary: const Color(0xFFFFB7C5),
          secondary: const Color(0xFFFFC0CB),
          background: const Color(0xFFFFF5F7),
          surface: Colors.white,
          text: const Color(0xFF4A1A22),
          textSecondary: const Color(0xFFB86B77),
        );
      case ThemeStyle.tea:
        return ThemeParams(
          brightness: Brightness.light,
          primary: const Color(0xFF90E0EF),
          secondary: const Color(0xFF0096C7),
          background: const Color(0xFFEDF2F4),
          surface: Colors.white,
          text: const Color(0xFF2B2D42),
          textSecondary: const Color(0xFF8D99AE),
        );
      case ThemeStyle.apricot:
        return ThemeParams(
          brightness: Brightness.light,
          primary: const Color(0xFFFB8500),
          secondary: const Color(0xFFFFB703),
          background: const Color(0xFFFEFAE0),
          surface: Colors.white,
          text: const Color(0xFF283618),
          textSecondary: const Color(0xFF606C38),
        );
      case ThemeStyle.coral:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFFF7F50),
          secondary: const Color(0xFFFF6347),
          background: const Color(0xFF29150E),
          surface: const Color(0xFF3D2319),
          text: const Color(0xFFFFF0EC),
          textSecondary: const Color(0xFFFFA07A),
        );
      case ThemeStyle.peach:
        return ThemeParams(
          brightness: Brightness.light,
          primary: const Color(0xFFFFDAB9),
          secondary: const Color(0xFFFFA07A),
          background: const Color(0xFFFFF8F0),
          surface: Colors.white,
          text: const Color(0xFF5C3D2E),
          textSecondary: const Color(0xFF8C624E),
        );
      case ThemeStyle.bronze:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFCD7F32),
          secondary: const Color(0xFFA57164),
          background: const Color(0xFF1A130E),
          surface: const Color(0xFF2B201A),
          text: const Color(0xFFFFF8F5),
          textSecondary: const Color(0xFFE5AA70),
        );
      case ThemeStyle.silver:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFC0C0C0),
          secondary: const Color(0xFFA9A9A9),
          background: const Color(0xFF1E1E1E),
          surface: const Color(0xFF2D2D2D),
          text: const Color(0xFFF5F5F5),
          textSecondary: const Color(0xFFD3D3D3),
        );
      case ThemeStyle.gold:
        return ThemeParams(
          brightness: Brightness.dark,
          primary: const Color(0xFFFFD700),
          secondary: const Color(0xFFDAA520),
          background: const Color(0xFF1C1A0E),
          surface: const Color(0xFF2F2B18),
          text: const Color(0xFFFFFFF0),
          textSecondary: const Color(0xFFEEE8AA),
        );
    }
  }

  ThemeData getThemeData(AppFontFamily font) {
    final params = getThemeParams(state);
    return _buildTheme(
      brightness: params.brightness,
      primary: params.primary,
      secondary: params.secondary,
      background: params.background,
      surface: params.surface,
      text: params.text,
      textSecondary: params.textSecondary,
      fontFamily: font,
    );
  }

  ThemeData _buildTheme({
    required Brightness brightness,
    required Color primary,
    required Color secondary,
    required Color background,
    required Color surface,
    required Color text,
    required Color textSecondary,
    required AppFontFamily fontFamily,
  }) {
    TextTheme baseTextTheme = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;

    TextTheme selectedTextTheme;
    switch (fontFamily) {
      case AppFontFamily.montserrat:
        selectedTextTheme = GoogleFonts.montserratTextTheme(baseTextTheme);
        break;
      case AppFontFamily.roboto:
        selectedTextTheme = GoogleFonts.robotoTextTheme(baseTextTheme);
        break;
      case AppFontFamily.inter:
        selectedTextTheme = GoogleFonts.interTextTheme(baseTextTheme);
        break;
      case AppFontFamily.outfit:
        selectedTextTheme = GoogleFonts.outfitTextTheme(baseTextTheme);
        break;
    }

    return ThemeData(
      brightness: brightness,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      cardColor: surface,
      textTheme: selectedTextTheme.copyWith(
        bodyLarge: selectedTextTheme.bodyLarge?.copyWith(color: text, fontSize: 16),
        bodyMedium: selectedTextTheme.bodyMedium?.copyWith(color: textSecondary, fontSize: 14),
        titleLarge: selectedTextTheme.titleLarge?.copyWith(color: text, fontWeight: FontWeight.bold, fontSize: 20),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: text),
        titleTextStyle: TextStyle(color: text, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: ThemeData.estimateBrightnessForColor(primary) == Brightness.light
              ? const Color(0xFF13131B)
              : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
        hintStyle: GoogleFonts.inter(color: textSecondary.withValues(alpha: 0.7)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
    );
  }
}

enum AppFontFamily { outfit, montserrat, roboto, inter }

class FontNotifier extends StateNotifier<AppFontFamily> {
  FontNotifier() : super(AppFontFamily.outfit) {
    _loadFont();
  }

  Future<void> _loadFont() async {
    final box = await Hive.openBox('settings');
    final stored = box.get('font_style', defaultValue: 'outfit');
    state = AppFontFamily.values.firstWhere(
      (e) => e.name == stored,
      orElse: () => AppFontFamily.outfit,
    );
  }

  Future<void> selectFont(AppFontFamily font) async {
    state = font;
    final box = await Hive.openBox('settings');
    await box.put('font_style', font.name);
  }
}

final fontProvider = StateNotifierProvider<FontNotifier, AppFontFamily>((ref) {
  return FontNotifier();
});

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeStyle>((ref) {
  return ThemeNotifier();
});
