import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../core/constants.dart';
import 'image_export_service.dart';

class AnimatedStickerResult {
  final Uint8List animatedWebpBytes;
  final Uint8List firstFramePngBytes;
  final int frameCount;

  const AnimatedStickerResult({
    required this.animatedWebpBytes,
    required this.firstFramePngBytes,
    required this.frameCount,
  });
}

class AnimatedStickerService {
  static const MethodChannel _channel =
      MethodChannel('com.axel.sticker_maker/whatsapp');

  /// Obtiene la duración total de un video en milisegundos
  Future<int> getVideoDurationMs(String videoPath) async {
    final duration = await _channel.invokeMethod<int>(
      'getVideoDurationMs',
      {'videoPath': videoPath},
    );
    return duration ?? 3000;
  }

  /// Extrae los fotogramas PNG de 512x512 del rango [startMs]..[endMs] de un video
  Future<List<Uint8List>> extractVideoFrames({
    required String videoPath,
    required int startMs,
    required int endMs,
    int fps = 10,
  }) async {
    final rawList = await _channel.invokeMethod<List<Object?>>(
      'extractVideoFrames',
      {
        'videoPath': videoPath,
        'startMs': startMs,
        'endMs': endMs,
        'fps': fps,
        'targetSize': AppConstants.stickerSizePx,
      },
    );

    if (rawList == null || rawList.isEmpty) {
      throw const StickerValidationException(
        'No se pudieron extraer fotogramas del video seleccionado.',
      );
    }

    return rawList.whereType<Uint8List>().toList();
  }

  /// Extrae los fotogramas de un archivo GIF animando y encuadrando cada uno a 512x512 px
  Future<(List<Uint8List> frames, int avgFrameDurationMs)> extractGifFrames(
    String gifPath,
  ) async {
    final bytes = await File(gifPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final totalFrames = codec.frameCount;

    if (totalFrames <= 1) {
      throw const StickerValidationException(
        'El archivo elegido no tiene múltiples cuadros animados.',
      );
    }

    // Limitar a máximo 35 cuadros para cuidar el límite de 500 KB de WhatsApp
    final step = (totalFrames / 30).ceil().clamp(1, 10);
    final List<Uint8List> pngFrames = [];
    int totalDurationMs = 0;

    for (int i = 0; i < totalFrames; i += step) {
      final frameInfo = await codec.getNextFrame();
      final durationMs = frameInfo.duration.inMilliseconds.clamp(40, 500);
      totalDurationMs += durationMs * step;

      final png512 = await _renderUiImageTo512Png(frameInfo.image);
      pngFrames.add(png512);
    }

    final avgDuration =
        (totalDurationMs / pngFrames.length).round().clamp(60, 250);
    return (pngFrames, avgDuration);
  }

  Future<Uint8List> _renderUiImageTo512Png(ui.Image src) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      const ui.Rect.fromLTWH(0, 0, 512, 512),
    );

    const margin = 16.0;
    const safeSize = 512.0 - (margin * 2);
    final maxSide =
        src.width > src.height ? src.width.toDouble() : src.height.toDouble();
    final scale = safeSize / maxSide;

