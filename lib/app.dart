import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/home/splash_screen.dart';
import 'providers/theme_provider.dart';

class StickerMakerApp extends ConsumerWidget {
  const StickerMakerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeMember = ref.watch(themeMemberProvider);

    return MaterialApp(
      title: 'Bocchi Stickers',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(activeMember, Brightness.light),
      darkTheme: AppTheme.buildTheme(activeMember, Brightness.dark),
      themeMode: ThemeMode
          .dark, // Modo oscuro por defecto para lucir los colores neón/marino
      home: const SplashScreen(),
    );
  }
}
