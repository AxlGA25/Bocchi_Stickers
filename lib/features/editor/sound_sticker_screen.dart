import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/theme_provider.dart';
import '../../services/sound_sticker_service.dart';

class SoundStickerScreen extends ConsumerStatefulWidget {
  const SoundStickerScreen({super.key});

  @override
  ConsumerState<SoundStickerScreen> createState() => _SoundStickerScreenState();
}

class _SoundStickerScreenState extends ConsumerState<SoundStickerScreen> {
  final ImagePicker _picker = ImagePicker();
  final SoundStickerService _soundService = SoundStickerService();
  final TextEditingController _urlController = TextEditingController();

  // Paso 1: Visual (Imagen o Video)
  bool _isVideoMode = false;
  String? _mediaPath;
  Uint8List? _videoPreviewFrame;
  bool _loadingPreview = false;
  String _cropAlign = 'center'; // top, center, bottom, fit
  int _videoDurationMs = 5000;
  double _startSeconds = 0.0;

  // Paso 2: Audio
  bool _useOriginalVideoAudio = true;
  String? _localAudioPath;
  String? _localAudioName;
  double _maxSeconds = 5.0;

  bool _isGenerating = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String _formatSeconds(double sec) {
    final totalTenths = (sec * 10).round();
    final mins = totalTenths ~/ 600;
    final secs = (totalTenths % 600) ~/ 10;
    final tenths = totalTenths % 10;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.$tenths';
  }

  void _switchMode(bool videoMode) {
    if (_isVideoMode == videoMode) return;
    setState(() {
      _isVideoMode = videoMode;
      _mediaPath = null;
      _videoPreviewFrame = null;
      _startSeconds = 0.0;
      _videoDurationMs = 5000;
      _cropAlign = videoMode ? 'top' : 'center';
      _useOriginalVideoAudio = videoMode;
    });
  }

