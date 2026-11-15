import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';

class BackgroundRemovalService {
  /// Recorta automáticamente el sujeto principal de [imagePath] y devuelve un ui.Image sin fondo.
  Future<ui.Image?> removeBackgroundFromFile(String imagePath) async {
    final options = SubjectSegmenterOptions(
      enableForegroundConfidenceMask: false,
      enableForegroundBitmap: true,
      enableMultipleSubjects: SubjectResultOptions(
        enableConfidenceMask: false,
        enableSubjectBitmap: false,
      ),
    );

    final segmenter = SubjectSegmenter(options: options);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final result = await segmenter.processImage(inputImage);
      final Uint8List? bitmapBytes = result.foregroundBitmap;

      if (bitmapBytes == null || bitmapBytes.isEmpty) {
        return null;
      }

      final codec = await ui.instantiateImageCodec(bitmapBytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      await segmenter.close();
    }
  }
}
