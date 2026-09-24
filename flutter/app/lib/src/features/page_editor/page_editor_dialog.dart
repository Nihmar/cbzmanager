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
  int _pieces = 2;

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

  List<Uint8List> _build() => applyEditPipeline(
        widget.source,
        width: _intOf(_width, _origW),
        height: _intOf(_height, _origH),
        adjust: _adjust,
        split: _split,
        horizontal: _horizontal,
        pieces: _pieces + 1,
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
            Container(
              width: 220,
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
              ),
              child: Image.memory(_preview(), fit: BoxFit.contain),
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
                        _split ? '${_pieces + 1} pieces' : 'Off',
                      ),
                      value: _split,
                      onChanged: (v) => setState(() => _split = v),
                    ),
                    if (_split)
                      Row(
                        children: [
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: true, label: Text('Rows')),
                              ButtonSegment(value: false, label: Text('Columns')),
                            ],
                            selected: {_horizontal},
                            onSelectionChanged: (s) =>
                                setState(() => _horizontal = s.first),
                          ),
                          Expanded(
                            child: Slider(
                              value: _pieces.toDouble(),
                              min: 1,
                              max: 6,
                              divisions: 5,
                              label: '${_pieces + 1}',
                              onChanged: (v) =>
                                  setState(() => _pieces = v.round()),
                            ),
                          ),
                        ],
                      ),
                    Text(
                      'Output: ${widget.targetExt} (${_split ? '${_pieces + 1} pages' : '1 page'})',
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
          onPressed: () => Navigator.of(context).pop(_build()),
          icon: const Icon(Icons.check),
          label: const Text('Apply'),
        ),
      ],
    );
  }
}