  Future<void> _pickMedia() async {
    if (_isVideoMode) {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() {
        _mediaPath = picked.path;
        _loadingPreview = true;
        _startSeconds = 0.0;
      });

      try {
        final durMs = await _soundService.getVideoDurationMs(picked.path);
        final frame =
            await _soundService.extractSingleVideoFrame(picked.path, 0);
        if (!mounted) return;
        setState(() {
          _videoDurationMs = durMs.clamp(1000, 600000);
          final maxSecAvailable = (_videoDurationMs / 1000.0).clamp(1.0, 5.0);
          _maxSeconds = maxSecAvailable;
          _videoPreviewFrame = frame;
        });
      } finally {
        if (mounted) setState(() => _loadingPreview = false);
      }
    } else {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          _mediaPath = picked.path;
          _videoPreviewFrame = null;
        });
      }
    }
  }

  Future<void> _refreshVideoFrameAtStart() async {
    if (_mediaPath == null || !_isVideoMode) return;
    setState(() => _loadingPreview = true);
    try {
      final frame = await _soundService.extractSingleVideoFrame(
        _mediaPath!,
        (_startSeconds * 1000).round(),
      );
      if (mounted && frame != null) {
        setState(() => _videoPreviewFrame = frame);
      }
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  Future<void> _pickAudioFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
    );
    final file = res?.files.firstOrNull;
    if (file?.path != null) {
      setState(() {
        _localAudioPath = file!.path;
        _localAudioName = file.name;
        _urlController.clear();
      });
    }
  }

  BoxFit get _previewFit => _cropAlign == 'fit' ? BoxFit.contain : BoxFit.cover;

  Alignment get _previewAlignment {
    switch (_cropAlign) {
      case 'top':
        return Alignment.topCenter;
      case 'bottom':
        return Alignment.bottomCenter;
      default:
        return Alignment.center;
    }
  }

  Future<void> _generateMp4() async {
    if (_mediaPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isVideoMode
                ? 'Primero elige un video de tu galería.'
                : 'Primero elige una imagen de tu galería.',
          ),
        ),
      );
      return;
    }

    final needsCustomAudio = !_isVideoMode || !_useOriginalVideoAudio;
    final urlText = _urlController.text.trim();

    if (needsCustomAudio && _localAudioPath == null && urlText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Elige un archivo de audio o pega un link de Myinstants.'),
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      String? resolvedAudioPath;
      if (needsCustomAudio) {
        resolvedAudioPath = _localAudioPath ??
            await _soundService.downloadAudioFromUrl(urlText);
      }

      final savedLocation = await _soundService.createSoundStickerMp4(
        mediaPath: _mediaPath!,
        isVideo: _isVideoMode,
        audioPath: resolvedAudioPath,
        startMs: _isVideoMode ? (_startSeconds * 1000).round() : 0,
        maxDurationMs: (_maxSeconds * 1000).round(),
        cropAlign: _cropAlign,
      );

      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¡Listo en Alta Calidad!'),
          content: Text(
            'Tu archivo MP4 (512×512) se guardó en tu galería:\n\n'
            '$savedLocation\n\n'
            'Ábrelo desde WhatsApp -> Stickers -> Crear (+) para convertirlo en sticker.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text(
              'Error: $e',
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeMember = ref.watch(themeMemberProvider);
    final maxStartSec = ((_videoDurationMs / 1000.0) - 1.0).clamp(0.0, 600.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estudio MP4 + Sonido'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // TARJETA 1: VISUAL (IMAGEN O VIDEO)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_motion_rounded,
                          color: activeMember.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '1. Elige Imagen o Video',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Selector Imagen / Video
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: false,
                          icon: Icon(Icons.image_rounded),
                          label: Text('Imagen'),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          icon: Icon(Icons.movie_rounded),
                          label: Text('Video animado'),
                        ),
                      ],
                      selected: <bool>{_isVideoMode},
                      onSelectionChanged: _isGenerating
                          ? null
                          : (set) => _switchMode(set.first),
                    ),
                    const SizedBox(height: 14),

                    // Vista previa cuadrada 512x512 con encuadre en vivo
                    Center(
                      child: GestureDetector(
                        onTap: _isGenerating ? null : _pickMedia,
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: activeMember.primaryColor
                                  .withValues(alpha: 0.7),
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child:
                                _buildPreviewContent(activeMember.primaryColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Botones rápidos de encuadre
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _AlignChip(
                          label: 'Arriba',
                          value: 'top',
                          selected: _cropAlign == 'top',
                          onSelected: () => setState(() => _cropAlign = 'top'),
                        ),
                        _AlignChip(
                          label: 'Centro',
                          value: 'center',
                          selected: _cropAlign == 'center',
                          onSelected: () =>
                              setState(() => _cropAlign = 'center'),
                        ),
                        _AlignChip(
                          label: 'Abajo',
                          value: 'bottom',
                          selected: _cropAlign == 'bottom',
                          onSelected: () =>
                              setState(() => _cropAlign = 'bottom'),
                        ),
                        _AlignChip(
                          label: 'Completo',
                          value: 'fit',
                          selected: _cropAlign == 'fit',
                          onSelected: () => setState(() => _cropAlign = 'fit'),
                        ),
                      ],
                    ),

                    // Control de minuto/segundo de inicio (solo si es video largo)
                    if (_isVideoMode &&
                        _mediaPath != null &&
                        maxStartSec > 0.5) ...[
                      const Divider(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Inicio del recorte:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _formatSeconds(_startSeconds),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: activeMember.primaryColor,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _startSeconds.clamp(0.0, maxStartSec),
                        min: 0.0,
                        max: maxStartSec,
                        onChanged: _isGenerating
                            ? null
                            : (v) => setState(() => _startSeconds = v),
                        onChangeEnd: (_) => _refreshVideoFrameAtStart(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // TARJETA 2: SONIDO Y DURACIÓN (JUSTO ABAJO)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.volume_up_rounded,
                          color: activeMember.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '2. Sonido y duración',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isVideoMode)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Usar audio original del video',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Desactívalo si quieres ponerle otro sonido o meme',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _useOriginalVideoAudio,
                        onChanged: _isGenerating
                            ? null
                            : (v) => setState(() => _useOriginalVideoAudio = v),
                      ),
                    if (!_isVideoMode || !_useOriginalVideoAudio) ...[
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _isGenerating ? null : _pickAudioFile,
                        icon: const Icon(Icons.audio_file_rounded),
                        label: Text(
                          _localAudioName != null
                              ? 'Audio: $_localAudioName'
                              : 'Elegir MP3 / WAV / M4A del teléfono',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _urlController,
                        enabled: !_isGenerating,
                        onChanged: (val) {
                          if (val.trim().isNotEmpty &&
                              _localAudioPath != null) {
                            setState(() {
                              _localAudioPath = null;
                              _localAudioName = null;
                            });
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'O pega un link de Myinstants / .mp3',
                          hintText: 'https://www.myinstants.com/es/instant/...',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Duración del clip (máx. 5 s):',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${_maxSeconds.toStringAsFixed(1)} s',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: activeMember.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _maxSeconds.clamp(1.0, 5.0),
                      min: 1.0,
                      max: 5.0,
                      divisions: 8,
                      label: '${_maxSeconds.toStringAsFixed(1)} s',
                      onChanged: _isGenerating
                          ? null
                          : (v) => setState(() => _maxSeconds = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // BOTÓN GENERAR
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _isGenerating ? null : _generateMp4,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.movie_creation_rounded),
                label: Text(
                  _isGenerating
                      ? 'Exportando MP4 en alta calidad...'
                      : 'Guardar MP4 en Galería',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Se guarda en Movies/BocchiStickers en 512×512 HD (2.8 Mbps).',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewContent(Color accent) {
    if (_loadingPreview) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_mediaPath == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isVideoMode
                ? Icons.video_call_rounded
                : Icons.add_photo_alternate_rounded,
            size: 52,
            color: accent,
          ),
          const SizedBox(height: 10),
          Text(
            _isVideoMode
                ? 'Toca para elegir un video'
                : 'Toca para elegir una imagen',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      );
    }

    if (_isVideoMode && _videoPreviewFrame != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            _videoPreviewFrame!,
            fit: _previewFit,
            alignment: _previewAlignment,
            gaplessPlayback: true,
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Toca para cambiar',
                style: TextStyle(color: Colors.white, fontSize: 10.5),
              ),
            ),
          ),
        ],
      );
    }

    if (!_isVideoMode) {
      return Image.file(
        File(_mediaPath!),
        fit: _previewFit,
        alignment: _previewAlignment,
      );
    }

    return const Center(
      child: Icon(Icons.movie_rounded, size: 48, color: Colors.white70),
    );
  }
}

class _AlignChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onSelected;

  const _AlignChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => onSelected(),
    );
  }
}
