import 'package:flutter/material.dart';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';

import '../../util/service_messages.dart';
import 'convert_service.dart';

/// Options chosen in the convert dialog.
class ConvertRequest {
  const ConvertRequest({required this.backup, required this.threads});

  final bool backup;
  final int threads;
}

/// Asks how to convert: keep an `_OLD` backup or delete the originals, and how
/// many files to convert in parallel.  [defaultThreads]/[defaultBackup] come
/// from the persisted settings.
Future<ConvertRequest?> showConvertOptionsDialog(
  BuildContext context, {
  required int fileCount,
  int defaultThreads = 0,
  bool defaultBackup = true,
}) {
  return showDialog<ConvertRequest>(
    context: context,
    builder: (context) => _ConvertOptionsDialog(
      fileCount: fileCount,
      defaultThreads: defaultThreads,
      defaultBackup: defaultBackup,
    ),
  );
}

class _ConvertOptionsDialog extends StatefulWidget {
  const _ConvertOptionsDialog({
    required this.fileCount,
    this.defaultThreads = 0,
    this.defaultBackup = true,
  });

  final int fileCount;
  final int defaultThreads;
  final bool defaultBackup;

  @override
  State<_ConvertOptionsDialog> createState() => _ConvertOptionsDialogState();
}

class _ConvertOptionsDialogState extends State<_ConvertOptionsDialog> {
  late bool _backup = widget.defaultBackup;
  late final _threads = TextEditingController(text: '${widget.defaultThreads}');

  @override
  void dispose() {
    _threads.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.convertWebp),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.convertSummary(widget.fileCount, ConvertService.quality),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(l10n.originals, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(l10n.backup),
                  icon: const Icon(Icons.backup_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text(l10n.delete),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
              selected: {_backup},
              onSelectionChanged: (selection) =>
                  setState(() => _backup = selection.first),
            ),
            const SizedBox(height: 8),
            Text(
              _backup ? l10n.originalsRenamed : l10n.originalsOverwritten,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _threads,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.parallelFiles,
                helperText: l10n.autoThreadsCapped8,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: () {
            final threads = int.tryParse(_threads.text.trim()) ?? 0;
            Navigator.of(context).pop(
              ConvertRequest(
                backup: _backup,
                threads: threads < 0 ? 0 : threads,
              ),
            );
          },
          icon: const Icon(Icons.transform),
          label: Text(l10n.convert),
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
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.conversionResults),
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
                    label: Text(l10n.convertedCount(ok)),
                  ),
                  if (kept > 0) Chip(label: Text(l10n.keptPages(kept))),
                  if (failed > 0)
                    Chip(
                      avatar: const Icon(Icons.error, size: 18),
                      label: Text(l10n.failedCount(failed)),
                      backgroundColor: theme.colorScheme.errorContainer,
                    ),
                  Chip(label: Text(l10n.pagesToWebp(pages))),
                  if (saved > 0) Chip(label: Text(l10n.savedSize(_mb(saved)))),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: failed == 0
                    ? Center(child: Text(l10n.allFilesConverted))
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
                                subtitle: Text(
                                  localizeServiceMessage(l10n, outcome.error!),
                                ),
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
            child: Text(l10n.close),
          ),
        ],
      );
    },
  );
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
