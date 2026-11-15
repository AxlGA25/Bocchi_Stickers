import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/models/sticker.dart';
import '../editor/canvas_painter.dart';

class StickerTile extends StatelessWidget {
  final Sticker sticker;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const StickerTile({
    super.key,
    required this.sticker,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(sticker.sourcePath);
    final exists = file.existsSync();
    final modTime = exists ? file.lastModifiedSync().millisecondsSinceEpoch : 0;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CheckerboardBackground(
              squareSize: 10,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: exists
                    ? Image.file(
                        file,
                        key: ValueKey('${sticker.sourcePath}_$modTime'),
                        fit: BoxFit.contain,
                      )
                    : const Icon(Icons.broken_image_outlined),
              ),
            ),
            if (sticker.emojis.isNotEmpty)
              Positioned(
                right: 6,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    sticker.emojis.join(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
