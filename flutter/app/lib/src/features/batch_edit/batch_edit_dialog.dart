import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../engine/image_edit.dart';
import 'batch_edit_service.dart';

/// Reusable colour-adjustment controls.
class ColorAdjustEditor extends StatelessWidget {
  const ColorAdjustEditor({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ColorAdjust value;
  final ValueChanged<ColorAdjust> onChanged;

  ColorAdjust _with({
    bool? invert,
    bool? grayscale,
    bool? sepia,
    double? rGain,
    double? gGain,
    double? bGain,
    double? saturation,
    double? contrast,
    double? brightness,
    double? gamma,
  }) => ColorAdjust(
    invert: invert ?? value.invert,
    grayscale: grayscale ?? value.grayscale,
    sepia: sepia ?? value.sepia,
    rGain: rGain ?? value.rGain,
    gGain: gGain ?? value.gGain,
    bGain: bGain ?? value.bGain,
    saturation: saturation ?? value.saturation,
    contrast: contrast ?? value.contrast,
    brightness: brightness ?? value.brightness,
    gamma: gamma ?? value.gamma,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('Grayscale'),
              selected: value.grayscale,
              onSelected: (v) => onChanged(_with(grayscale: v)),
            ),
            FilterChip(
              label: const Text('Sepia'),
              selected: value.sepia,
              onSelected: (v) => onChanged(_with(sepia: v)),
            ),
            FilterChip(
              label: const Text('Invert'),
              selected: value.invert,
              onSelected: (v) => onChanged(_with(invert: v)),
            ),
          ],
        ),
        _slider(
          'Brightness',
          value.brightness,
          -100,
          100,
          (v) => onChanged(_with(brightness: v)),
        ),
        _slider(
          'Contrast',
          value.contrast,
          0.25,
          3,
          (v) => onChanged(_with(contrast: v)),
        ),
        _slider(
          'Saturation',
          value.saturation,
          0,
          2,
          (v) => onChanged(_with(saturation: v)),
        ),
        _slider(
          'Gamma',
          value.gamma,
          0.25,
          3,
          (v) => onChanged(_with(gamma: v)),
        ),
        Row(
          children: [
            Expanded(
              child: _slider(
                'R gain',
                value.rGain,
                0,
                2,
                (v) => onChanged(_with(rGain: v)),
              ),
            ),
            Expanded(
              child: _slider(
                'G gain',
                value.gGain,
                0,
                2,
                (v) => onChanged(_with(gGain: v)),
              ),
            ),
            Expanded(
              child: _slider(
                'B gain',
                value.bGain,
                0,
                2,
                (v) => onChanged(_with(bGain: v)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(value.toStringAsFixed(2), textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

/// Batch-edit options dialog. [previewBytes] is the first page of the selection
/// (optional); it powers the live colour preview.
Future<BatchEditParams?> showBatchEditDialog(
  BuildContext context, {
  required int fileCount,
  Uint8List? previewBytes,
  bool defaultBackup = true,
}) {
  return showDialog<BatchEditParams>(
    context: context,
    builder: (context) => _BatchEditDialog(
      fileCount: fileCount,
      previewBytes: previewBytes,
      defaultBackup: defaultBackup,
    ),
  );
}

class _BatchEditDialog extends StatefulWidget {
  const _BatchEditDialog({
    required this.fileCount,
    this.previewBytes,
    this.defaultBackup = true,
  });

  final int fileCount;
  final Uint8List? previewBytes;
  final bool defaultBackup;

  @override
  State<_BatchEditDialog> createState() => _BatchEditDialogState();
}

class _BatchEditDialogState extends State<_BatchEditDialog> {
  int _percent = 100;
  ColorAdjust _adjust = ColorAdjust.neutral;
  bool _split = false;
  bool _horizontal = true;
  int _pieces = 2;
  late bool _backup = widget.defaultBackup;
  img.Image? _previewSrc;

  @override
  void initState() {
    super.initState();
    final bytes = widget.previewBytes;
    if (bytes != null) {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        _previewSrc = resampleImage(decoded, 260, 340) ?? decoded;
      }
    }
  }

  Uint8List? _previewBytes() {
    final src = _previewSrc;
    if (src == null) return null;
    return encodeImage(
      _adjust.isNeutral ? src : (adjustColors(src, _adjust) ?? src),
      '.png',
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewBytes();
    final piecesTotal = _pieces + 1;

    return AlertDialog(
      title: Text('Batch edit — ${widget.fileCount} file(s)'),
      content: SizedBox(
        width: 660,
        height: 560,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview != null)
              Container(
                width: 200,
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Image.memory(preview, fit: BoxFit.contain),
              ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Resize %'),
                        Expanded(
                          child: Slider(
                            value: _percent.toDouble(),
                            min: 10,
                            max: 200,
                            divisions: 38,
                            label: '$_percent%',
                            onChanged: (v) =>
                                setState(() => _percent = v.round()),
                          ),
                        ),
                        Text('$_percent%'),
                      ],
                    ),
                    const Divider(),
                    ColorAdjustEditor(
                      value: _adjust,
                      onChanged: (v) => setState(() => _adjust = v),
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Split pages'),
                      subtitle: Text(
                        _split
                            ? '$_pieces line(s) → $piecesTotal pieces'
                            : 'Off',
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
                              ButtonSegment(
                                value: false,
                                label: Text('Columns'),
                              ),
                            ],
                            selected: {_horizontal},
                            onSelectionChanged: (s) =>
                                setState(() => _horizontal = s.first),
                          ),
                          const SizedBox(width: 16),
                          const Text('Lines'),
                          Expanded(
                            child: Slider(
                              value: _pieces.toDouble(),
                              min: 1,
                              max: 6,
                              divisions: 5,
                              label: '$_pieces',
                              onChanged: (v) =>
                                  setState(() => _pieces = v.round()),
                            ),
                          ),
                        ],
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Backup originals (_OLD.cbz)'),
                      value: _backup,
                      onChanged: (v) => setState(() => _backup = v),
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
          onPressed: () => Navigator.of(context).pop(
            BatchEditParams(
              percent: _percent == 100 ? 0 : _percent,
              adjust: _adjust,
              split: _split,
              horizontal: _horizontal,
              pieces: _pieces + 1,
              backup: _backup,
            ),
          ),
          icon: const Icon(Icons.check),
          label: const Text('Apply'),
        ),
      ],
    );
  }
}
