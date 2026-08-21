import 'package:flutter/material.dart';

/// Paleta corporativa: el azul es el color principal; el blanco y el
/// amarillo son los secundarios.
class AppColors {
  const AppColors._();

  static const Color azul = Color(0xFF0D3C7E);
  static const Color azulOscuro = Color(0xFF082A5C);
  static const Color azulMedio = Color(0xFF1B5AAE);
  static const Color azulClaro = Color(0xFFE4EBF6);
  static const Color amarillo = Color(0xFFF5A623);
  static const Color amarilloClaro = Color(0xFFFFF0D6);

  /// Amarillo oscurecido: el amarillo puro no se lee sobre blanco.
  static const Color amarilloTexto = Color(0xFFB87400);

  static const Color blanco = Color(0xFFFFFFFF);
  static const Color fondo = Color(0xFFF4F6FA);
  static const Color texto = Color(0xFF121A2B);
  static const Color textoSuave = Color(0xFF5B6478);
  static const Color borde = Color(0xFFD8DFEC);
  static const Color rojo = Color(0xFFB3261E);

  /// Estados. La marca solo tiene azul y amarillo, así que "cumplido" usa
  /// azul y "pendiente / incumplido" amarillo, en vez de verde y naranja.
  static const Color cumplido = azul;
  static const Color pendiente = amarilloTexto;
  static const Color neutro = textoSuave;

  /// Versiones para fondos oscuros (banner azul, tema oscuro).
  static const Color cumplidoSobreAzul = amarillo;
  static const Color neutroSobreAzul = Color(0xFFB9C6DC);
}

class AppTheme {
  const AppTheme._();

  static const ColorScheme _esquemaClaro = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.azul,
    onPrimary: AppColors.blanco,
    primaryContainer: AppColors.azul,
    onPrimaryContainer: AppColors.blanco,
    secondary: AppColors.amarillo,
    onSecondary: Color(0xFF3A2400),
    secondaryContainer: AppColors.amarilloClaro,
    onSecondaryContainer: Color(0xFF573700),
    tertiary: AppColors.azulMedio,
    onTertiary: AppColors.blanco,
    tertiaryContainer: AppColors.azulClaro,
    onTertiaryContainer: AppColors.azulOscuro,
    error: AppColors.rojo,
    onError: AppColors.blanco,
    errorContainer: Color(0xFFFBDAD6),
    onErrorContainer: Color(0xFF6B140F),
    surface: AppColors.blanco,
    onSurface: AppColors.texto,
    surfaceContainerLowest: AppColors.blanco,
    surfaceContainerLow: Color(0xFFFAFBFD),
    surfaceContainer: AppColors.fondo,
    surfaceContainerHigh: Color(0xFFEDF1F8),
    surfaceContainerHighest: AppColors.azulClaro,
    onSurfaceVariant: AppColors.textoSuave,
    outline: AppColors.borde,
    outlineVariant: Color(0xFFE8ECF4),
    inverseSurface: AppColors.azulOscuro,
    onInverseSurface: AppColors.blanco,
    inversePrimary: AppColors.amarillo,
  );

  static const ColorScheme _esquemaOscuro = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.amarillo,
    onPrimary: Color(0xFF2B1800),
    primaryContainer: AppColors.azul,
    onPrimaryContainer: AppColors.blanco,
    secondary: AppColors.blanco,
    onSecondary: AppColors.azulOscuro,
    secondaryContainer: Color(0xFF14315E),
    onSecondaryContainer: AppColors.blanco,
    tertiary: Color(0xFF9BC0F0),
    onTertiary: AppColors.azulOscuro,
    tertiaryContainer: AppColors.azulMedio,
    onTertiaryContainer: AppColors.blanco,
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF071B33),
    onSurface: Color(0xFFE6ECF6),
    surfaceContainerLowest: Color(0xFF051426),
    surfaceContainerLow: Color(0xFF0A2140),
    surfaceContainer: Color(0xFF0C264A),
    surfaceContainerHigh: Color(0xFF102D55),
    surfaceContainerHighest: Color(0xFF143462),
    onSurfaceVariant: Color(0xFFB9C6DC),
    outline: Color(0xFF244C82),
    outlineVariant: Color(0xFF1A3A66),
    inverseSurface: AppColors.blanco,
    onInverseSurface: AppColors.azulOscuro,
    inversePrimary: AppColors.azul,
  );

  static ThemeData get claro => _construir(_esquemaClaro, AppColors.fondo);

  static ThemeData get oscuro =>
      _construir(_esquemaOscuro, const Color(0xFF051426));

  static ThemeData _construir(ColorScheme scheme, Color fondoScaffold) {
    final esClaro = scheme.brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: fondoScaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.azul,
        foregroundColor: AppColors.blanco,
        elevation: 0,
        centerTitle: false,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.blanco,
        unselectedLabelColor: const Color(0xFFB9C6DC),
        indicatorColor: AppColors.amarillo,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: esClaro ? AppColors.blanco : scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.azul,
          foregroundColor: AppColors.blanco,
          disabledBackgroundColor: esClaro
              ? AppColors.azulClaro
              : scheme.surfaceContainerHigh,
          disabledForegroundColor: AppColors.textoSuave,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: esClaro ? AppColors.azul : AppColors.amarillo,
          side: BorderSide(
            color: esClaro ? AppColors.azul : AppColors.amarillo,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: esClaro ? AppColors.azul : AppColors.amarillo,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.amarillo,
        foregroundColor: Color(0xFF3A2400),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.amarillo,
        linearTrackColor:
            esClaro ? AppColors.azulClaro : scheme.surfaceContainerHigh,
        circularTrackColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: esClaro ? AppColors.azul : AppColors.amarillo,
            width: 2,
          ),
        ),
        prefixIconColor: esClaro ? AppColors.azul : AppColors.amarillo,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.azulOscuro,
        contentTextStyle: TextStyle(color: AppColors.blanco),
        actionTextColor: AppColors.amarillo,
        behavior: SnackBarBehavior.fixed,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      listTileTheme: ListTileThemeData(
        iconColor: esClaro ? AppColors.azul : AppColors.amarillo,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
