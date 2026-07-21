import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const List<Color> coloresDisponibles = [
    Color(0xFFFF7A00), // Naranja Tata
    Color(0xFFFF9E1B),
    Color(0xFFFFC166),
    Color(0xFF6B7280), // Gris
    Color(0xFF9CA3AF), // Gris claro
    Color(0xFF2563EB), // Azul
    Color(0xFF16A34A), // Verde
  ];

  static const List<String> fuentesDisponibles = [
    'Poppins',
    'Inter',
    'Roboto',
    'Open Sans',
    'Montserrat',
    'Lato',
    'Nunito',
  ];

  static TextTheme _textTheme(String fuente) {
    switch (fuente) {
      case 'Inter':
        return GoogleFonts.interTextTheme();
      case 'Roboto':
        return GoogleFonts.robotoTextTheme();
      case 'Open Sans':
        return GoogleFonts.openSansTextTheme();
      case 'Montserrat':
        return GoogleFonts.montserratTextTheme();
      case 'Lato':
        return GoogleFonts.latoTextTheme();
      case 'Nunito':
        return GoogleFonts.nunitoTextTheme();
      default:
        return GoogleFonts.poppinsTextTheme();
    }
  }

  /// El color elegido es el acento real (sin forzar naranja en grises).
  static Color accentFromSeed(Color seed) => seed;

  static ThemeData _buildTheme({
    required Color seed,
    required Brightness brightness,
    required String fuente,
  }) {
    final accent = accentFromSeed(seed);
    // Esquema completo desde el acento elegido → primary, containers,
    // switches, chips y botones van en conjunto.
    final baseScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    final onAccent =
        accent.computeLuminance() > 0.55 ? Colors.black : Colors.white;
    final colorScheme = baseScheme.copyWith(
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      tertiary: Color.lerp(accent, baseScheme.tertiary, 0.25)!,
      primaryContainer: Color.lerp(
        accent,
        brightness == Brightness.dark
            ? Colors.white
            : Colors.black,
        brightness == Brightness.dark ? 0.25 : 0.12,
      )!,
      secondaryContainer: Color.lerp(
        accent,
        brightness == Brightness.dark ? Colors.black : Colors.white,
        0.55,
      )!,
      surfaceTint: accent,
    );
    final textTheme = _textTheme(fuente).apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      textTheme: textTheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.onSurface,
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 2,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.08),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor:
              colorScheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor:
              colorScheme.onSurface.withValues(alpha: 0.38),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return null;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return null;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return null;
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return null;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.onPrimary),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
    );
  }

  static ThemeData light(Color seed, String fuente) {
    return _buildTheme(
      seed: seed,
      brightness: Brightness.light,
      fuente: fuente,
    );
  }

  static ThemeData dark(Color seed, String fuente) {
    final base = _buildTheme(
      seed: seed,
      brightness: Brightness.dark,
      fuente: fuente,
    );
    final cs = base.colorScheme;
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0F1419),
      cardTheme: base.cardTheme.copyWith(
        color: const Color(0xFF1A222C),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1A222C),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(0xFF151B22),
        selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurfaceVariant,
      ),
      dividerColor: cs.outlineVariant.withValues(alpha: 0.4),
      listTileTheme: ListTileThemeData(
        iconColor: cs.onSurfaceVariant,
        textColor: cs.onSurface,
      ),
    );
  }
}
