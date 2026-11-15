import 'package:flutter/material.dart';

enum KessokuMember {
  bocchi(
    id: 'bocchi',
    displayName: 'Bocchi',
    fullName: 'Hitori Gotoh',
    role: 'Guitarra líder • Rosa Bocchi',
    quote: '「ひとりじゃ、ないかも…！」\n¡Quizá no estoy sola...!',
    assetPath: 'assets/characters/bocchi.png',
    primaryColor: Color(0xFFFF66A3),
    secondaryColor: Color(0xFF4DD0E1), // Cubo azul de Bocchi
    surfaceTint: Color(0xFF2A1521),
    badgeEmoji: '🌸',
  ),
  kita(
    id: 'kita',
    displayName: 'Kita',
    fullName: 'Ikuyo Kita',
    role: 'Voz y Guitarra • Rojo Kita-Aura',
    quote: '「キラキラで、いこう！」\n¡Vamos con todo el brillo!',
    assetPath: 'assets/characters/kita.png',
    primaryColor: Color(0xFFFF2E55),
    secondaryColor: Color(0xFFFFD54F),
    surfaceTint: Color(0xFF2D1218),
    badgeEmoji: '❤️',
  ),
  ryo(
    id: 'ryo',
    displayName: 'Ryo',
    fullName: 'Ryo Yamada',
    role: 'Bajo • Negro & Azul Marino',
    quote: '「ステッカー作り、無料…お金、貸して」\nHacer stickers es gratis... préstame dinero.',
    assetPath: 'assets/characters/ryo.png',
    primaryColor: Color(0xFF3B82F6),
    secondaryColor: Color(0xFF1E3A8A),
    surfaceTint: Color(0xFF0A1124), // Negro con azul marino profundo
    badgeEmoji: '💙',
  ),
  nijika(
    id: 'nijika',
    displayName: 'Nijika',
    fullName: 'Nijika Ijichi',
    role: 'Batería • Amarillo Dorito',
    quote: '「さあ、ライブ始めるよ！」\n¡Vamos, que empieza el show!',
    assetPath: 'assets/characters/nijika.png',
    primaryColor: Color(0xFFFFB300),
    secondaryColor: Color(0xFFFF7043),
    surfaceTint: Color(0xFF2B210D),
    badgeEmoji: '💛',
  );

  final String id;
  final String displayName;
  final String fullName;
  final String role;
  final String quote;
  final String assetPath;
  final Color primaryColor;
  final Color secondaryColor;
  final Color surfaceTint;
  final String badgeEmoji;

  const KessokuMember({
    required this.id,
    required this.displayName,
    required this.fullName,
    required this.role,
    required this.quote,
    required this.assetPath,
    required this.primaryColor,
    required this.secondaryColor,
    required this.surfaceTint,
    required this.badgeEmoji,
  });

  static KessokuMember fromId(String? id) {
    return KessokuMember.values.firstWhere(
      (m) => m.id == id,
      orElse: () => KessokuMember.bocchi,
    );
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData buildTheme(KessokuMember member, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final baseScheme = ColorScheme.fromSeed(
      seedColor: member.primaryColor,
      brightness: brightness,
    );

    // En modo oscuro (especialmente para Ryo: negro con azul marino) damos un matiz profundo personalizado
    final Color scaffoldBg = isDark
        ? Color.lerp(const Color(0xFF0D0E12), member.surfaceTint, 0.55)!
        : Color.lerp(Colors.white, member.primaryColor, 0.06)!;

    final Color cardBg = isDark
        ? Color.lerp(const Color(0xFF181A22), member.surfaceTint, 0.65)!
        : Colors.white;

    final colorScheme = baseScheme.copyWith(
      primary: member.primaryColor,
      secondary: member.secondaryColor,
      surface: scaffoldBg,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      fontFamily: 'Nunito',
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: scaffoldBg,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: member.primaryColor.withValues(alpha: isDark ? 0.35 : 0.25),
            width: 1.5,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: member.primaryColor,
        foregroundColor:
            member == KessokuMember.nijika ? Colors.black87 : Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}