    canvas.translate(256.0, 256.0);
    canvas.scale(scale, scale);
    canvas.drawImage(
      src,
      ui.Offset(-src.width / 2, -src.height / 2),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(512, 512);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Convierte una lista de fotogramas PNG 512x512 en un archivo WebP Animado (<= 500 KB)
  /// reduciendo automáticamente calidad y cantidad de cuadros si supera los 500 KB.
  Future<AnimatedStickerResult> buildAnimatedWebpFromPngFrames({
    required List<Uint8List> pngFrames,
    required int frameDurationMs,
  }) async {
    if (pngFrames.isEmpty) {
      throw const StickerValidationException('Lista de fotogramas vacía.');
    }

    List<Uint8List> workingFrames = List<Uint8List>.from(pngFrames);
    int currentDurationMs = frameDurationMs.clamp(60, 300);

    // Probar distintos niveles de calidad (de 75 hacia 25) para entrar debajo de 500 KB
    for (int quality in [75, 60, 45, 32, 22]) {
      final singleWebps = <Uint8List>[];
      for (final png in workingFrames) {
        final webp = await _channel.invokeMethod<Uint8List>(
          'encodePngToWebp',
          {
            'pngBytes': png,
            'quality': quality,
          },
        );
        if (webp != null) {
          singleWebps.add(webp);
        }
      }

      final muxed = _muxWebpFramesIntoAnimatedWebp(
        singleFrameWebps: singleWebps,
        width: AppConstants.stickerSizePx,
        height: AppConstants.stickerSizePx,
        frameDurationMs: currentDurationMs,
      );

      if (muxed.length <= AppConstants.maxAnimatedStickerFileSizeBytes) {
        return AnimatedStickerResult(
          animatedWebpBytes: muxed,
          firstFramePngBytes: workingFrames.first,
          frameCount: workingFrames.length,
        );
      }

      // Si aún pesa > 500 KB y tenemos muchos cuadros, reducir cuadros a la mitad duplicando duración
      if (workingFrames.length > 10 && quality <= 45) {
        final reduced = <Uint8List>[];
        for (int i = 0; i < workingFrames.length; i += 2) {
          reduced.add(workingFrames[i]);
        }
        workingFrames = reduced;
        currentDurationMs = (currentDurationMs * 2).clamp(80, 400);
      }
    }

    throw const StickerValidationException(
      'El video es demasiado complejo y supera los 500 KB. Intenta recortar un fragmento más corto (1.5 a 2.5 seg).',
    );
  }

  /// Ensambla múltiples archivos WebP estáticos en un contenedor RIFF WEBP Animado (VP8X + ANIM + ANMF)
  /// siguiendo la especificación oficial de Google WebP Container.
  Uint8List _muxWebpFramesIntoAnimatedWebp({
    required List<Uint8List> singleFrameWebps,
    required int width,
    required int height,
    required int frameDurationMs,
  }) {
    final chunksBuilder = BytesBuilder(copy: false);

    // 1. Chunk VP8X (Extended WebP Header: 10 bytes payload)
    // Flags: bit 1 (Animation = 0x02) | bit 4 (Alpha = 0x10) => 0x12
    final vp8xPayload = ByteData(10);
    vp8xPayload.setUint8(0, 0x12);
    // Canvas Width - 1 (24 bits little-endian en bytes 4..6)
    final wMinus1 = width - 1;
    vp8xPayload.setUint8(4, wMinus1 & 0xFF);
    vp8xPayload.setUint8(5, (wMinus1 >> 8) & 0xFF);
    vp8xPayload.setUint8(6, (wMinus1 >> 16) & 0xFF);
    // Canvas Height - 1 (24 bits little-endian en bytes 7..9)
    final hMinus1 = height - 1;
    vp8xPayload.setUint8(7, hMinus1 & 0xFF);
    vp8xPayload.setUint8(8, (hMinus1 >> 8) & 0xFF);
    vp8xPayload.setUint8(9, (hMinus1 >> 16) & 0xFF);
    _writeChunk(chunksBuilder, 'VP8X', vp8xPayload.buffer.asUint8List());

    // 2. Chunk ANIM (Global Animation Header: 6 bytes payload -> BG color RGBA=0, LoopCount=0 infinito)
    final animPayload = Uint8List(6);
    _writeChunk(chunksBuilder, 'ANIM', animPayload);

    // 3. un Chunk ANMF por cada fotograma
    for (final webp in singleFrameWebps) {
      final frameBitstream = _extractFrameSubchunks(webp);
      final anmfHeader = ByteData(16);

      // Frame X = 0 (bytes 0..2), Frame Y = 0 (bytes 3..5)
      // Frame Width - 1 (bytes 6..8)
      anmfHeader.setUint8(6, wMinus1 & 0xFF);
      anmfHeader.setUint8(7, (wMinus1 >> 8) & 0xFF);
      anmfHeader.setUint8(8, (wMinus1 >> 16) & 0xFF);
      // Frame Height - 1 (bytes 9..11)
      anmfHeader.setUint8(9, hMinus1 & 0xFF);
      anmfHeader.setUint8(10, (hMinus1 >> 8) & 0xFF);
      anmfHeader.setUint8(11, (hMinus1 >> 16) & 0xFF);
      // Duration en ms (bytes 12..14)
      final dur = frameDurationMs.clamp(40, 1000);
      anmfHeader.setUint8(12, dur & 0xFF);
      anmfHeader.setUint8(13, (dur >> 8) & 0xFF);
      anmfHeader.setUint8(14, (dur >> 16) & 0xFF);
      // Flags (byte 15): bit 1 = Blending (Do not blend = 1 -> 0x02), bit 0 = Disposal (Dispose to background = 1 -> 0x01) => 0x03
      anmfHeader.setUint8(15, 0x03);

      final anmfPayload = BytesBuilder(copy: false)
        ..add(anmfHeader.buffer.asUint8List())
        ..add(frameBitstream);

      _writeChunk(chunksBuilder, 'ANMF', anmfPayload.toBytes());
    }

    final bodyBytes = chunksBuilder.toBytes();
    final riffHeader = ByteData(12);
    // 'RIFF'
    riffHeader.setUint8(0, 0x52);
    riffHeader.setUint8(1, 0x49);
    riffHeader.setUint8(2, 0x46);
    riffHeader.setUint8(3, 0x46);
    // File size - 8
    riffHeader.setUint32(4, bodyBytes.length + 4, Endian.little);
    // 'WEBP'
    riffHeader.setUint8(8, 0x57);
    riffHeader.setUint8(9, 0x45);
    riffHeader.setUint8(10, 0x42);
    riffHeader.setUint8(11, 0x50);

    final out = BytesBuilder(copy: false)
      ..add(riffHeader.buffer.asUint8List())
      ..add(bodyBytes);
    return out.toBytes();
  }

  /// Extrae los sub-chunks de imagen (ALPH, VP8 , VP8L) de un archivo WebP individual
  Uint8List _extractFrameSubchunks(Uint8List singleWebp) {
    final out = BytesBuilder(copy: false);
    int offset = 12; // Saltar cabecera RIFF....WEBP

    while (offset + 8 <= singleWebp.length) {
      final fourCC =
          String.fromCharCodes(singleWebp.sublist(offset, offset + 4));
      final bd = ByteData.sublistView(singleWebp, offset + 4, offset + 8);
      final chunkSize = bd.getUint32(0, Endian.little);
      final paddedSize = chunkSize + (chunkSize.isOdd ? 1 : 0);

      if (offset + 8 + paddedSize > singleWebp.length) break;

      if (fourCC == 'ALPH' || fourCC == 'VP8 ' || fourCC == 'VP8L') {
        out.add(singleWebp.sublist(offset, offset + 8 + paddedSize));
      }

      offset += 8 + paddedSize;
    }

    return out.toBytes();
  }

  void _writeChunk(BytesBuilder builder, String fourCC, Uint8List payload) {
    final header = ByteData(8);
    for (int i = 0; i < 4; i++) {
      header.setUint8(i, fourCC.codeUnitAt(i));
    }
    header.setUint32(4, payload.length, Endian.little);
    builder.add(header.buffer.asUint8List());
    builder.add(payload);
    if (payload.length.isOdd) {
      builder.addByte(0); // Padding byte par requerido por RIFF
    }
  }
}
