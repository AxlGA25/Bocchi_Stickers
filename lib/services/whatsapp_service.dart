import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../data/models/sticker.dart';
import '../data/models/sticker_pack.dart';
import 'image_export_service.dart';

class WhatsAppExportResult {
  final bool added;
  final String message;
  final StickerPack updatedPack;

  const WhatsAppExportResult({
    required this.added,
    required this.message,
    required this.updatedPack,
  });
}

class WhatsAppService {
  static const MethodChannel _channel =
      MethodChannel('com.axel.sticker_maker/whatsapp');

  final ImageExportService _exportService;

  WhatsAppService(this._exportService);

  Future<bool> isAnyWhatsAppInstalled() async {
    try {
      final dynamic raw = await _channel.invokeMethod('isWhatsAppInstalled');
      if (raw is Map) {
        return (raw['any'] as bool?) ?? false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<WhatsAppExportResult> exportAndSendPackToWhatsApp({
    required StickerPack pack,
    required List<StickerPack> allPacks,
  }) async {
    if (pack.stickers.length < AppConstants.minStickersPerPack) {
      throw const StickerValidationException(
        'El paquete necesita al menos 3 stickers para agregarse a WhatsApp.',
      );
    }
    if (pack.stickers.length > AppConstants.maxStickersPerPack) {
      throw const StickerValidationException(
        'El paquete no puede tener más de 30 stickers.',
      );
    }

    final installed = await isAnyWhatsAppInstalled();
    if (!installed) {
      throw const StickerValidationException(
        'No se detectó WhatsApp ni WhatsApp Business instalado en este teléfono.',
      );
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final packDir =
        Directory('${docsDir.path}/${AppConstants.packsFolderName}/${pack.id}');
    await packDir.create(recursive: true);

    final newVersion = pack.imageDataVersion + 1;

    String trayPath = pack.trayImagePath ?? '${packDir.path}/tray.png';
    File trayFile = File(trayPath);
    if (!await trayFile.exists()) {
      final firstSource = File(pack.stickers.first.sourcePath);
      final trayBytes = await _exportService.createValidatedTrayIcon(
        await firstSource.readAsBytes(),
      );
      trayFile = File('${packDir.path}/tray.png');
      await trayFile.writeAsBytes(trayBytes, flush: true);
      trayPath = trayFile.path;
    }

    final exportedStickers = <Sticker>[];
    final List<Map<String, dynamic>> providerStickersMeta =
        <Map<String, dynamic>>[];

    for (int i = 0; i < pack.stickers.length; i++) {
      final s = pack.stickers[i];
      final emojis = s.emojis.isEmpty
          ? const ['😀']
          : s.emojis.take(AppConstants.maxEmojisPerSticker).toList();

      final stickerDir = File(s.sourcePath).parent;
      final webpFileName = '${s.id}_v$newVersion.webp';
      final webpPath = '${stickerDir.path}/$webpFileName';

      File exportedFile;
      if (pack.isAnimatedPack || s.isAnimated) {
        final existingWebp = File(s.webpPath ?? s.sourcePath);
        exportedFile = await existingWebp.copy(webpPath);
      } else {
        exportedFile = await _exportService.exportStickerFile(
          sourcePngPath: s.sourcePath,
          destinationWebpPath: webpPath,
        );
      }

      exportedStickers.add(
        s.copyWith(
          webpPath: exportedFile.path,
          emojis: emojis,
        ),
      );

      providerStickersMeta.add(<String, dynamic>{
        'image_file': webpFileName,
        'file_path': exportedFile.path,
        'emojis': emojis,
      });
    }

    final updatedPack = pack.copyWith(
      trayImagePath: trayPath,
      imageDataVersion: newVersion,
      updatedAt: DateTime.now(),
      stickers: exportedStickers,
    );

    await _syncContentProviderRegistry(
      docsDir: docsDir,
      targetPack: updatedPack,
      targetPackStickersMeta: providerStickersMeta,
    );

    try {
      final dynamic response = await _channel.invokeMethod(
        'addPackToWhatsApp',
        <String, dynamic>{
          'identifier': updatedPack.whatsappIdentifier,
          'name': updatedPack.name,
        },
      );

      bool added = false;
      String status = '';
      if (response is Map) {
        added = (response['added'] as bool?) ?? false;
        status = (response['status'] as String?) ?? '';
      }

      return WhatsAppExportResult(
        added: added,
        message: added
            ? '¡Paquete "${updatedPack.name}" agregado a WhatsApp!'
            : (status == 'cancelled_or_already_added'
                ? 'Operación cancelada o el paquete ya estaba agregado.'
                : 'Estado devuelto por WhatsApp: $status'),
        updatedPack: updatedPack,
      );
    } on PlatformException catch (e) {
      throw StickerValidationException(
        'WhatsApp rechazó el paquete (${e.code}): ${e.message}',
      );
    }
  }

  Future<void> _syncContentProviderRegistry({
    required Directory docsDir,
    required StickerPack targetPack,
    required List<Map<String, dynamic>> targetPackStickersMeta,
  }) async {
    final registryFile =
        File('${docsDir.path}/${AppConstants.whatsappRegistryFileName}');

    List<dynamic> existingPacks = <dynamic>[];
    if (await registryFile.exists()) {
      try {
        final decoded = jsonDecode(await registryFile.readAsString())
            as Map<String, dynamic>;
        existingPacks =
            decoded['sticker_packs'] as List<dynamic>? ?? <dynamic>[];
      } catch (_) {
        existingPacks = <dynamic>[];
      }
    }

    final filtered = existingPacks.where((item) {
      final map = item as Map<String, dynamic>;
      final id = map['identifier'] as String? ?? '';
      return !id.startsWith('${targetPack.id}_v');
    }).toList();

    filtered.add(<String, dynamic>{
      'identifier': targetPack.whatsappIdentifier,
      'name': targetPack.name,
      'publisher': targetPack.publisher,
      'tray_image_file': 'tray.png',
      'tray_file_path': targetPack.trayImagePath,
      'image_data_version': targetPack.imageDataVersion.toString(),
      'animated_sticker_pack': targetPack.isAnimatedPack,
      'stickers': targetPackStickersMeta,
    });

    const encoder = JsonEncoder.withIndent('  ');
    await registryFile.writeAsString(
      encoder.convert(<String, dynamic>{'sticker_packs': filtered}),
      flush: true,
    );
  }
}
