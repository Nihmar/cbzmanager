import 'package:flutter/material.dart';

import 'cbr_service.dart';

/// Options for a CBR→CBZ run.
class CbrConvertRequest {
  const CbrConvertRequest({
    required this.skipExisting,
    required this.deleteSource,
    required this.threads,
  });

  final bool skipExisting;
  final bool deleteSource;
  final int threads;
}

Future<CbrConvertRequest?> showCbrOptionsDialog(
  BuildContext context, {
  required int fileCount,
  int defaultThreads = 0,
}) {
  return showDialog<CbrConvertRequest>(
    context: context,
    builder: (context) => _CbrOptionsDialog(
      fileCount: fileCount,
      defaultThreads: defaultThreads,
    ),
  );
}

class _CbrOptionsDialog extends StatefulWidget {
  const _CbrOptionsDialog({
    required this.fileCount,
    this.defaultThreads = 0,
  });

  final int fileCount;
  final int defaultThreads;

  @override
  State<_CbrOptionsDialog> createState() => _CbrOptionsDialogState();
}

class _CbrOptionsDialogState extends State<_CbrOptionsDialog> {
  bool _skipExisting = true;
  bool _deleteSource = false;
  late final _threads =
      TextEditingController(text: '${widget.defaultThreads}');

  @override
  void dispose() {
    _threads.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Convert CBR to CBZ'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.fileCount} CBR archive(s). ComicInfo.xml and '
              'non-image entries are dropped, images renumbered page_NNNN.*.',
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Skip existing .cbz targets'),
              value: _skipExisting,
              onChanged: (v) => setState(() => _skipExisting = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Delete the .cbr source after conversion'),
              value: _deleteSource,
              onChanged: (v) => setState(() => _deleteSource = v),
            ),
            TextField(
              controller: _threads,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Parallel files (0 = auto)',
                helperText: 'Automatic uses one worker per CPU core, capped at 4.',
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
            CbrConvertRequest(
              skipExisting: _skipExisting,
              deleteSource: _deleteSource,
              threads: int.tryParse(_threads.text.trim()) ?? 0,
            ),
          ),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Convert'),
        ),
      ],
    );
  }
}

Future<void> showCbrResultsDialog(
  BuildContext context,
  List<CbrConvertOutcome> outcomes,
) {
  final converted = outcomes.where((o) => o.success && !o.skipped).length;
  final skipped = outcomes.where((o) => o.skipped).length;
  final failed = outcomes.where((o) => o.error != null).length;
  final pages = outcomes.fold<int>(0, (sum, o) => sum + o.pages);

  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text('CBR → CBZ results'),
        content: SizedBox(
          width: 520,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.check_circle, size: 18),
                    label: Text('$converted converted'),
                  ),
                  if (skipped > 0) Chip(label: Text('$skipped skipped')),
                  if (failed > 0)
                    Chip(
                      avatar: const Icon(Icons.error, size: 18),
                      label: Text('$failed failed'),
                      backgroundColor: theme.colorScheme.errorContainer,
                    ),
                  Chip(label: Text('$pages page(s)')),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: failed == 0
                    ? const Center(child: Text('All done.'))
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
                                title: Text(outcome.name),
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
