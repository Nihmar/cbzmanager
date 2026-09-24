import 'package:flutter/material.dart';

import 'convert_service.dart';

/// Options chosen in the convert dialog.
class ConvertRequest {
  const ConvertRequest({required this.backup, required this.threads});

  final bool backup;
  final int threads;
}

/// Asks how to convert: keep an `_OLD` backup or delete the originals, and how
/// many files to convert in parallel.
Future<ConvertRequest?> showConvertOptionsDialog(
  BuildContext context, {
  required int fileCount,
}) {
  return showDialog<ConvertRequest>(
    context: context,
    builder: (context) => _ConvertOptionsDialog(fileCount: fileCount),
  );
}

class _ConvertOptionsDialog extends StatefulWidget {
  const _ConvertOptionsDialog({required this.fileCount});

  final int fileCount;

  @override
  State<_ConvertOptionsDialog> createState() => _ConvertOptionsDialogState();
}

class _ConvertOptionsDialogState extends State<_ConvertOptionsDialog> {
  bool _backup = true;
  final _threads = TextEditingController(text: '0');

  @override
  void dispose() {
    _threads.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Convert to WebP'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.fileCount} file(s): WebP q${ConvertService.quality}, '
              'only if smaller, ComicInfo filtered, pages renumbered.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text('Originals', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Backup'),
                  icon: Icon(Icons.backup_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Delete'),
                  icon: Icon(Icons.delete_outline),
                ),
              ],
              selected: {_backup},
              onSelectionChanged: (selection) =>
                  setState(() => _backup = selection.first),
            ),
            const SizedBox(height: 8),
            Text(
              _backup
                  ? 'Originals are renamed to <name>_OLD.cbz.'
                  : 'Originals are overwritten with no backup.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _threads,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Parallel files (0 = auto)',
                helperText: 'Automatic uses one worker per CPU core, capped at 8.',
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
          onPressed: () {
            final threads = int.tryParse(_threads.text.trim()) ?? 0;
            Navigator.of(context).pop(
              ConvertRequest(backup: _backup, threads: threads < 0 ? 0 : threads),
            );
          },
          icon: const Icon(Icons.transform),
          label: const Text('Convert'),
        ),
      ],
    );
  }
}

/// Shows the conversion summary.
Future<void> showConvertResultsDialog(
  BuildContext context,
  List<ConvertOutcome> outcomes,
) {
  final ok = outcomes.where((o) => o.success).length;
  final failed = outcomes.where((o) => o.error != null).length;
  final pages = outcomes.fold<int>(0, (sum, o) => sum + o.converted);
  final kept = outcomes.fold<int>(0, (sum, o) => sum + o.kept);
  var saved = 0;
  for (final outcome in outcomes) {
    final delta = outcome.inputBytes - outcome.outputBytes;
    if (delta > 0) saved += delta;
  }

  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text('Conversion results'),
        content: SizedBox(
          width: 520,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.check_circle, size: 18),
                    label: Text('$ok converted'),
                  ),
                  if (kept > 0)
                    Chip(label: Text('$kept page(s) kept')),
                  if (failed > 0)
                    Chip(
                      avatar: const Icon(Icons.error, size: 18),
                      label: Text('$failed failed'),
                      backgroundColor: theme.colorScheme.errorContainer,
                    ),
                  Chip(label: Text('$pages page(s) to WebP')),
                  if (saved > 0) Chip(label: Text('${_mb(saved)} saved')),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: failed == 0
                    ? const Center(child: Text('All files converted.'))
                    : ListView(
                        children: [
                          for (final outcome in outcomes)
                            if (outcome.error != null)
                              ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.error_outline,
                                  color: theme.colorScheme.error,
                                ),
                                title: Text(outcome.item.name),
                                subtitle: Text(outcome.error!),
                              ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
