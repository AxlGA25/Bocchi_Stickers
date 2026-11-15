import 'package:flutter/material.dart';

import '../../core/constants.dart';

class EmojiPickerSheet extends StatefulWidget {
  final List<String> initialEmojis;

  const EmojiPickerSheet({
    super.key,
    this.initialEmojis = const ['😀'],
  });

  static Future<List<String>?> show(
    BuildContext context, {
    List<String> initialEmojis = const ['😀'],
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EmojiPickerSheet(initialEmojis: initialEmojis),
    );
  }

  @override
  State<EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<EmojiPickerSheet> {
  static const List<String> _presetEmojis = [
    '😀',
    '😂',
    '🤣',
    '😎',
    '😍',
    '🥰',
    '😘',
    '🤪',
    '🤩',
    '🥳',
    '😭',
    '😤',
    '😡',
    '🤬',
    '🤯',
    '😱',
    '🥺',
    '😴',
    '🤔',
    '🫡',
    '🙄',
    '😬',
    '🤡',
    '👻',
    '💀',
    '👽',
    '🤖',
    '🔥',
    '✨',
    '❤️',
    '💔',
    '💯',
    '👍',
    '👎',
    '👏',
    '🙏',
    '💪',
    '👀',
    '🎉',
    '🚀',
  ];

  late final List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(
      widget.initialEmojis.isEmpty ? const ['😀'] : widget.initialEmojis,
    );
  }

  void _toggleEmoji(String emoji) {
    setState(() {
      if (_selected.contains(emoji)) {
        if (_selected.length > AppConstants.minEmojisPerSticker) {
          _selected.remove(emoji);
        }
      } else {
        if (_selected.length < AppConstants.maxEmojisPerSticker) {
          _selected.add(emoji);
        } else {
          // Si ya hay 3, reemplaza el último seleccionado
          _selected[_selected.length - 1] = emoji;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Elige de 1 a 3 emojis',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Chip(
                  label: Text(
                    '${_selected.length}/${AppConstants.maxEmojisPerSticker}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'WhatsApp usa estos emojis para sugerir tu sticker mientras escribes en el chat.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),

            // Emojis seleccionados actualmente
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _selected
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          e,
                          style: const TextStyle(fontSize: 32),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Cuadrícula de emojis rápidos
            SizedBox(
              height: 240,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _presetEmojis.length,
                itemBuilder: (context, index) {
                  final emoji = _presetEmojis[index];
                  final isSelected = _selected.contains(emoji);

                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _toggleEmoji(emoji),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_selected),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Guardar sticker'),
            ),
          ],
        ),
      ),
    );
  }
}
