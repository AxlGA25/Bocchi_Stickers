import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../services/image_export_service.dart';
import 'models/sticker.dart';
import 'models/sticker_pack.dart';

class PackRepository {
  final Uuid _uuid = const Uuid();
  final ImageExportService _exportService = ImageExportService();

  Future<Directory> _getDocsDir() => getApplicationDocumentsDirectory();

  Future<File> _getPacksJsonFile() async {
    final docs = await _getDocsDir();
    return File('${docs.path}/${AppConstants.packsJsonFileName}');
  }

  Future<Directory> getPackDirectory(String packId) async {
    final docs = await _getDocsDir();
    return Directory('${docs.path}/${AppConstants.packsFolderName}/$packId');
  }

  String _generatePackId() {
    final raw = _uuid.v4().replaceAll('-', '').substring(0, 12);
    return 'pack_$raw';
  }

  String _generateStickerId() {
    final raw = _uuid.v4().replaceAll('-', '').substring(0, 12);
    return 'stk_$raw';
  }

  Future<List<StickerPack>> loadPacks() async {
    final file = await _getPacksJsonFile();
    if (!await file.exists()) {
      return [];
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final list = decoded['packs'] as List<dynamic>? ?? [];
      final packs = list
          .map((item) => StickerPack.fromJson(item as Map<String, dynamic>))
          .toList();

      packs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return packs;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePacks(List<StickerPack> packs) async {
    final file = await _getPacksJsonFile();
    final data = {
      'lastPublisher': packs.isNotEmpty
          ? packs.first.publisher
          : AppConstants.defaultPublisher,
      'packs': packs.map((p) => p.toJson()).toList(),
    };
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(data), flush: true);
  }

  Future<void> updatePack(StickerPack updatedPack) async {
    final packs = await loadPacks();
    final idx = packs.indexWhere((p) => p.id == updatedPack.id);
    if (idx == -1) return;
    packs[idx] = updatedPack;
    await savePacks(packs);
  }

  Future<String> getLastPublisher() async {
    final file = await _getPacksJsonFile();
    if (!await file.exists()) return AppConstants.defaultPublisher;
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final saved = (decoded['lastPublisher'] as String?)?.trim();
      if (saved != null && saved.isNotEmpty) return saved;
    } catch (_) {}
    return AppConstants.defaultPublisher;
  }

  Future<StickerPack> createPack({
    required String name,
    required String publisher,
    bool isAnimatedPack = false,
  }) async {
    final packId = _generatePackId();
    final packDir = await getPackDirectory(packId);
    final stickersDir = Directory('${packDir.path}/stickers');
    await stickersDir.create(recursive: true);

    final now = DateTime.now();
    final newPack = StickerPack(
      id: packId,
      name: name.trim(),
      publisher: publisher.trim(),
      isAnimatedPack: isAnimatedPack,
      createdAt: now,
      updatedAt: now,
    );

    final currentPacks = await loadPacks();
    final updated = [newPack, ...currentPacks];
    await savePacks(updated);
    return newPack;
  }

  Future<void> renamePack({
    required String packId,
    required String newName,
    required String newPublisher,
  }) async {
    final packs = await loadPacks();
    final index = packs.indexWhere((p) => p.id == packId);
    if (index == -1) return;

    final current = packs[index];
    packs[index] = current.copyWith(
      name: newName.trim(),
      publisher: newPublisher.trim(),
      imageDataVersion: current.imageDataVersion + 1,
      updatedAt: DateTime.now(),
    );

    await savePacks(packs);
  }

  Future<StickerPack?> duplicatePack(String sourcePackId) async {
    final packs = await loadPacks();
    final sourceIndex = packs.indexWhere((p) => p.id == sourcePackId);
    if (sourceIndex == -1) return null;

    final sourcePack = packs[sourceIndex];
    final newPackId = _generatePackId();
    final newPackDir = await getPackDirectory(newPackId);
    final newStickersRootDir = Directory('${newPackDir.path}/stickers');
    await newStickersRootDir.create(recursive: true);

    String? newTrayPath;
    if (sourcePack.trayImagePath != null) {
      final oldTray = File(sourcePack.trayImagePath!);
      if (await oldTray.exists()) {
        final targetTray = File('${newPackDir.path}/tray.png');
        await oldTray.copy(targetTray.path);
        newTrayPath = targetTray.path;
      }
    }

    final List<Sticker> copiedStickers = [];
    for (final sticker in sourcePack.stickers) {
      final newStickerId = _generateStickerId();
      final stickerDir = Directory('${newStickersRootDir.path}/$newStickerId');
      await stickerDir.create(recursive: true);

      final newSourcePath = '${stickerDir.path}/source.png';
      final oldSource = File(sticker.sourcePath);
      if (await oldSource.exists()) {
        await oldSource.copy(newSourcePath);
      }

      String? newWebpPath;
      if (sticker.webpPath != null) {
        final oldWebp = File(sticker.webpPath!);
        if (await oldWebp.exists()) {
          newWebpPath = '${stickerDir.path}/export.webp';
          await oldWebp.copy(newWebpPath);
        }
      }

      String? newOriginalPath;
      if (sticker.originalPhotoPath != null) {
        final oldOrig = File(sticker.originalPhotoPath!);
        if (await oldOrig.exists()) {
          newOriginalPath = '${stickerDir.path}/original.jpg';
          await oldOrig.copy(newOriginalPath);
        }
      }

      copiedStickers.add(
        Sticker(
          id: newStickerId,
          sourcePath: newSourcePath,
          webpPath: newWebpPath,
          emojis: List<String>.from(sticker.emojis),
          originalPhotoPath: newOriginalPath,
          isAnimated: sticker.isAnimated,
        ),
      );
    }

    final now = DateTime.now();
    final duplicated = StickerPack(
      id: newPackId,
      name: '${sourcePack.name} (Copia)',
      publisher: sourcePack.publisher,
      trayImagePath: newTrayPath,
      imageDataVersion: 1,
      isAnimatedPack: sourcePack.isAnimatedPack,
      createdAt: now,
      updatedAt: now,
      stickers: copiedStickers,
    );

    final updatedPacks = [duplicated, ...packs];
    await savePacks(updatedPacks);
    return duplicated;
  }

