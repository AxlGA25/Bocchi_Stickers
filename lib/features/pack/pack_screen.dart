import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../data/models/sticker.dart';
import '../../data/models/sticker_pack.dart';
import '../../providers/packs_provider.dart';
import '../editor/animated_editor_screen.dart';
import '../editor/editor_screen.dart';
import 'emoji_picker_sheet.dart';
import 'sticker_tile.dart';

class PackScreen extends ConsumerStatefulWidget {
  final String packId;

  const PackScreen({super.key, required this.packId});

  @override
  ConsumerState<PackScreen> createState() => _PackScreenState();
}

class _PackScreenState extends ConsumerState<PackScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isExportingToWhatsApp = false;

  Future<void> _pickAndEditNewSticker(StickerPack pack) async {
    if (pack.stickers.length >= AppConstants.maxStickersPerPack) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este paquete ya tiene el máximo de 30 stickers.'),
        ),
      );
      return;
    }

    if (pack.isAnimatedPack) {
      await _showAnimatedSourceSheet(pack);
      return;
    }

    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditorScreen(
          packId: pack.id,
          imagePath: picked.path,
          originalPhotoPath: picked.path,
        ),
      ),
    );
  }

  Future<void> _showAnimatedSourceSheet(StickerPack pack) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Nuevo Sticker Animado',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Elige el origen de tu animación'),
              ),
              ListTile(
                leading: const Icon(Icons.video_library_rounded),
                title: const Text('Elegir Video de la galería (.mp4)'),
                subtitle: const Text('Recorta hasta 4 segundos en movimiento'),
                onTap: () => Navigator.of(sheetCtx).pop('video'),
              ),
              ListTile(
                leading: const Icon(Icons.gif_box_outlined),
                title: const Text('Elegir archivo GIF animado (.gif)'),
                onTap: () => Navigator.of(sheetCtx).pop('gif'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (choice == null || !mounted) return;

    if (choice == 'video') {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null || !mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => AnimatedEditorScreen(
            packId: pack.id,
            mediaPath: video.path,
            isGif: false,
          ),
        ),
      );
    } else if (choice == 'gif') {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gif', 'webp'],
      );
      final path = res?.files.firstOrNull?.path;
      if (path == null || !mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => AnimatedEditorScreen(
            packId: pack.id,
            mediaPath: path,
            isGif: true,
          ),
        ),
      );
    }
  }

  Future<void> _editExistingSticker(StickerPack pack, Sticker sticker) async {
    if (sticker.isAnimated) {
      final newEmojis = await EmojiPickerSheet.show(
        context,
        initialEmojis: sticker.emojis,
      );
      if (newEmojis != null && newEmojis.isNotEmpty) {
        await ref.read(packsProvider.notifier).updateStickerEmojis(
              packId: pack.id,
              stickerId: sticker.id,
              emojis: newEmojis,
            );
      }
      return;
    }

    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditorScreen(
          packId: pack.id,
          imagePath: sticker.sourcePath,
          existingStickerId: sticker.id,
          originalPhotoPath: sticker.originalPhotoPath,
          initialEmojis: sticker.emojis,
        ),
      ),
    );
  }

  Future<void> _sendPackToWhatsApp(StickerPack pack) async {
    if (_isExportingToWhatsApp) return;

    setState(() => _isExportingToWhatsApp = true);
    try {
      final message =
          await ref.read(packsProvider.notifier).exportAndSendToWhatsApp(pack);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text(
              '$e',
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingToWhatsApp = false);
      }
    }
  }

  void _showStickerOptions(
    StickerPack pack,
    Sticker sticker,
    int stickerIndex,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!sticker.isAnimated)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Editar recorte / fondo en el lienzo'),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _editExistingSticker(pack, sticker);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.emoji_emotions_outlined),
                  title: Text('Cambiar emojis (${sticker.emojis.join(' ')})'),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    final newEmojis = await EmojiPickerSheet.show(
                      context,
                      initialEmojis: sticker.emojis,
                    );
                    if (newEmojis != null && newEmojis.isNotEmpty) {
                      await ref
                          .read(packsProvider.notifier)
                          .updateStickerEmojis(
                            packId: pack.id,
                            stickerId: sticker.id,
                            emojis: newEmojis,
                          );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_size_select_large_rounded),
                  title: const Text('Usar como ícono del paquete (Tray Icon)'),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    await ref
                        .read(packsProvider.notifier)
                        .setTrayIconFromSticker(
                          packId: pack.id,
                          stickerId: sticker.id,
                        );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ícono del paquete actualizado.'),
                        ),
                      );
                    }
                  },
                ),
                if (stickerIndex > 0)
                  ListTile(
                    leading: const Icon(Icons.arrow_back_rounded),
                    title: const Text('Mover una posición antes'),
                    onTap: () async {
                      Navigator.of(sheetCtx).pop();
                      await ref.read(packsProvider.notifier).reorderStickers(
                            packId: pack.id,
                            oldIndex: stickerIndex,
                            newIndex: stickerIndex - 1,
                          );
                    },
                  ),
                if (stickerIndex < pack.stickers.length - 1)
                  ListTile(
                    leading: const Icon(Icons.arrow_forward_rounded),
                    title: const Text('Mover una posición después'),
                    onTap: () async {
                      Navigator.of(sheetCtx).pop();
                      await ref.read(packsProvider.notifier).reorderStickers(
                            packId: pack.id,
                            oldIndex: stickerIndex,
                            newIndex: stickerIndex + 1,
                          );
                    },
                  ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Eliminar sticker',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    await ref.read(packsProvider.notifier).deleteSticker(
                          packId: pack.id,
                          stickerId: sticker.id,
                        );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final packsAsync = ref.watch(packsProvider);

    return packsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $err')),
      ),
      data: (packs) {
        final pack = packs.where((p) => p.id == widget.packId).firstOrNull;
        if (pack == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('El paquete ya no existe.')),
          );
        }

        final count = pack.stickers.length;
        final missingForMin = AppConstants.minStickersPerPack - count;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(pack.name)),
                    if (pack.isAnimatedPack) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.movie_filter_rounded, size: 18),
                    ],
                  ],
                ),
                Text(
                  '${pack.isAnimatedPack ? "Animado" : "Estático"} • Por ${pack.publisher} • $count/${AppConstants.maxStickersPerPack}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              if (missingForMin > 0)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          missingForMin == 1
                              ? 'Agrega 1 sticker más para poder enviarlo a WhatsApp (mínimo 3).'
                              : 'Agrega $missingForMin stickers más para poder enviarlo a WhatsApp (mínimo 3).',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: pack.stickers.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _AddStickerCell(
                        isAnimated: pack.isAnimatedPack,
                        onTap: () => _pickAndEditNewSticker(pack),
                      );
                    }

                    final stickerIdx = index - 1;
                    final sticker = pack.stickers[stickerIdx];
                    return StickerTile(
                      sticker: sticker,
                      onTap: () => _editExistingSticker(pack, sticker),
                      onLongPress: () =>
                          _showStickerOptions(pack, sticker, stickerIdx),
                    );
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: pack.isReady && !_isExportingToWhatsApp
                    ? () => _sendPackToWhatsApp(pack)
                    : null,
                icon: _isExportingToWhatsApp
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_to_mobile_rounded),
                label: Text(
                  _isExportingToWhatsApp
                      ? 'Validando y enviando a WhatsApp...'
                      : (pack.isReady
                          ? 'Agregar a WhatsApp ($count stickers)'
                          : 'Agregar a WhatsApp (mínimo 3 stickers)'),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AddStickerCell extends StatelessWidget {
  final bool isAnimated;
  final VoidCallback onTap;

  const _AddStickerCell({
    required this.isAnimated,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.primary.withValues(alpha: 0.6),
          width: 1.8,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAnimated
                  ? Icons.video_call_rounded
                  : Icons.add_photo_alternate_outlined,
              size: 36,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 6),
            Text(
              isAnimated ? '+ Agregar\nVideo / GIF' : '+ Agregar\nsticker',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
