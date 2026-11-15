import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/editor_provider.dart';
import '../../providers/packs_provider.dart';
import '../../services/background_removal_service.dart';
import '../pack/emoji_picker_sheet.dart';
import 'canvas_painter.dart';
import 'tools_bar.dart';

class EditorScreen extends ConsumerStatefulWidget {
  final String packId;
  final String imagePath;
  final String? existingStickerId;
  final String? originalPhotoPath;
  final List<String> initialEmojis;

  const EditorScreen({
    super.key,
    required this.packId,
    required this.imagePath,
    this.existingStickerId,
    this.originalPhotoPath,
    this.initialEmojis = const ['😀'],
  });

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final BackgroundRemovalService _bgService = BackgroundRemovalService();

  bool _isLoading = true;
  bool _isSaving = false;

  Offset _baseOffset = Offset.zero;
  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  Offset _startFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _loadWorkingImage(widget.imagePath);
  }

  Future<void> _loadWorkingImage(String path) async {
    setState(() => _isLoading = true);
    try {
      final bytes = await File(path).readAsBytes();
      final descriptor = await ui.ImageDescriptor.encoded(
        await ui.ImmutableBuffer.fromUint8List(bytes),
      );

      const maxWorkingSide = 1500;
      int? targetW;
      int? targetH;

      if (descriptor.width > maxWorkingSide ||
          descriptor.height > maxWorkingSide) {
        if (descriptor.width >= descriptor.height) {
          targetW = maxWorkingSide;
        } else {
          targetH = maxWorkingSide;
        }
      }

      final codec = await descriptor.instantiateCodec(
        targetWidth: targetW,
        targetHeight: targetH,
      );
      final frame = await codec.getNextFrame();

      if (mounted) {
        ref.read(editorProvider.notifier).setImage(frame.image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar imagen: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _runAutoAiBackgroundRemoval() async {
    final notifier = ref.read(editorProvider.notifier);
    final sourcePath = widget.originalPhotoPath ?? widget.imagePath;

    notifier.setRemovingBg(true);
    try {
      final cutout = await _bgService.removeBackgroundFromFile(sourcePath);
      if (!mounted) return;

      if (cutout == null) {
        notifier.setRemovingBg(false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se detectó un sujeto claro. Puedes usar el Lazo o el Borrador manual.',
            ),
          ),
        );
        return;
      }

      notifier.setAiCutoutImage(cutout);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '¡Fondo eliminado con IA! Puedes afinar detalles con Borrador o Restaurar.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        notifier.setRemovingBg(false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'El modelo de IA se está inicializando o falló ($e). Intenta de nuevo en unos segundos o usa el Lazo.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showTextOverlayDialog() async {
    final current = ref.read(editorProvider).textOverlay;
    final textCtrl = TextEditingController(text: current?.text ?? '');
    Color selectedColor = current?.color ?? Colors.white;
    double fontSize = current?.fontSize ?? 46.0;
    double verticalAlign = current?.verticalAlignFactor ?? 0.84;

    const palette = [
      Colors.white,
      Color(0xFFFFD54F),
      Color(0xFFFF5252),
      Color(0xFF69F0AE),
      Color(0xFF40C4FF),
      Color(0xFFE040FB),
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Texto en el sticker'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: textCtrl,
                      autofocus: true,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: 'Frase del sticker',
                        hintText: 'Ej. ¡Qué pro!',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Posición vertical:'),
                    const SizedBox(height: 6),
                    SegmentedButton<double>(
                      segments: const [
                        ButtonSegment(value: 0.16, label: Text('Arriba')),
                        ButtonSegment(value: 0.50, label: Text('Centro')),
                        ButtonSegment(value: 0.84, label: Text('Abajo')),
                      ],
                      selected: {verticalAlign},
                      onSelectionChanged: (sel) {
                        setDialogState(() => verticalAlign = sel.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text('Tamaño de letra: ${fontSize.round()}'),
                    Slider(
                      value: fontSize,
                      min: 28.0,
                      max: 72.0,
                      onChanged: (v) => setDialogState(() => fontSize = v),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      alignment: WrapAlignment.center,
                      children: palette.map((c) {
                        final isSelected =
                            selectedColor.toARGB32() == c.toARGB32();
                        return GestureDetector(
                          onTap: () => setDialogState(() => selectedColor = c),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.black54,
                                width: isSelected ? 3.5 : 1.5,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                if (current != null)
                  TextButton(
                    onPressed: () {
                      ref.read(editorProvider.notifier).setTextOverlay(null);
                      Navigator.of(dialogCtx).pop();
                    },
                    child: const Text('Quitar texto'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final txt = textCtrl.text.trim();
                    if (txt.isEmpty) {
                      ref.read(editorProvider.notifier).setTextOverlay(null);
                    } else {
                      ref.read(editorProvider.notifier).setTextOverlay(
                            StickerTextOverlay(
                              text: txt,
                              color: selectedColor,
                              fontSize: fontSize,
                              verticalAlignFactor: verticalAlign,
                            ),
                          );
                    }
                    Navigator.of(dialogCtx).pop();
                  },
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Uint8List> _exportCanvasToPng512(EditorState state) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(
        0,
        0,
        AppConstants.stickerSizePx + 0.0,
        AppConstants.stickerSizePx + 0.0,
      ),
    );

    StickerCanvasPainter.renderSticker512(
      canvas: canvas,
      state: state,
      includePreviewGuides: false,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      AppConstants.stickerSizePx,
      AppConstants.stickerSizePx,
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _onSavePressed() async {
    final editorState = ref.read(editorProvider);
    if (editorState.image == null || _isSaving) return;

    final chosenEmojis = await EmojiPickerSheet.show(
      context,
      initialEmojis: widget.initialEmojis,
    );
    if (chosenEmojis == null || chosenEmojis.isEmpty || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final png512Bytes = await _exportCanvasToPng512(editorState);

      await ref.read(packsProvider.notifier).saveSticker(
            packId: widget.packId,
            existingStickerId: widget.existingStickerId,
            png512Bytes: png512Bytes,
            originalImagePath: widget.originalPhotoPath ?? widget.imagePath,
            emojis: chosenEmojis,
          );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar el sticker: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Offset _toLogical512(Offset localPosition, double canvasPixelSize) {
    final factor = AppConstants.stickerSizePx / canvasPixelSize;
    return Offset(
      (localPosition.dx * factor).clamp(0.0, AppConstants.stickerSizePx + 0.0),
      (localPosition.dy * factor).clamp(0.0, AppConstants.stickerSizePx + 0.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor'),
        actions: [
          IconButton(
            tooltip: 'Agregar o editar texto',
            icon: Icon(
              Icons.text_fields_rounded,
              color: editorState.textOverlay != null
                  ? Theme.of(context).colorScheme.secondary
                  : null,
            ),
            onPressed: _showTextOverlayDialog,
          ),
          if (widget.originalPhotoPath != null &&
              widget.originalPhotoPath != widget.imagePath &&
              File(widget.originalPhotoPath!).existsSync())
            IconButton(
              tooltip: 'Re-editar desde foto original',
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: () => _loadWorkingImage(widget.originalPhotoPath!),
            ),
          IconButton(
            tooltip: 'Deshacer',
            icon: const Icon(Icons.undo_rounded),
            onPressed: editorState.canUndo ? notifier.undo : null,
          ),
          IconButton(
            tooltip: 'Rehacer',
            icon: const Icon(Icons.redo_rounded),
            onPressed: editorState.canRedo ? notifier.redo : null,
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: _isSaving || _isLoading ? null : _onSavePressed,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: const Text('Listo'),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final canvasSize = constraints.maxWidth;
                            final scaleFactor =
                                AppConstants.stickerSizePx / canvasSize;

                            final isMoveMode = editorState.keepBackground ||
                                editorState.activeTool == EditorTool.move;

                            return ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onScaleStart: (details) {
                                  if (isMoveMode) {
                                    _baseOffset = editorState.offset;
                                    _baseScale = editorState.scale;
                                    _baseRotation = editorState.rotation;
                                    _startFocalPoint = details.localFocalPoint;
                                  } else {
                                    notifier.startStroke(
                                      _toLogical512(
                                        details.localFocalPoint,
                                        canvasSize,
                                      ),
                                    );
                                  }
                                },
                                onScaleUpdate: (details) {
                                  if (isMoveMode) {
                                    final delta = (details.localFocalPoint -
                                            _startFocalPoint) *
                                        scaleFactor;
                                    notifier.updateTransform(
                                      offset: _baseOffset + delta,
                                      scale: _baseScale * details.scale,
                                      rotation:
                                          _baseRotation + details.rotation,
                                    );
                                  } else {
                                    notifier.appendStrokePoint(
                                      _toLogical512(
                                        details.localFocalPoint,
                                        canvasSize,
                                      ),
                                    );
                                  }
                                },
                                onScaleEnd: (_) {
                                  if (!isMoveMode) {
                                    notifier.endStroke();
                                  }
                                },
                                child: CheckerboardBackground(
                                  squareSize: 14,
                                  child: CustomPaint(
                                    size: Size.square(canvasSize),
                                    painter: StickerCanvasPainter(
                                      editorState: editorState,
                                      showGuides: true,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                EditorToolsBar(
                  state: editorState,
                  onKeepBackgroundChanged: notifier.setKeepBackground,
                  onToggleRoundedCorners: notifier.toggleRoundedCornersOnKeepBg,
                  onToggleWhiteBorder: notifier.toggleWhiteBorder,
                  onWhiteBorderWidthChanged: notifier.setWhiteBorderWidth,
                  onRunAutoAiCutout: _runAutoAiBackgroundRemoval,
                  onClearAiCutout: notifier.clearAiCutout,
                  onSelectTool: notifier.selectTool,
                  onBrushSizeChanged: notifier.setBrushSize,
                  onResetTransform: notifier.resetTransform,
                ),
              ],
            ),
    );
  }
}
