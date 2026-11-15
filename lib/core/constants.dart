class AppConstants {
  AppConstants._();

  // Límites estrictos de WhatsApp
  static const int minStickersPerPack = 3;
  static const int maxStickersPerPack = 30;
  static const int maxEmojisPerSticker = 3;
  static const int minEmojisPerSticker = 1;

  static const int stickerSizePx = 512;
  static const int stickerMarginPx = 16;
  static const int maxStickerFileSizeBytes = 100 * 1024; // 100 KB estáticos
  static const int maxAnimatedStickerFileSizeBytes =
      500 * 1024; // 500 KB animados

  static const int trayIconSizePx = 96;
  static const int maxTrayFileSizeBytes = 50 * 1024; // 50 KB

  static const int maxNameLength = 128;
  static const String defaultPublisher = 'Axel Guerrero';

  // Nombres de archivos y carpetas locales
  static const String packsJsonFileName = 'packs.json';
  static const String whatsappRegistryFileName = 'whatsapp_packs.json';
  static const String packsFolderName = 'packs';
}
