import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/packs_provider.dart';
import '../../services/animated_sticker_service.dart';
import '../pack/emoji_picker_sheet.dart';
import 'canvas_painter.dart';

class AnimatedEditorScreen extends ConsumerStatefulWidget {
  final String packId;
  final String mediaPath;
  final bool isGif;

  const AnimatedEditorScreen({
    super.key,
    required this.packId,
    required this.mediaPath,
    this.isGif = false,
  });

  @override
  ConsumerState<AnimatedEditorScreen> createState() =>
      _AnimatedEditorScreenState();
}

class _AnimatedEditorScreenState extends ConsumerState<AnimatedEditorScreen> {
  final AnimatedStickerService _animService = AnimatedStickerService();

  bool _isLoading = true;
  bool _isSaving = false;

  int _videoDurationMs = 3000;
  RangeValues _trimRangeMs = const RangeValues(0, 2500);
  int _fps = 10;

  List<Uint8List> _rawFramesBytes = [];
  List<ui.Image> _decodedFrames = [];
  int _currentFrameIdx = 0;
  int _frameDurationMs = 100;
  Timer? _playbackTimer;

  // Transformación interactiva del video dentro del lienzo 512x512
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  Offset _baseOffset = Offset.zero;
  double _baseScale = 1.0;
  Offset _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _initMedia();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  String _formatTimestamp(double ms) {
    final totalTenths = (ms / 100).round();
    final minutes = totalTenths ~/ 600;
    final seconds = (totalTenths % 600) ~/ 10;
    final tenths = totalTenths % 10;
    final minStr = minutes.toString().padLeft(2, '0');
    final secStr = seconds.toString().padLeft(2, '0');
    return '$minStr:$secStr.$tenths';
  }

