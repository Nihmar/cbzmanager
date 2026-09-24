import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../engine/format.dart';
import '../../engine/image_edit.dart';
import '../batch_edit/batch_edit_dialog.dart' show ColorAdjustEditor;

/// Single-page editor: resize (aspect lock), colour adjustments and split.
///
/// Returns the encoded piece(s) — more than one when splitting — or null when
/// cancelled.
Future<List<Uint8List>?> showPageEditorDialog(
  BuildContext context, {
  required Uint8List pageBytes,
  required String pageName,
}) {
  final decoded = img.decodeImage(pageBytes);
  if (decoded == null) {
    return showDialog<List<Uint8List>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit page'),
        content: Text('Cannot decode $pageName.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  return showDialog<List<Uint8List>>(
    context: context,
    builder: (context) => _PageEditorDialog(
      source: decoded,
      pageName: pageName,
      targetExt: encodeExtFor(extensionOf(pageName)),
    ),
  );
}

class _PageEditorDialog extends StatefulWidget {
  const _PageEditorDialog({
    required this.source,
    required this.pageName,
    required this.targetExt,
  });

  final img.Image source;
  final String pageName;
  final String targetExt;

  @override
  State<_PageEditorDialog> createState() => _PageEditorDialogState();
}

class _PageEditorDialogState extends State<_PageEditorDialog> {
  late final int _origW = widget.source.width;
  late final int _origH = widget.source.height;
  late final TextEditingController _width = TextEditingController(text: '$_origW');
  late final TextEditingController _height = TextEditingController(text: '$_origH');

  bool _lockAspect = true;
  ColorAdjust _adjust = ColorAdjust.neutral;
  bool _split = false;
  bool _horizontal = true;
  final List<double> _cuts = <double>[];

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  int _intOf(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim())?.clamp(1, 20000) ?? fallback;

  void _onWidthChanged() {
    if (!_lockAspect) return;
    final w = _intOf(_width, _origW);
    _height.text = '${(w * _origH / _origW).round().clamp(1, 20000)}';
  }

  void _onHeightChanged() {
    if (!_lockAspect) return;
    final h = _intOf(_height, _origH);
    _width.text = '${(h * _origW / _origH).round().clamp(1, 20000)}';
  }

  Uint8List _preview() {
    var image = resampleImage(widget.source, 240, 320) ?? widget.source;
    if (!_adjust.isNeutral) {
      image = adjustColors(image, _adjust) ?? image;
    }
    return encodeImage(image, '.png');
  }

  /// Interactive preview: cut lines can be added (tap), moved (drag) and
  /// removed (long-press) once splitting is enabled.
  Widget _buildPreview(BoxConstraints constraints) {
    final aspect = _origW / _origH;
    final boxAspect = constraints.maxWidth / constraints.maxHeight;
    final w = aspect > boxAspect
        ? constraints.maxWidth
        : constraints.maxHeight * aspect;
    final h = aspect > boxAspect
        ? constraints.maxWidth / aspect
        : constraints.maxHeight;

    return Center(
      child: SizedBox(
        width: w,
        height: h,
        child: GestureDetector(
          onTapUp: !_split
              ? null
              : (details) {
                  final frac = _horizontal
                      ? details.localPosition.dy / h
                      : details.localPosition.dx / w;
                  setState(() {
                    _cuts
                      ..add(frac.clamp(0.02, 0.98))
                      ..sort();
                  });
                },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(_preview(), fit: BoxFit.fill),
              if (_split)
                for (var i = 0; i < _cuts.length; i++)
                  Positioned(
                    left: _horizontal ? 0 : _cuts[i] * w - 4,
                    top: _horizontal ? _cuts[i] * h - 4 : 0,
                    width: _horizontal ? w : 8,
                    height: _horizontal ? 8 : h,
                    child: GestureDetector(
                      onPanUpdate: (details) => setState(() {
                        final delta = _horizontal
                            ? details.delta.dy / h
                            : details.delta.dx / w;
                        _cuts[i] = (_cuts[i] + delta).clamp(0.02, 0.98);
                      }),
                      onLongPress: () => setState(() => _cuts.removeAt(i)),
                      child: MouseRegion(
                        cursor: _horizontal
                            ? SystemMouseCursors.resizeUpDown
                            : SystemMouseCursors.resizeLeftRight,
                        child: Container(
                          color: Colors.red.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  List<Uint8List> _build() => applyEditPipeline(
        widget.source,
        width: _intOf(_width, _origW),
        height: _intOf(_height, _origH),
        adjust: _adjust,
        split: _split,
        horizontal: _horizontal,
        cuts: _cuts,
        targetExt: widget.targetExt,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Edit ${widget.pageName}'),
      content: SizedBox(
        width: 700,
        height: 580,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        _buildPreview(constraints),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Size', style: theme.textTheme.labelLarge),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _width,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Width'),
                            onChanged: (_) =>
                                setState(() => _onWidthChanged()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _height,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Height'),
                            onChanged: (_) =>
                                setState(() => _onHeightChanged()),
                          ),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Keep aspect ratio'),
                      value: _lockAspect,
                      onChanged: (v) => setState(() => _lockAspect = v ?? true),
                    ),
                    const Divider(),
                    ColorAdjustEditor(
                      value: _adjust,
                      onChanged: (v) => setState(() => _adjust = v),
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Split page'),
                      subtitle: Text(
                        _split ? '${_cuts.length + 1} pieces' : 'Off',
                      ),
                      value: _split,
                      onChanged: (v) => setState(() => _split = v),
                    ),
                    if (_split) ...[
                      Row(
                        children: [
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: true, label: Text('Rows')),
                              ButtonSegment(value: false, label: Text('Columns')),
                            ],
                            selected: {_horizontal},
                            onSelectionChanged: (s) => setState(() {
                              _horizontal = s.first;
                              _cuts.clear();
                            }),
                          ),
                          const Spacer(),
                          Text('${_cuts.length} line(s)'),
                          TextButton(
                            onPressed: _cuts.isEmpty
                                ? null
                                : () => setState(_cuts.clear),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                      Text(
                        'Tap the preview to add a cut, drag to move it, '
                        'long-press to remove.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      'Output: ${widget.targetExt} '
                      '(${_split ? '${_cuts.length + 1} pages' : '1 page'})',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _split && _cuts.isEmpty
              ? null
              : () => Navigator.of(context).pop(_build()),
          icon: const Icon(Icons.check),
          label: const Text('Apply'),
        ),
      ],
    );
  }
}
