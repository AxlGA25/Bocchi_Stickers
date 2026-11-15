import 'package:flutter/material.dart';

import '../../providers/editor_provider.dart';

class EditorToolsBar extends StatelessWidget {
  final EditorState state;
  final ValueChanged<bool> onKeepBackgroundChanged;
  final VoidCallback onToggleRoundedCorners;
  final ValueChanged<bool> onToggleWhiteBorder;
  final ValueChanged<double> onWhiteBorderWidthChanged;
  final VoidCallback onRunAutoAiCutout;
  final VoidCallback onClearAiCutout;
  final ValueChanged<EditorTool> onSelectTool;
  final ValueChanged<double> onBrushSizeChanged;
  final VoidCallback onResetTransform;

  const EditorToolsBar({
    super.key,
    required this.state,
    required this.onKeepBackgroundChanged,
    required this.onToggleRoundedCorners,
    required this.onToggleWhiteBorder,
    required this.onWhiteBorderWidthChanged,
    required this.onRunAutoAiCutout,
    required this.onClearAiCutout,
    required this.onSelectTool,
    required this.onBrushSizeChanged,
    required this.onResetTransform,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showBrushSlider = !state.keepBackground &&
        (state.activeTool == EditorTool.eraser ||
            state.activeTool == EditorTool.restore);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Selector principal: Quitar fondo vs Mantener fondo
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    icon: Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: Text('Quitar fondo'),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: Icon(Icons.image_outlined, size: 18),
                    label: Text('Mantener fondo'),
                  ),
                ],
                selected: {state.keepBackground},
                onSelectionChanged: (selection) {
                  onKeepBackgroundChanged(selection.first);
                },
              ),
            ),
            const SizedBox(height: 8),

            // 2. Fila de Borde Blanco estilo sticker (disponible en ambos modos)
            Row(
              children: [
                FilterChip(
                  selected: state.hasWhiteBorder,
                  onSelected: onToggleWhiteBorder,
                  avatar: const Icon(Icons.border_outer_rounded, size: 18),
                  label: const Text('Borde blanco'),
                ),
                if (state.hasWhiteBorder)
                  Expanded(
                    child: Slider(
                      value: state.whiteBorderWidth,
                      min: 2.0,
                      max: 22.0,
                      label: '${state.whiteBorderWidth.round()} px',
                      onChanged: onWhiteBorderWidthChanged,
                    ),
                  )
                else
                  const Spacer(),
                if (state.keepBackground)
                  FilterChip(
                    selected: state.roundedCornersOnKeepBg,
                    onSelected: (_) => onToggleRoundedCorners(),
                    label: const Text('Redondear'),
                  ),
              ],
            ),

            // 3. Controles según el modo elegido
            if (state.keepBackground) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Pellizca con 2 dedos para zoom o rotar.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onResetTransform,
                    icon: const Icon(Icons.center_focus_strong, size: 18),
                    label: const Text('Centrar'),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: state.isRemovingBg ? null : onRunAutoAiCutout,
                      icon: state.isRemovingBg
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(
                        state.aiCutoutImage == null
                            ? 'Quitar fondo (Auto IA)'
                            : 'IA aplicada',
                      ),
                    ),
                  ),
                  if (state.aiCutoutImage != null) ...[
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Quitar recorte IA',
                      onPressed: onClearAiCutout,
                      icon: const Icon(Icons.layers_clear_outlined, size: 20),
                    ),
                  ],
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Centrar imagen',
                    onPressed: onResetTransform,
                    icon: const Icon(Icons.center_focus_strong, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (showBrushSlider)
                Row(
                  children: [
                    const Icon(Icons.circle, size: 10),
                    Expanded(
                      child: Slider(
                        value: state.brushSize,
                        min: 6.0,
                        max: 80.0,
                        label: '${state.brushSize.round()} px',
                        onChanged: onBrushSizeChanged,
                      ),
                    ),
                    const Icon(Icons.circle, size: 22),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${state.brushSize.round()}px',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ToolButton(
                    icon: Icons.open_with_rounded,
                    label: 'Mover/Zoom',
                    isSelected: state.activeTool == EditorTool.move,
                    onTap: () => onSelectTool(EditorTool.move),
                  ),
                  _ToolButton(
                    icon: Icons.gesture_rounded,
                    label: 'Lazo',
                    isSelected: state.activeTool == EditorTool.lasso,
                    onTap: () => onSelectTool(EditorTool.lasso),
                  ),
                  _ToolButton(
                    icon: Icons.cleaning_services_outlined,
                    label: 'Borrador',
                    isSelected: state.activeTool == EditorTool.eraser,
                    onTap: () => onSelectTool(EditorTool.eraser),
                  ),
                  _ToolButton(
                    icon: Icons.brush_rounded,
                    label: 'Restaurar',
                    isSelected: state.activeTool == EditorTool.restore,
                    onTap: () => onSelectTool(EditorTool.restore),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