  Future<void> deletePack(String packId) async {
    final packs = await loadPacks();
    final filtered = packs.where((p) => p.id != packId).toList();
    await savePacks(filtered);

    final packDir = await getPackDirectory(packId);
    if (await packDir.exists()) {
      await packDir.delete(recursive: true);
    }
  }

  Future<void> saveSticker({
    required String packId,
    String? existingStickerId,
    required Uint8List png512Bytes,
    String? originalImagePath,
    List<String>? emojis,
  }) async {
    final packs = await loadPacks();
    final packIndex = packs.indexWhere((p) => p.id == packId);
    if (packIndex == -1) return;

    final pack = packs[packIndex];
    if (existingStickerId == null &&
        pack.stickers.length >= AppConstants.maxStickersPerPack) {
      throw Exception('El paquete ya alcanzó el máximo de 30 stickers.');
    }

    final stickerId = existingStickerId ?? _generateStickerId();
    final packDir = await getPackDirectory(packId);
    final stickerDir = Directory('${packDir.path}/stickers/$stickerId');
    await stickerDir.create(recursive: true);

    final sourceFile = File('${stickerDir.path}/source.png');
    await sourceFile.writeAsBytes(png512Bytes, flush: true);

    final webpBytes =
        await _exportService.convertPng512ToValidatedWebp(png512Bytes);
    final webpFile = File('${stickerDir.path}/export.webp');
    await webpFile.writeAsBytes(webpBytes, flush: true);

    String? savedOriginalPath;
    if (originalImagePath != null) {
      final origFile = File(originalImagePath);
      if (await origFile.exists()) {
        final targetOrig = File('${stickerDir.path}/original.jpg');
        if (origFile.path != targetOrig.path) {
          await origFile.copy(targetOrig.path);
        }
        savedOriginalPath = targetOrig.path;
      }
    }

    final currentStickers = List<Sticker>.from(pack.stickers);
    final existingIdx = currentStickers.indexWhere((s) => s.id == stickerId);

    if (existingIdx >= 0) {
      final old = currentStickers[existingIdx];
      currentStickers[existingIdx] = old.copyWith(
        sourcePath: sourceFile.path,
        webpPath: webpFile.path,
        originalPhotoPath: savedOriginalPath ?? old.originalPhotoPath,
        emojis: emojis ?? old.emojis,
      );
    } else {
      currentStickers.add(
        Sticker(
          id: stickerId,
          sourcePath: sourceFile.path,
          webpPath: webpFile.path,
          originalPhotoPath: savedOriginalPath,
          emojis: emojis ?? const ['😀'],
          isAnimated: false,
        ),
      );
    }

    String? trayPath = pack.trayImagePath;
    if (trayPath == null || !await File(trayPath).exists()) {
      final trayBytes =
          await _exportService.createValidatedTrayIcon(png512Bytes);
      final trayFile = File('${packDir.path}/tray.png');
      await trayFile.writeAsBytes(trayBytes, flush: true);
      trayPath = trayFile.path;
    }

    packs[packIndex] = pack.copyWith(
      stickers: currentStickers,
      trayImagePath: trayPath,
      imageDataVersion: pack.imageDataVersion + 1,
      updatedAt: DateTime.now(),
    );

    await savePacks(packs);
  }

