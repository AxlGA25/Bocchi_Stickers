import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../providers/editor_provider.dart';

class CheckerboardBackground extends StatelessWidget {
  final Widget? child;
  final double squareSize;

  const CheckerboardBackground({
    super.key,
    this.child,
    this.squareSize = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _CheckerboardPainter(
        squareSize: squareSize,
        colorA: isDark ? const Color(0xFF2B2B2B) : const Color(0xFFE0E0E0),
        colorB: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
      ),
      child: child,
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  final double squareSize;
  final Color colorA;
  final Color colorB;

  const _CheckerboardPainter({
    required this.squareSize,
    required this.colorA,
    required this.colorB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintA = Paint()..color = colorA;
    final paintB = Paint()..color = colorB;

    final cols = (size.width / squareSize).ceil();
    final rows = (size.height / squareSize).ceil();

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final isEven = (r + c).isEven;
        final rect = Rect.fromLTWH(
          c * squareSize,
          r * squareSize,
          squareSize,
          squareSize,
        );
        canvas.drawRect(rect, isEven ? paintA : paintB);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) {
    return oldDelegate.squareSize != squareSize ||
        oldDelegate.colorA != colorA ||
        oldDelegate.colorB != colorB;
  }
}

class StickerCanvasPainter extends CustomPainter {
  final EditorState editorState;
  final bool showGuides;

  const StickerCanvasPainter({
    required this.editorState,
    this.showGuides = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleFactor = size.width / AppConstants.stickerSizePx;
    canvas.save();
    canvas.scale(scaleFactor, scaleFactor);

    renderSticker512(
      canvas: canvas,
      state: editorState,
      includePreviewGuides: showGuides,
    );

    canvas.restore();
  }

  static void renderSticker512({
    required Canvas canvas,
    required EditorState state,
    required bool includePreviewGuides,
  }) {
    final image = state.image;
    const canvasRect = Rect.fromLTWH(
      0,
      0,
      AppConstants.stickerSizePx + 0.0,
      AppConstants.stickerSizePx + 0.0,
    );

    final margin = AppConstants.stickerMarginPx.toDouble();
    final safeRect = Rect.fromLTWH(
      margin,
      margin,
      AppConstants.stickerSizePx - (margin * 2),
      AppConstants.stickerSizePx - (margin * 2),
    );

    if (image != null) {
      canvas.save();
      canvas.clipRect(safeRect);

      // 1. Si el borde blanco está activo, pintar la silueta dilatada en blanco detrás del sujeto
      if (state.hasWhiteBorder && state.whiteBorderWidth > 0) {
        final r = state.whiteBorderWidth;
        const directions = 12;
        for (int i = 0; i < directions; i++) {
          final angle = (2 * math.pi * i) / directions;
          final dx = math.cos(angle) * r;
          final dy = math.sin(angle) * r;

          canvas.save();
          canvas.translate(dx, dy);
          canvas.saveLayer(
            canvasRect,
            Paint()
              ..colorFilter = const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
          );
          _drawSubjectWithMasks(canvas, image, state, canvasRect, safeRect);
          canvas.restore();
          canvas.restore();
        }
      }

      // 2. Pintar el sujeto recortado principal encima del borde blanco
      _drawSubjectWithMasks(canvas, image, state, canvasRect, safeRect);

      // 3. Pintar texto superpuesto (si existe) dentro del área segura de 480x480
      if (state.textOverlay != null &&
          state.textOverlay!.text.trim().isNotEmpty) {
        _drawTextOverlay(canvas, state.textOverlay!, safeRect);
      }

      canvas.restore();
    }

    // 4. Línea del Lazo en vivo
    if (!state.keepBackground &&
        includePreviewGuides &&
        state.activeStroke != null &&
        state.activeStroke!.type == MaskOperationType.lasso) {
      final path = _buildSmoothPath(state.activeStroke!.points, close: true);

      final outlineBg = Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      final outlineFg = Paint()
        ..color = const Color(0xFFFFD54F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawPath(path, outlineBg);
      canvas.drawPath(path, outlineFg);
    }

    // 5. Guía visual del margen obligatorio de 16 px
    if (includePreviewGuides) {
      final guidePaint = Paint()
        ..color = const Color(0xFF7C4DFF).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      if (state.keepBackground && state.roundedCornersOnKeepBg) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(safeRect, const Radius.circular(36)),
          guidePaint,
        );
      } else {
        canvas.drawRect(safeRect, guidePaint);
      }
    }
  }

  static void _drawSubjectWithMasks(
    Canvas canvas,
    ui.Image image,
    EditorState state,
    Rect canvasRect,
    Rect safeRect,
  ) {
    canvas.saveLayer(canvasRect, Paint());

    if (state.keepBackground && state.roundedCornersOnKeepBg) {
      final inset = state.hasWhiteBorder ? state.whiteBorderWidth : 0.0;
      canvas.clipRRect(
        RRect.fromRectAndRadius(
          safeRect.deflate(inset),
          const Radius.circular(36),
        ),
      );
    }

    _drawTransformedImage(canvas, image, state);

    if (!state.keepBackground) {
      final allOps = <MaskOperation>[
        ...state.operations,
        if (state.activeStroke != null &&
            state.activeStroke!.type != MaskOperationType.lasso)
          state.activeStroke!,
      ];

      for (final op in allOps) {
        _applyMaskOperation(canvas, image, state, op, canvasRect);
      }
    }

    canvas.restore();
  }

  static void _drawTextOverlay(
    Canvas canvas,
    StickerTextOverlay overlay,
    Rect safeRect,
  ) {
    final maxWidth = safeRect.width - 16;

    // Trazo negro exterior (contorno estilo meme/sticker)
    final strokeSpan = TextSpan(
      text: overlay.text,
      style: TextStyle(
        fontSize: overlay.fontSize,
        fontWeight: FontWeight.w900,
        height: 1.1,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8.0
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.black,
      ),
    );

    // Relleno interior de color
    final fillSpan = TextSpan(
      text: overlay.text,
      style: TextStyle(
        fontSize: overlay.fontSize,
        fontWeight: FontWeight.w900,
        height: 1.1,
        color: overlay.color,
      ),
    );

    final strokePainter = TextPainter(
      text: strokeSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    final fillPainter = TextPainter(
      text: fillSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    final dx = (AppConstants.stickerSizePx - fillPainter.width) / 2;
    final dy = (AppConstants.stickerSizePx * overlay.verticalAlignFactor) -
        (fillPainter.height / 2);
    final clampedDy = dy.clamp(
      safeRect.top + 4,
      safeRect.bottom - fillPainter.height - 4,
    );

    final offset = Offset(dx, clampedDy);
    strokePainter.paint(canvas, offset);
    fillPainter.paint(canvas, offset);
  }

  static void _drawTransformedImage(
    Canvas canvas,
    ui.Image image,
    EditorState state,
  ) {
    canvas.save();
    const center = Offset(
      AppConstants.stickerSizePx / 2,
      AppConstants.stickerSizePx / 2,
    );
    canvas.translate(center.dx + state.offset.dx, center.dy + state.offset.dy);
    canvas.rotate(state.rotation);
    canvas.scale(state.scale, state.scale);

    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImage(
      image,
      Offset(-image.width / 2, -image.height / 2),
      paint,
    );
    canvas.restore();
  }

  static void _applyMaskOperation(
    Canvas canvas,
    ui.Image image,
    EditorState state,
    MaskOperation op,
    Rect canvasRect,
  ) {
    switch (op.type) {
      case MaskOperationType.eraser:
        final path = _buildSmoothPath(op.points, close: false);
        final clearPaint = Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.stroke
          ..strokeWidth = op.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
        if (op.points.length == 1) {
          canvas.drawCircle(
            op.points.first,
            op.strokeWidth / 2,
            Paint()
              ..blendMode = BlendMode.clear
              ..style = PaintingStyle.fill,
          );
        } else {
          canvas.drawPath(path, clearPaint);
        }

      case MaskOperationType.lasso:
        if (op.points.length < 3) return;
        final inversePath = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(canvasRect)
          ..addPolygon(op.points, true);
        final clearPaint = Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        canvas.drawPath(inversePath, clearPaint);

      case MaskOperationType.restore:
        canvas.saveLayer(canvasRect, Paint());
        final strokePath = _buildSmoothPath(op.points, close: false);
        if (op.points.length == 1) {
          canvas.drawCircle(
            op.points.first,
            op.strokeWidth / 2,
            Paint()..style = PaintingStyle.fill,
          );
        } else {
          final maskPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = op.strokeWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true;
          canvas.drawPath(strokePath, maskPaint);
        }

        canvas.saveLayer(
          canvasRect,
          Paint()..blendMode = BlendMode.srcIn,
        );
        _drawTransformedImage(
          canvas,
          state.originalImage ?? image,
          state,
        );
        canvas.restore();
        canvas.restore();
    }
  }

  static Path _buildSmoothPath(List<Offset> points, {required bool close}) {
    final path = Path();
    if (points.isEmpty) return path;

    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    if (close) {
      path.close();
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant StickerCanvasPainter oldDelegate) {
    return oldDelegate.editorState != editorState ||
        oldDelegate.showGuides != showGuides;
  }
}
