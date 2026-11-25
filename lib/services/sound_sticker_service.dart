import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class SoundStickerService {
  static const MethodChannel _channel =
      MethodChannel('com.axel.sticker_maker/whatsapp');

  Future<int> getVideoDurationMs(String videoPath) async {
    final duration = await _channel.invokeMethod<int>(
      'getVideoDurationMs',
      <String, dynamic>{'videoPath': videoPath},
    );
    return duration ?? 5000;
  }

  Future<Uint8List?> extractSingleVideoFrame(
      String videoPath, int timeMs) async {
    return _channel.invokeMethod<Uint8List>(
      'extractSingleVideoFrame',
      <String, dynamic>{
        'videoPath': videoPath,
        'timeMs': timeMs,
      },
    );
  }

  /// Descarga un audio desde un link directo (.mp3) o una página de Myinstants
  Future<String> downloadAudioFromUrl(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      throw Exception('Pega un enlace válido de Myinstants o un .mp3.');
    }

    String audioUrl = trimmed;

    if (trimmed.contains('myinstants.com') && !trimmed.endsWith('.mp3')) {
      final html = await _fetchText(trimmed);
      final match =
          RegExp(r'''(/media/sounds/[^'"\s]+\.mp3)''').firstMatch(html);
      if (match == null) {
        throw Exception(
          'No se encontró el archivo de audio dentro de ese enlace de Myinstants.',
        );
      }
      audioUrl = 'https://www.myinstants.com${match.group(1)}';
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(audioUrl));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception(
            'Error al descargar audio (HTTP ${response.statusCode}).');
      }

      final bytes = await response.fold<List<int>>(
        <int>[],
        (prev, chunk) => prev..addAll(chunk),
      );

      final tempDir = await getTemporaryDirectory();
      final audioFile = File(
        '${tempDir.path}/sound_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await audioFile.writeAsBytes(bytes, flush: true);
      return audioFile.path;
    } finally {
      client.close();
    }
  }

  Future<String> _fetchText(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception(
            'No se pudo abrir la página (HTTP ${response.statusCode}).');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  /// Combina una imagen o video con sonido en un .mp4 HD de 512x512 guardado en la galería
  Future<String> createSoundStickerMp4({
    required String mediaPath,
    required bool isVideo,
    String? audioPath,
    int startMs = 0,
    int maxDurationMs = 5000,
    String cropAlign = 'center',
  }) async {
    final savedPath = await _channel.invokeMethod<String>(
      'createSoundStickerMp4',
      <String, dynamic>{
        'mediaPath': mediaPath,
        'isVideo': isVideo,
        'audioPath': audioPath,
        'startMs': startMs,
        'maxDurationMs': maxDurationMs,
        'cropAlign': cropAlign,
      },
    );

    if (savedPath == null || savedPath.isEmpty) {
      throw Exception('No se pudo generar el video MP4.');
    }
    return savedPath;
  }
}
