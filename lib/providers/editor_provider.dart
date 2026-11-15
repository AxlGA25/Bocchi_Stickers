import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum EditorTool {
  move,
  lasso,
  eraser,
  restore,
}

enum MaskOperationType {
  eraser,
  restore,
  lasso,
}

class MaskOperation {
  final MaskOperationType type;
  final List<Offset> points;
  final double strokeWidth;

  const MaskOperation({
    required this.type,
    required this.points,
    this.strokeWidth = 28.0,
  });
}

class StickerTextOverlay {
  final String text;
  final Color color;
  final double fontSize;

  /// Posición vertical normalizada en el lienzo de 512x512 (ej. 0.18 arriba, 0.50 centro, 0.84 abajo)
  final double verticalAlignFactor;

  const StickerTextOverlay({
    required this.text,
    this.color = Colors.white,
    this.fontSize = 46.0,
    this.verticalAlignFactor = 0.84,
  });

  StickerTextOverlay copyWith({
    String? text,
    Color? color,
    double? fontSize,
    double? verticalAlignFactor,
  }) {
    return StickerTextOverlay(
      text: text ?? this.text,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      verticalAlignFactor: verticalAlignFactor ?? this.verticalAlignFactor,
    );
  }
}

class EditorState {
  final ui.Image? originalImage;
  final ui.Image? aiCutoutImage;
  final bool keepBackground;
  final bool roundedCornersOnKeepBg;
  final bool isRemovingBg;

  /// Borde blanco clásico alrededor del sujeto o tarjeta (Fase 6)
  final bool hasWhiteBorder;
  final double whiteBorderWidth;

  /// Texto superpuesto sobre el sticker (Fase 6)
  final StickerTextOverlay? textOverlay;

  final Offset offset;
  final double scale;
  final double rotation;
  final EditorTool activeTool;
  final double brushSize;
  final List<MaskOperation> operations;
  final List<MaskOperation> redoStack;
  final MaskOperation? activeStroke;

  const EditorState({
    this.originalImage,
    this.aiCutoutImage,
    this.keepBackground = false,
    this.roundedCornersOnKeepBg = false,
    this.isRemovingBg = false,
    this.hasWhiteBorder = true,
    this.whiteBorderWidth = 10.0,
    this.textOverlay,
    this.offset = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.activeTool = EditorTool.move,
    this.brushSize = 28.0,
    this.operations = const [],
    this.redoStack = const [],
    this.activeStroke,
  });

  ui.Image? get image {
    if (keepBackground) return originalImage;
    return aiCutoutImage ?? originalImage;
  }

  bool get canUndo => !keepBackground && operations.isNotEmpty;
  bool get canRedo => !keepBackground && redoStack.isNotEmpty;

  EditorState copyWith({
    ui.Image? originalImage,
    ui.Image? aiCutoutImage,
    bool clearAiCutout = false,
    bool? keepBackground,
    bool? roundedCornersOnKeepBg,
    bool? isRemovingBg,
    bool? hasWhiteBorder,
    double? whiteBorderWidth,
    StickerTextOverlay? textOverlay,
    bool clearTextOverlay = false,
    Offset? offset,
    double? scale,
    double? rotation,
    EditorTool? activeTool,
    double? brushSize,
    List<MaskOperation>? operations,
    List<MaskOperation>? redoStack,
    MaskOperation? activeStroke,
    bool clearActiveStroke = false,
  }) {
    return EditorState(
      originalImage: originalImage ?? this.originalImage,
      aiCutoutImage:
          clearAiCutout ? null : (aiCutoutImage ?? this.aiCutoutImage),
      keepBackground: keepBackground ?? this.keepBackground,
      roundedCornersOnKeepBg:
          roundedCornersOnKeepBg ?? this.roundedCornersOnKeepBg,
      isRemovingBg: isRemovingBg ?? this.isRemovingBg,
      hasWhiteBorder: hasWhiteBorder ?? this.hasWhiteBorder,
      whiteBorderWidth: whiteBorderWidth ?? this.whiteBorderWidth,
      textOverlay: clearTextOverlay ? null : (textOverlay ?? this.textOverlay),
      offset: offset ?? this.offset,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      activeTool: activeTool ?? this.activeTool,
      brushSize: brushSize ?? this.brushSize,
      operations: operations ?? this.operations,
      redoStack: redoStack ?? this.redoStack,
      activeStroke:
          clearActiveStroke ? null : (activeStroke ?? this.activeStroke),
    );
  }
}

final editorProvider =
    NotifierProvider.autoDispose<EditorNotifier, EditorState>(
  EditorNotifier.new,
);

