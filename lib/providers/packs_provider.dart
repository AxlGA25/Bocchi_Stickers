import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/sticker_pack.dart';
import '../data/pack_repository.dart';
import '../services/backup_service.dart';
import '../services/image_export_service.dart';
import '../services/whatsapp_service.dart';

final packRepositoryProvider = Provider<PackRepository>((ref) {
  return PackRepository();
});

final imageExportServiceProvider = Provider<ImageExportService>((ref) {
  return ImageExportService();
});

final whatsAppServiceProvider = Provider<WhatsAppService>((ref) {
  return WhatsAppService(ref.read(imageExportServiceProvider));
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService();
});

final packsProvider =
    AsyncNotifierProvider<PacksNotifier, List<StickerPack>>(PacksNotifier.new);

class PacksNotifier extends AsyncNotifier<List<StickerPack>> {
  PackRepository get _repo => ref.read(packRepositoryProvider);

  @override
  Future<List<StickerPack>> build() async {
    return _repo.loadPacks();
  }

  Future<void> reloadPacks() async {
    state = const AsyncLoading();
    state = AsyncData(await _repo.loadPacks());
  }

  Future<StickerPack> createPack({
    required String name,
    required String publisher,
    bool isAnimatedPack = false,
  }) async {
    final created = await _repo.createPack(
      name: name,
      publisher: publisher,
      isAnimatedPack: isAnimatedPack,
    );
    state = AsyncData(await _repo.loadPacks());
    return created;
  }

  Future<void> renamePack({
    required String packId,
    required String newName,
    required String newPublisher,
  }) async {
    await _repo.renamePack(
      packId: packId,
      newName: newName,
      newPublisher: newPublisher,
    );
    state = AsyncData(await _repo.loadPacks());
  }

  Future<void> duplicatePack(String packId) async {
    await _repo.duplicatePack(packId);
    state = AsyncData(await _repo.loadPacks());
  }

  Future<void> deletePack(String packId) async {
    await _repo.deletePack(packId);
    state = AsyncData(await _repo.loadPacks());
  }

  Future<void> saveSticker({
    required String packId,
    String? existingStickerId,
    required Uint8List png512Bytes,
    String? originalImagePath,
    List<String>? emojis,
  }) async {
    await _repo.saveSticker(
      packId: packId,
      existingStickerId: existingStickerId,
      png512Bytes: png512Bytes,
      originalImagePath: originalImagePath,
      emojis: emojis,
    );
    state = AsyncData(await _repo.loadPacks());
  }

  Future<void> saveAnimatedSticker({
    required String packId,
    required Uint8List animatedWebpBytes,
    required Uint8List firstFramePngBytes,
    required List<String> emojis,
  }) async {
    await _repo.saveAnimatedSticker(
      packId: packId,
      animatedWebpBytes: animatedWebpBytes,
      firstFramePngBytes: firstFramePngBytes,
      emojis: emojis,
    );
    state = AsyncData(await _repo.loadPacks());
  }

  Future<void> updateStickerEmojis({
    required String packId,
    required String stickerId,
    required List<String> emojis,
  }) async {
    await _repo.updateStickerEmojis(
      packId: packId,
      stickerId: stickerId,
      emojis: emojis,
    );
    state = AsyncData(await _repo.loadPacks());
  }

  Future<void> reorderStickers({
    required String packId,
    required int oldIndex,
    required int newIndex,
  }) async {
    await _repo.reorderStickers(
      packId: packId,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    state = AsyncData(await _repo.loadPacks());
  }

  Future<void> setTrayIconFromSticker({
    required String packId,
    required String stickerId,
  }) async {
    await _repo.setTrayIconFromSticker(
      packId: packId,
      stickerId: stickerId,
    );
    state = AsyncData(await _repo.loadPacks());
  }

  Future<void> deleteSticker({
    required String packId,
    required String stickerId,
  }) async {
    await _repo.deleteSticker(packId: packId, stickerId: stickerId);
    state = AsyncData(await _repo.loadPacks());
  }

  Future<String> exportAndSendToWhatsApp(StickerPack pack) async {
    final currentPacks = state.valueOrNull ?? await _repo.loadPacks();
    final waService = ref.read(whatsAppServiceProvider);
    final result = await waService.exportAndSendPackToWhatsApp(
      pack: pack,
      allPacks: currentPacks,
    );

    await _repo.updatePack(result.updatedPack);
    state = AsyncData(await _repo.loadPacks());
    return result.message;
  }
}
