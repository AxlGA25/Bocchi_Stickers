import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../core/constants.dart';

class StickerValidationException implements Exception {
  final String message;
  const StickerValidationException(this.message);

  @override
  String toString() => message;
}

class ImageExportService {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.axel.sticker_maker/whatsapp');

  /// Verifica que los bytes tengan la cabecera RIFF....WEBP
  static bool hasValidWebpHeader(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final riff = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
    final webp = ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
    return riff == 'RIFF' && webp == 'WEBP';
  }

  /// Convierte un PNG de 512x512 a WebP <= 100 KB cumpliendo todas las reglas de WhatsApp
  Future<Uint8List> convertPng512ToValidatedWebp(Uint8List pngBytes) async {
    int quality = 90;

    while (quality >= 20) {
      Uint8List? webpBytes;

      // 1. Intentar con nuestro codificador nativo Android o FlutterImageCompress
      try {
        webpBytes = await _nativeChannel.invokeMethod<Uint8List>(
          'encodePngToWebp',
          {
            'pngBytes': pngBytes,
            'quality': quality,
          },
        );
      } catch (_) {
        webpBytes = await FlutterImageCompress.compressWithList(
          pngBytes,
          minWidth: AppConstants.stickerSizePx,
          minHeight: AppConstants.stickerSizePx,
          quality: quality,
          format: CompressFormat.webp,
          keepExif: false,
        );
      }

      if (webpBytes != null &&
          webpBytes.isNotEmpty &&
          webpBytes.length <= AppConstants.maxStickerFileSizeBytes) {
        await validateWebpStickerBytes(webpBytes);
        return webpBytes;
      }

      quality -= 10;
    }

    throw const StickerValidationException(
      'No se pudo comprimir el sticker bajo 100 KB ni siquiera a calidad 20.',
    );
  }

  /// Valida las 4 reglas técnicas de un archivo WebP para WhatsApp:
  /// 1) Cabecera RIFF/WEBP, 2) Peso <= 100 KB, 3) 512x512 px exactos, 4) Esquina transparente (canal alfa)
  Future<void> validateWebpStickerBytes(Uint8List webpBytes) async {
    if (!hasValidWebpHeader(webpBytes)) {
      throw const StickerValidationException(
        'El archivo generado no tiene una cabecera RIFF/WEBP válida.',
      );
    }

    if (webpBytes.length > AppConstants.maxStickerFileSizeBytes) {
      final kb = (webpBytes.length / 1024).toStringAsFixed(1);
      throw StickerValidationException(
        'El sticker pesa $kb KB (máximo permitido: 100 KB).',
      );
    }

    final codec = await ui.instantiateImageCodec(webpBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    if (image.width != AppConstants.stickerSizePx ||
        image.height != AppConstants.stickerSizePx) {
      throw StickerValidationException(
        'Dimensiones inválidas: ${image.width}x${image.height} (debe ser 512x512 px).',
      );
    }

    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba != null && rgba.lengthInBytes >= 4) {
      // El píxel (0,0) está dentro del margen obligatorio de 16px, por lo que su byte Alpha (índice 3) debe ser 0
      final cornerAlpha = rgba.getUint8(3);
      if (cornerAlpha != 0) {
        throw const StickerValidationException(
          'El sticker perdió la transparencia en el margen exterior.',
        );
      }
    }
  }

  /// Genera y valida el Tray Icon de 96x96 px (<= 50 KB) a partir de un PNG de 512x512
  Future<Uint8List> createValidatedTrayIcon(Uint8List sourcePngBytes) async {
    final codec = await ui.instantiateImageCodec(
      sourcePngBytes,
      targetWidth: AppConstants.trayIconSizePx,
      targetHeight: AppConstants.trayIconSizePx,
    );
    final frame = await codec.getNextFrame();
    final pngData = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final trayPngBytes = pngData!.buffer.asUint8List();

    if (trayPngBytes.length <= AppConstants.maxTrayFileSizeBytes) {
      return trayPngBytes;
    }

    // Si el PNG de 96x96 supera 50 KB, comprimir a WebP
    int quality = 90;
    while (quality >= 20) {
      final compressed = await FlutterImageCompress.compressWithList(
        trayPngBytes,
        minWidth: AppConstants.trayIconSizePx,
        minHeight: AppConstants.trayIconSizePx,
        quality: quality,
        format: CompressFormat.webp,
      );
      if (compressed.length <= AppConstants.maxTrayFileSizeBytes) {
        return compressed;
      }
      quality -= 10;
    }

    throw const StickerValidationException(
      'El ícono del paquete (Tray Icon) supera los 50 KB.',
    );
  }

  /// Exporta un archivo `source.png` a `export.webp` en la misma carpeta del sticker
  Future<File> exportStickerFile({
    required String sourcePngPath,
    required String destinationWebpPath,
  }) async {
    final sourceFile = File(sourcePngPath);
    if (!await sourceFile.exists()) {
      throw StickerValidationException(
        'No se encontró el archivo fuente: $sourcePngPath',
      );
    }

    final pngBytes = await sourceFile.readAsBytes();
    final webpBytes = await convertPng512ToValidatedWebp(pngBytes);
    final outFile = File(destinationWebpPath);
    await outFile.writeAsBytes(webpBytes, flush: true);
    return outFile;
  }
}
