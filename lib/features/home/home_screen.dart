import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/models/sticker_pack.dart';
import '../../providers/packs_provider.dart';
import '../../providers/theme_provider.dart';
import '../pack/pack_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _showCreateOrRenameDialog(
    BuildContext context,
    WidgetRef ref, {
    StickerPack? existingPack,
  }) async {
    final repo = ref.read(packRepositoryProvider);
    final defaultPublisher =
        existingPack?.publisher ?? await repo.getLastPublisher();

    if (!context.mounted) return;

    final nameController =
        TextEditingController(text: existingPack?.name ?? '');
    final publisherController = TextEditingController(text: defaultPublisher);
    final formKey = GlobalKey<FormState>();
    bool isAnimatedPack = existingPack?.isAnimatedPack ?? false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                existingPack == null ? 'Nuevo paquete' : 'Editar paquete',
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        autofocus: true,
                        maxLength: AppConstants.maxNameLength,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del paquete',
                          hintText: 'Ej. Kessoku Reactions',
                          prefixIcon: Icon(Icons.folder_special_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Escribe un nombre para el paquete';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: publisherController,
                        maxLength: AppConstants.maxNameLength,
                        decoration: const InputDecoration(
                          labelText: 'Autor / Publisher',
                          hintText: 'Ej. Axel Guerrero',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'El autor es obligatorio para WhatsApp';
                          }
                          return null;
                        },
                      ),
                      if (existingPack == null) ...[
                        const SizedBox(height: 14),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Paquete Animado (Video / GIF)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: const Text(
                            'Usa clips MP4 o GIFs en movimiento',
                            style: TextStyle(fontSize: 12),
                          ),
                          secondary: const Icon(Icons.movie_filter_rounded),
                          value: isAnimatedPack,
                          onChanged: (val) =>
                              setDialogState(() => isAnimatedPack = val),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  },
                  child: Text(existingPack == null ? 'Crear' : 'Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      final name = nameController.text.trim();
      final publisher = publisherController.text.trim();

      if (existingPack == null) {
        await ref.read(packsProvider.notifier).createPack(
              name: name,
              publisher: publisher,
              isAnimatedPack: isAnimatedPack,
            );
      } else {
        await ref.read(packsProvider.notifier).renamePack(
              packId: existingPack.id,
              newName: name,
              newPublisher: publisher,
            );
      }
    }
  }

  void _showThemePickerSheet(BuildContext context, WidgetRef ref) {
    final activeMember = ref.read(themeMemberProvider);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tema de Kessoku Band',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cambia los colores y el personaje de tu estudio:',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ...KessokuMember.values.map((member) {
                  final isSelected = member == activeMember;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: isSelected
                        ? member.primaryColor.withValues(alpha: 0.18)
                        : null,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      // Avatar limpio sin emoji encima de la cara
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: member.primaryColor.withValues(alpha: 0.25),
                          border: Border.all(
                            color: member.primaryColor,
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            member.assetPath,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                member.badgeEmoji,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        '${member.displayName} (${member.fullName})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        member.role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: member.primaryColor,
                            )
                          : null,
                      onTap: () {
                        ref
                            .read(themeMemberProvider.notifier)
                            .selectMember(member);
                        Navigator.of(sheetCtx).pop();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeletePack(
    BuildContext context,
    WidgetRef ref,
    StickerPack pack,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar paquete'),
          content: Text(
            '¿Seguro que deseas eliminar "${pack.name}" y todos sus archivos guardados en el dispositivo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await ref.read(packsProvider.notifier).deletePack(pack.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paquete "${pack.name}" eliminado.')),
        );
      }
    }
  }

  void _showPackOptionsSheet(
    BuildContext context,
    WidgetRef ref,
    StickerPack pack,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    pack.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('Autor: ${pack.publisher}'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Renombrar paquete / autor'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showCreateOrRenameDialog(
                      context,
                      ref,
                      existingPack: pack,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Duplicar paquete'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await ref
                        .read(packsProvider.notifier)
                        .duplicatePack(pack.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Se creó una copia de "${pack.name}".'),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Eliminar paquete',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _confirmDeletePack(context, ref, pack);
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
  Widget build(BuildContext context, WidgetRef ref) {
    final packsAsync = ref.watch(packsProvider);
    final activeMember = ref.watch(themeMemberProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ClipOval(
            child: Image.asset(
              'assets/icon.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.music_note_rounded,
                color: activeMember.primaryColor,
              ),
            ),
          ),
        ),
        title: const Text(
          'Bocchi Stickers',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Botón compacto con la carita de la integrante activa (sin desbordar el AppBar)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showThemePickerSheet(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: activeMember.primaryColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: activeMember.primaryColor,
                  width: 1.4,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: Image.asset(
                      activeMember.assetPath,
                      width: 22,
                      height: 22,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Text(
                        activeMember.badgeEmoji,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    activeMember.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.backup_outlined),
            tooltip: 'Copia de seguridad (.zip)',
            onSelected: (value) async {
              final backup = ref.read(backupServiceProvider);
              try {
                if (value == 'export') {
                  final saved = await backup.exportBackupZip();
                  if (context.mounted && saved != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Respaldo .zip exportado correctamente.'),
                      ),
                    );
                  }
                } else if (value == 'import') {
                  final count = await backup.importBackupZip();
                  if (count > 0) {
                    await ref.read(packsProvider.notifier).reloadPacks();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Se restauraron $count paquetes desde el archivo .zip.',
                          ),
                        ),
                      );
                    }
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error en respaldo: $e')),
                  );
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.upload_file_rounded),
                  title: Text('Exportar respaldo (.zip)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.download_for_offline_outlined),
                  title: Text('Importar respaldo (.zip)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: packsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text('Error al cargar los paquetes: $err'),
        ),
        data: (packs) {
          final totalStickers = packs.fold<int>(
            0,
            (sum, p) => sum + p.stickers.length,
          );

          return CustomScrollView(
            slivers: [
              // Banner superior personalizado con la integrante activa de Kessoku Band
              SliverToBoxAdapter(
                child: _KessokuHeroBanner(
                  member: activeMember,
                  packCount: packs.length,
                  totalStickers: totalStickers,
                  onTapCharacter: () => _showThemePickerSheet(context, ref),
                ),
              ),

              if (packs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyPacksState(member: activeMember),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.84,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final pack = packs[index];
                        return _PackCard(
                          pack: pack,
                          member: activeMember,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PackScreen(packId: pack.id),
                              ),
                            );
                          },
                          onLongPress: () =>
                              _showPackOptionsSheet(context, ref, pack),
                        );
                      },
                      childCount: packs.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateOrRenameDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text(
          'Nuevo paquete',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _KessokuHeroBanner extends StatelessWidget {
  final KessokuMember member;
  final int packCount;
  final int totalStickers;
  final VoidCallback onTapCharacter;

  const _KessokuHeroBanner({
    required this.member,
    required this.packCount,
    required this.totalStickers,
    required this.onTapCharacter,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTapCharacter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              member.primaryColor.withValues(alpha: 0.85),
              member.surfaceTint,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: member.primaryColor.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      member.role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    member.quote,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$packCount paquetes • $totalStickers stickers creados',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: Colors.black26,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: ClipOval(
                child: Image.asset(
                  member.assetPath,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        member.badgeEmoji,
                        style: const TextStyle(fontSize: 38),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado vacío con la monita del tema activo y sin botón duplicado
class _EmptyPacksState extends StatelessWidget {
  final KessokuMember member;

  const _EmptyPacksState({required this.member});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 88),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                color: member.primaryColor.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(
                  color: member.primaryColor,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: member.primaryColor.withValues(alpha: 0.25),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  member.assetPath,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.music_note_rounded,
                    size: 56,
                    color: member.primaryColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '¡Aún no tienes paquetes con ${member.displayName}!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Toca el botón "Nuevo paquete" de aquí abajo para empezar a armar tus stickers estáticos o animados.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  final StickerPack pack;
  final KessokuMember member;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PackCard({
    required this.pack,
    required this.member,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isReady = pack.isReady;
    final trayFile =
        pack.trayImagePath != null ? File(pack.trayImagePath!) : null;
    final hasTray = trayFile != null && trayFile.existsSync();
    final modTime =
        hasTray ? trayFile.lastModifiedSync().millisecondsSinceEpoch : 0;

    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: member.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: hasTray
                            ? Image.file(
                                trayFile,
                                key: ValueKey('${trayFile.path}_$modTime'),
                                width: 76,
                                height: 76,
                                fit: BoxFit.contain,
                              )
                            : Icon(
                                pack.isAnimatedPack
                                    ? Icons.movie_filter_rounded
                                    : Icons.collections_outlined,
                                size: 44,
                                color: member.primaryColor,
                              ),
                      ),
                    ),
                    if (pack.isAnimatedPack)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_circle_fill_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'GIF/MP4',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.more_vert, size: 20),
                        tooltip: 'Opciones',
                        onPressed: onLongPress,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                pack.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                pack.publisher,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${pack.stickers.length}/${AppConstants.maxStickersPerPack}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: member.primaryColor,
                        ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isReady
                          ? Colors.green.withValues(alpha: 0.18)
                          : Colors.amber.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isReady ? 'Listo' : 'Incompleto',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isReady
                            ? Colors.green.shade400
                            : Colors.amber.shade400,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