  /// Guarda un sticker animado (.webp animado <= 500 KB) y su primer cuadro como miniatura/tray icon
  Future<void> saveAnimatedSticker({
    required String packId,
    required Uint8List animatedWebpBytes,
    required Uint8List firstFramePngBytes,
    required List<String> emojis,
  }) async {
    final packs = await loadPacks();
    final packIndex = packs.indexWhere((p) => p.id == packId);
    if (packIndex == -1) return;

    final pack = packs[packIndex];
    if (pack.stickers.length >= AppConstants.maxStickersPerPack) {
      throw Exception('El paquete ya alcanzó el máximo de 30 stickers.');
    }

    final stickerId = _generateStickerId();
    final packDir = await getPackDirectory(packId);
    final stickerDir = Directory('${packDir.path}/stickers/$stickerId');
    await stickerDir.create(recursive: true);

    // Guardamos el WebP animado tanto en export.webp como en source.png (Flutter Image.file anima WebP directamente)
    final webpFile = File('${stickerDir.path}/export.webp');
    await webpFile.writeAsBytes(animatedWebpBytes, flush: true);

    final previewFile = File('${stickerDir.path}/source.png');
    await previewFile.writeAsBytes(animatedWebpBytes, flush: true);

    String? trayPath = pack.trayImagePath;
    if (trayPath == null || !await File(trayPath).exists()) {
      final trayBytes =
          await _exportService.createValidatedTrayIcon(firstFramePngBytes);
      final trayFile = File('${packDir.path}/tray.png');
      await trayFile.writeAsBytes(trayBytes, flush: true);
      trayPath = trayFile.path;
    }

    final currentStickers = List<Sticker>.from(pack.stickers)
      ..add(
        Sticker(
          id: stickerId,
          sourcePath: previewFile.path,
          webpPath: webpFile.path,
          emojis: emojis,
          isAnimated: true,
        ),
      );

    packs[packIndex] = pack.copyWith(
      stickers: currentStickers,
      trayImagePath: trayPath,
      isAnimatedPack: true,
      imageDataVersion: pack.imageDataVersion + 1,
      updatedAt: DateTime.now(),
    );

    await savePacks(packs);
  }

  Future<void> updateStickerEmojis({
    required String packId,
    required String stickerId,
    required List<String> emojis,
  }) async {
    final packs = await loadPacks();
    final packIndex = packs.indexWhere((p) => p.id == packId);
    if (packIndex == -1) return;

    final pack = packs[packIndex];
    final stickers = List<Sticker>.from(pack.stickers);
    final idx = stickers.indexWhere((s) => s.id == stickerId);
    if (idx == -1) return;

    stickers[idx] = stickers[idx].copyWith(emojis: emojis);
    packs[packIndex] = pack.copyWith(
      stickers: stickers,
      imageDataVersion: pack.imageDataVersion + 1,
      updatedAt: DateTime.now(),
    );

    await savePacks(packs);
  }

  Future<void> reorderStickers({
    required String packId,
    required int oldIndex,
    required int newIndex,
  }) async {
    final packs = await loadPacks();
    final packIndex = packs.indexWhere((p) => p.id == packId);
    if (packIndex == -1) return;

    final pack = packs[packIndex];
    final stickers = List<Sticker>.from(pack.stickers);
    if (oldIndex < 0 ||
        oldIndex >= stickers.length ||
        newIndex < 0 ||
        newIndex >= stickers.length) {
      return;
    }

    final item = stickers.removeAt(oldIndex);
    stickers.insert(newIndex, item);

    packs[packIndex] = pack.copyWith(
      stickers: stickers,
      imageDataVersion: pack.imageDataVersion + 1,
      updatedAt: DateTime.now(),
    );

    await savePacks(packs);
  }

  Future<void> setTrayIconFromSticker({
    required String packId,
    required String stickerId,
  }) async {
    final packs = await loadPacks();
    final packIndex = packs.indexWhere((p) => p.id == packId);
    if (packIndex == -1) return;

    final pack = packs[packIndex];
    final sticker = pack.stickers.where((s) => s.id == stickerId).firstOrNull;
    if (sticker == null) return;

    final sourceFile = File(sticker.sourcePath);
    if (!await sourceFile.exists()) return;

    final pngBytes = await sourceFile.readAsBytes();
    final trayBytes = await _exportService.createValidatedTrayIcon(pngBytes);
    final packDir = await getPackDirectory(packId);
    final trayFile = File('${packDir.path}/tray.png');
    await trayFile.writeAsBytes(trayBytes, flush: true);

    packs[packIndex] = pack.copyWith(
      trayImagePath: trayFile.path,
      imageDataVersion: pack.imageDataVersion + 1,
      updatedAt: DateTime.now(),
    );

    await savePacks(packs);
  }

  Future<void> deleteSticker({
    required String packId,
    required String stickerId,
  }) async {
    final packs = await loadPacks();
    final packIndex = packs.indexWhere((p) => p.id == packId);
    if (packIndex == -1) return;

    final pack = packs[packIndex];
    final updatedStickers =
        pack.stickers.where((s) => s.id != stickerId).toList();

    final packDir = await getPackDirectory(packId);
    final stickerDir = Directory('${packDir.path}/stickers/$stickerId');
    if (await stickerDir.exists()) {
      await stickerDir.delete(recursive: true);
    }

    packs[packIndex] = pack.copyWith(
      stickers: updatedStickers,
      imageDataVersion: pack.imageDataVersion + 1,
      updatedAt: DateTime.now(),
    );

    await savePacks(packs);
  }
}