  Future<void> _initMedia() async {
    setState(() => _isLoading = true);
    try {
      if (widget.isGif) {
        final (frames, avgDuration) =
            await _animService.extractGifFrames(widget.mediaPath);
        _rawFramesBytes = frames;
        _frameDurationMs = avgDuration;
        await _decodeFramesForCanvas(resetFraming: true);
      } else {
        final duration =
            await _animService.getVideoDurationMs(widget.mediaPath);
        _videoDurationMs = duration.clamp(600, 600000);
        final initialEnd = _videoDurationMs > 2500 ? 2500 : _videoDurationMs;
        _trimRangeMs = RangeValues(0, initialEnd.toDouble());
        await _extractVideoPreview(resetFraming: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al abrir archivo animado: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _extractVideoPreview({bool resetFraming = false}) async {
    setState(() => _isLoading = true);
    try {
      final frames = await _animService.extractVideoFrames(
        videoPath: widget.mediaPath,
        startMs: _trimRangeMs.start.round(),
        endMs: _trimRangeMs.end.round(),
        fps: _fps,
      );
      _rawFramesBytes = frames;
      _currentFrameIdx = 0;
      _frameDurationMs = (1000 / _fps).round();
      await _decodeFramesForCanvas(resetFraming: resetFraming);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al extraer cuadros: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _decodeFramesForCanvas({required bool resetFraming}) async {
    final decoded = <ui.Image>[];
    for (final bytes in _rawFramesBytes) {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      decoded.add(frame.image);
    }
    _decodedFrames = decoded;

    if (resetFraming && _decodedFrames.isNotEmpty) {
      _alignFrame('fill_top');
    }
    _startPlaybackLoop();
  }

  /// Ajusta el encuadre del video: 'top' (arriba), 'center' (centro), 'bottom' (abajo) o 'fit' (completo)
  void _alignFrame(String preset) {
    if (_decodedFrames.isEmpty) return;
    final sample = _decodedFrames.first;
    const safeArea = 480.0;

    setState(() {
      if (preset == 'fit') {
        final maxSide = sample.width > sample.height
            ? sample.width.toDouble()
            : sample.height.toDouble();
        _scale = safeArea / maxSide;
        _offset = Offset.zero;
        return;
      }

      // Escala para llenar el cuadrado de 480x480 sin bordes vacíos
      final minSide = sample.width < sample.height
          ? sample.width.toDouble()
          : sample.height.toDouble();
      _scale = safeArea / minSide;

      final scaledH = sample.height * _scale;
      final maxShiftY = ((scaledH - safeArea) / 2).clamp(0.0, 1000.0);

      if (preset == 'top' || preset == 'fill_top') {
        // Baja la imagen para mostrar la parte superior (cabeza/rostro)
        _offset = Offset(0, maxShiftY * 0.85);
      } else if (preset == 'bottom') {
        // Sube la imagen para mostrar la parte inferior
        _offset = Offset(0, -maxShiftY * 0.85);
      } else {
        _offset = Offset.zero;
      }
    });
  }

  void _nudgeClip(double deltaMs) {
    final clipLen = _trimRangeMs.end - _trimRangeMs.start;
    double newStart = (_trimRangeMs.start + deltaMs)
        .clamp(0.0, (_videoDurationMs - clipLen).clamp(0.0, double.infinity));
    double newEnd =
        (newStart + clipLen).clamp(400.0, _videoDurationMs.toDouble());

    setState(() {
      _trimRangeMs = RangeValues(newStart, newEnd);
    });
    _extractVideoPreview(resetFraming: false);
  }

  void _startPlaybackLoop() {
    _playbackTimer?.cancel();
    if (_decodedFrames.isEmpty) return;

    _playbackTimer = Timer.periodic(
      Duration(milliseconds: _frameDurationMs),
      (_) {
        if (!mounted || _decodedFrames.isEmpty) return;
        setState(() {
          _currentFrameIdx = (_currentFrameIdx + 1) % _decodedFrames.length;
        });
      },
    );
  }

  /// Renderiza cada fotograma con la posición y zoom elegidos por el usuario a PNG 512x512
  Future<Uint8List> _renderFramedImageTo512Png(ui.Image src) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, 512, 512),
    );

    const margin = 16.0;
    const safeRect = Rect.fromLTWH(margin, margin, 480, 480);
    canvas.clipRect(safeRect);

    canvas.translate(256.0 + _offset.dx, 256.0 + _offset.dy);
    canvas.scale(_scale, _scale);
    canvas.drawImage(
      src,
      Offset(-src.width / 2, -src.height / 2),
      Paint()..filterQuality = FilterQuality.medium,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(512, 512);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _onSaveAnimatedSticker() async {
    if (_decodedFrames.isEmpty || _isSaving) return;

    final chosenEmojis = await EmojiPickerSheet.show(context);
    if (chosenEmojis == null || chosenEmojis.isEmpty || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final framedPngs = <Uint8List>[];
      for (final frameImg in _decodedFrames) {
        framedPngs.add(await _renderFramedImageTo512Png(frameImg));
      }

      final result = await _animService.buildAnimatedWebpFromPngFrames(
        pngFrames: framedPngs,
        frameDurationMs: _frameDurationMs,
      );

      await ref.read(packsProvider.notifier).saveAnimatedSticker(
            packId: widget.packId,
            animatedWebpBytes: result.animatedWebpBytes,
            firstFramePngBytes: result.firstFramePngBytes,
            emojis: chosenEmojis,
          );

      if (mounted) {
        final kb = (result.animatedWebpBytes.length / 1024).toStringAsFixed(1);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Sticker animado guardado! (${result.frameCount} cuadros • $kb KB)',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar animado: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final clipSeconds =
        ((_trimRangeMs.end - _trimRangeMs.start) / 1000).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isGif ? 'Editar GIF' : 'Editar Video',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed:
                  _isLoading || _isSaving ? null : _onSaveAnimatedSticker,
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
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Procesando fotogramas...'),
                ],
              ),
            )
          : Column(
              children: [
                // Lienzo interactivo 1:1 (puedes arrastrar hacia arriba/abajo/lados y hacer zoom)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final canvasPx = constraints.maxWidth;
                            final factor =
                                AppConstants.stickerSizePx / canvasPx;

                            return ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onScaleStart: (details) {
                                  _baseOffset = _offset;
                                  _baseScale = _scale;
                                  _startFocal = details.localFocalPoint;
                                },
                                onScaleUpdate: (details) {
                                  final delta =
                                      (details.localFocalPoint - _startFocal) *
                                          factor;
                                  setState(() {
                                    _offset = _baseOffset + delta;
                                    _scale = (_baseScale * details.scale)
                                        .clamp(0.2, 6.0);
                                  });
                                },
                                child: CheckerboardBackground(
                                  squareSize: 14,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (_decodedFrames.isNotEmpty)
                                        CustomPaint(
                                          painter: _AnimatedFramePainter(
                                            frame: _decodedFrames[
                                                _currentFrameIdx],
                                            offset: _offset,
                                            scale: _scale,
                                          ),
                                        ),
                                      Positioned(
                                        top: 10,
                                        right: 10,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            'Cuadro ${_currentFrameIdx + 1}/${_decodedFrames.length}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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

                // Panel inferior de encuadre y línea de tiempo (sin desbordamientos)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Botones rápidos para mover el encuadre del video
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              const Icon(Icons.open_with_rounded, size: 16),
                              const SizedBox(width: 6),
                              const Text(
                                'Encuadre:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ActionChip(
                                avatar: const Icon(
                                  Icons.vertical_align_top_rounded,
                                  size: 16,
                                ),
                                label: const Text('Arriba'),
                                onPressed: () => _alignFrame('top'),
                              ),
                              const SizedBox(width: 6),
                              ActionChip(
                                avatar: const Icon(
                                  Icons.vertical_align_center_rounded,
                                  size: 16,
                                ),
                                label: const Text('Centro'),
                                onPressed: () => _alignFrame('center'),
                              ),
                              const SizedBox(width: 6),
                              ActionChip(
                                avatar: const Icon(
                                  Icons.vertical_align_bottom_rounded,
                                  size: 16,
                                ),
                                label: const Text('Abajo'),
                                onPressed: () => _alignFrame('bottom'),
                              ),
                              const SizedBox(width: 6),
                              ActionChip(
                                avatar: const Icon(
                                  Icons.fit_screen_rounded,
                                  size: 16,
                                ),
                                label: const Text('Completo'),
                                onPressed: () => _alignFrame('fit'),
                              ),
                            ],
                          ),
                        ),

                        if (!widget.isGif) ...[
                          const Divider(height: 16),

                          // Fila de tiempo exacto (MM:SS.d) + FPS sin overflow
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Tiempo: ${_formatTimestamp(_trimRangeMs.start)} → ${_formatTimestamp(_trimRangeMs.end)} ($clipSeconds s)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              DropdownButton<int>(
                                value: _fps,
                                isDense: true,
                                items: const [
                                  DropdownMenuItem(
                                    value: 8,
                                    child: Text('8 FPS'),
                                  ),
                                  DropdownMenuItem(
                                    value: 10,
                                    child: Text('10 FPS'),
                                  ),
                                  DropdownMenuItem(
                                    value: 12,
                                    child: Text('12 FPS'),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _fps = val);
                                    _extractVideoPreview(resetFraming: false);
                                  }
                                },
                              ),
                            ],
                          ),

                          // Slider de recorte + botones de ajuste fino (-0.5s / +0.5s)
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Retroceder 0.5s',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.replay_5_rounded),
                                onPressed: _trimRangeMs.start > 0
                                    ? () => _nudgeClip(-500)
                                    : null,
                              ),
                              Expanded(
                                child: RangeSlider(
                                  values: _trimRangeMs,
                                  min: 0,
                                  max: _videoDurationMs.toDouble(),
                                  labels: RangeLabels(
                                    _formatTimestamp(_trimRangeMs.start),
                                    _formatTimestamp(_trimRangeMs.end),
                                  ),
                                  onChanged: (values) {
                                    final span = values.end - values.start;
                                    if (span >= 400 && span <= 4000) {
                                      setState(() => _trimRangeMs = values);
                                    }
                                  },
                                  onChangeEnd: (_) =>
                                      _extractVideoPreview(resetFraming: false),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Adelantar 0.5s',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.forward_5_rounded),
                                onPressed: _trimRangeMs.end < _videoDurationMs
                                    ? () => _nudgeClip(500)
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AnimatedFramePainter extends CustomPainter {
  final ui.Image frame;
  final Offset offset;
  final double scale;

  const _AnimatedFramePainter({
    required this.frame,
    required this.offset,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final factor = size.width / AppConstants.stickerSizePx;
    canvas.save();
    canvas.scale(factor, factor);

    const margin = 16.0;
    const safeRect = Rect.fromLTWH(margin, margin, 480, 480);

    canvas.save();
    canvas.clipRect(safeRect);
    canvas.translate(256.0 + offset.dx, 256.0 + offset.dy);
    canvas.scale(scale, scale);
    canvas.drawImage(
      frame,
      Offset(-frame.width / 2, -frame.height / 2),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();

    // Guía del margen de 16 px
    final guidePaint = Paint()
      ..color = const Color(0xFFFF66A3).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(safeRect, guidePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AnimatedFramePainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.offset != offset ||
        oldDelegate.scale != scale;
  }
}