class EditorNotifier extends AutoDisposeNotifier<EditorState> {
  @override
  EditorState build() {
    return const EditorState();
  }

  void setImage(ui.Image image) {
    const safeArea = 460.0;
    final maxSide = image.width > image.height
        ? image.width.toDouble()
        : image.height.toDouble();
    final initialScale = safeArea / maxSide;

    state = EditorState(
      originalImage: image,
      keepBackground: false,
      hasWhiteBorder: true,
      whiteBorderWidth: 10.0,
      offset: Offset.zero,
      scale: initialScale,
      rotation: 0.0,
      activeTool: EditorTool.move,
      brushSize: 28.0,
    );
  }

  void setKeepBackground(bool keep) {
    state = state.copyWith(
      keepBackground: keep,
      activeTool: keep ? EditorTool.move : state.activeTool,
      clearActiveStroke: true,
    );
  }

  void toggleRoundedCornersOnKeepBg() {
    state = state.copyWith(
      roundedCornersOnKeepBg: !state.roundedCornersOnKeepBg,
    );
  }

  void toggleWhiteBorder(bool enabled) {
    state = state.copyWith(hasWhiteBorder: enabled);
  }

  void setWhiteBorderWidth(double width) {
    state = state.copyWith(whiteBorderWidth: width.clamp(2.0, 22.0));
  }

  void setTextOverlay(StickerTextOverlay? overlay) {
    if (overlay == null || overlay.text.trim().isEmpty) {
      state = state.copyWith(clearTextOverlay: true);
    } else {
      state = state.copyWith(textOverlay: overlay);
    }
  }

  void setRemovingBg(bool busy) {
    state = state.copyWith(isRemovingBg: busy);
  }

  void setAiCutoutImage(ui.Image? cutout) {
    state = state.copyWith(
      aiCutoutImage: cutout,
      keepBackground: false,
      isRemovingBg: false,
    );
  }

  void clearAiCutout() {
    state = state.copyWith(clearAiCutout: true);
  }

  void selectTool(EditorTool tool) {
    if (state.keepBackground && tool != EditorTool.move) return;
    state = state.copyWith(activeTool: tool, clearActiveStroke: true);
  }

  void setBrushSize(double size) {
    state = state.copyWith(brushSize: size.clamp(6.0, 80.0));
  }

  void updateTransform({
    required Offset offset,
    required double scale,
    required double rotation,
  }) {
    state = state.copyWith(
      offset: offset,
      scale: scale.clamp(0.05, 12.0),
      rotation: rotation,
    );
  }

  void resetTransform() {
    final img = state.image;
    if (img == null) return;
    const safeArea = 460.0;
    final maxSide =
        img.width > img.height ? img.width.toDouble() : img.height.toDouble();
    state = state.copyWith(
      offset: Offset.zero,
      scale: safeArea / maxSide,
      rotation: 0.0,
    );
  }

  void startStroke(Offset point512) {
    if (state.keepBackground) return;
    final tool = state.activeTool;
    if (tool == EditorTool.move) return;

    final opType = switch (tool) {
      EditorTool.eraser => MaskOperationType.eraser,
      EditorTool.restore => MaskOperationType.restore,
      EditorTool.lasso => MaskOperationType.lasso,
      EditorTool.move => MaskOperationType.eraser,
    };

    state = state.copyWith(
      activeStroke: MaskOperation(
        type: opType,
        points: [point512],
        strokeWidth: state.brushSize,
      ),
    );
  }

  void appendStrokePoint(Offset point512) {
    final current = state.activeStroke;
    if (current == null) return;

    state = state.copyWith(
      activeStroke: MaskOperation(
        type: current.type,
        points: [...current.points, point512],
        strokeWidth: current.strokeWidth,
      ),
    );
  }

  void endStroke() {
    final current = state.activeStroke;
    if (current == null) return;

    if (current.type == MaskOperationType.lasso && current.points.length < 3) {
      state = state.copyWith(clearActiveStroke: true);
      return;
    }

    state = state.copyWith(
      operations: [...state.operations, current],
      redoStack: const [],
      clearActiveStroke: true,
    );
  }

  void undo() {
    if (!state.canUndo) return;
    final ops = List<MaskOperation>.from(state.operations);
    final last = ops.removeLast();
    state = state.copyWith(
      operations: ops,
      redoStack: [...state.redoStack, last],
    );
  }

  void redo() {
    if (!state.canRedo) return;
    final redos = List<MaskOperation>.from(state.redoStack);
    final restored = redos.removeLast();
    state = state.copyWith(
      operations: [...state.operations, restored],
      redoStack: redos,
    );
  }
}
