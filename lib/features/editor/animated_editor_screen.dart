import 'dart:async';
import 'dart:typed_data';

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

  List<Uint8List> _previewFrames = [];
  int _currentFrameIdx = 0;
  int _frameDurationMs = 100;
  Timer? _playbackTimer;

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

  Future<void> _initMedia() async {
    setState(() => _isLoading = true);
    try {
      if (widget.isGif) {
        final (frames, avgDuration) =
            await _animService.extractGifFrames(widget.mediaPath);
        _previewFrames = frames;
        _frameDurationMs = avgDuration;
        _startPlaybackLoop();
      } else {
        final duration =
            await _animService.getVideoDurationMs(widget.mediaPath);
        _videoDurationMs = duration.clamp(600, 30000);
        final initialEnd = _videoDurationMs > 2500 ? 2500 : _videoDurationMs;
        _trimRangeMs = RangeValues(0, initialEnd.toDouble());
        await _extractVideoPreview();
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

  Future<void> _extractVideoPreview() async {
    setState(() => _isLoading = true);
    try {
      final frames = await _animService.extractVideoFrames(
        videoPath: widget.mediaPath,
        startMs: _trimRangeMs.start.round(),
        endMs: _trimRangeMs.end.round(),
        fps: _fps,
      );
      _previewFrames = frames;
      _currentFrameIdx = 0;
      _frameDurationMs = (1000 / _fps).round();
      _startPlaybackLoop();
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

  void _startPlaybackLoop() {
    _playbackTimer?.cancel();
    if (_previewFrames.isEmpty) return;

    _playbackTimer = Timer.periodic(
      Duration(milliseconds: _frameDurationMs),
      (_) {
        if (!mounted || _previewFrames.isEmpty) return;
        setState(() {
          _currentFrameIdx = (_currentFrameIdx + 1) % _previewFrames.length;
        });
      },
    );
  }

  Future<void> _onSaveAnimatedSticker() async {
    if (_previewFrames.isEmpty || _isSaving) return;

    final chosenEmojis = await EmojiPickerSheet.show(context);
    if (chosenEmojis == null || chosenEmojis.isEmpty || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final result = await _animService.buildAnimatedWebpFromPngFrames(
        pngFrames: _previewFrames,
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
        title: Text(widget.isGif ? 'Sticker desde GIF' : 'Sticker desde Video'),
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
                  Text('Extrayendo fotogramas en 512×512...'),
                ],
              ),
            )
          : Column(
              children: [
                // Vista previa animada en bucle
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: CheckerboardBackground(
                            squareSize: 14,
                            child: _previewFrames.isEmpty
                                ? const Center(
                                    child: Text('Sin fotogramas'),
                                  )
                                : Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.memory(
                                        _previewFrames[_currentFrameIdx],
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
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
                                            'Cuadro ${_currentFrameIdx + 1}/${_previewFrames.length}',
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
                      ),
                    ),
                  ),
                ),

                // Controles de recorte de tiempo (para video)
                if (!widget.isGif)
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainer,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Recorte: $clipSeconds s (máx. recomendado 3.5 s)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              DropdownButton<int>(
                                value: _fps,
                                items: const [
                                  DropdownMenuItem(
                                    value: 8,
                                    child: Text('8 FPS (Ligero)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 10,
                                    child: Text('10 FPS (Ideal)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 12,
                                    child: Text('12 FPS (Fluido)'),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _fps = val);
                                    _extractVideoPreview();
                                  }
                                },
                              ),
                            ],
                          ),
                          RangeSlider(
                            values: _trimRangeMs,
                            min: 0,
                            max: _videoDurationMs.toDouble(),
                            labels: RangeLabels(
                              '${(_trimRangeMs.start / 1000).toStringAsFixed(1)}s',
                              '${(_trimRangeMs.end / 1000).toStringAsFixed(1)}s',
                            ),
                            onChanged: (values) {
                              // Limitar el fragmento a entre 0.5s y 4.0s para cumplir <= 500 KB
                              final span = values.end - values.start;
                              if (span >= 400 && span <= 4000) {
                                setState(() => _trimRangeMs = values);
                              }
                            },
                            onChangeEnd: (_) => _extractVideoPreview(),
                          ),
                          Text(
                            'Se garantiza automáticamente 512×512 px y peso ≤ ${AppConstants.maxAnimatedStickerFileSizeBytes ~/ 1024} KB.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
