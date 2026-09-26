import 'package:flutter/material.dart';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';

import '../../engine/merge.dart';

/// Sequence-builder: lets the user assign chapter counts per volume and previews
/// the resulting volume labels. Returns the sequence, or null when cancelled.
Future<List<int>?> showSequenceBuilder(
  BuildContext context, {
  required List<ChapterInfo> chapters,
  required int lastVolume,
}) {
  return showDialog<List<int>>(
    context: context,
    builder: (context) =>
        _SequenceBuilderDialog(chapters: chapters, lastVolume: lastVolume),
  );
}

class _SequenceBuilderDialog extends StatefulWidget {
  const _SequenceBuilderDialog({
    required this.chapters,
    required this.lastVolume,
  });

  final List<ChapterInfo> chapters;
  final int lastVolume;

  @override
  State<_SequenceBuilderDialog> createState() => _SequenceBuilderDialogState();
}

class _SequenceBuilderDialogState extends State<_SequenceBuilderDialog> {
  final List<int> _sequence = <int>[];
  int _next = 2;

  int get _assigned {
    var total = 0;
    for (final n in _sequence) {
      total += n;
    }
    return total;
  }

  int get _remaining => widget.chapters.length - _assigned;

  void _add() {
    if (_next <= 0 || _next > _remaining) return;
    setState(() {
      _sequence.add(_next);
      if (_next > _remaining - _next) _next = _remaining - _next;
      if (_next < 1) _next = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final labels = customSequenceLabels(
      widget.chapters.length,
      _sequence,
      widget.lastVolume,
    );
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.customSequenceTitle),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.sequenceSummary(
                widget.chapters.length,
                _assigned,
                _remaining,
              ),
              style: theme.textTheme.bodyMedium,
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: widget.chapters.length,
                itemBuilder: (context, index) {
                  final label = labels[index];
                  final unassigned = label.isEmpty || label == '-';
                  return ListTile(
                    dense: true,
                    leading: Text('${index + 1}'.padLeft(3)),
                    title: Text(widget.chapters[index].fileName),
                    trailing: Text(
                      unassigned ? '-' : label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: unassigned
                            ? theme.colorScheme.outline
                            : theme.colorScheme.primary,
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    initialValue: '$_next',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l10n.nextVolume),
                    onChanged: (v) => _next = int.tryParse(v) ?? 1,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _remaining > 0 ? _add : null,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addVolume),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _sequence.isEmpty
                      ? null
                      : () => setState(() => _sequence.removeLast()),
                  child: Text(l10n.undo),
                ),
                TextButton(
                  onPressed: _sequence.isEmpty
                      ? null
                      : () => setState(_sequence.clear),
                  child: Text(l10n.clear),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _sequence.isEmpty
              ? null
              : () => Navigator.of(context).pop(List<int>.of(_sequence)),
          child: Text(l10n.useSequence),
        ),
      ],
    );
  }
}
