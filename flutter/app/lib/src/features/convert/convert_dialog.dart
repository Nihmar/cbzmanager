import 'package:flutter/material.dart';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';

import '../../util/service_messages.dart';
import '../settings/settings.dart';
import 'convert_service.dart';

/// Options chosen in the convert dialog.
class ConvertRequest {
  const ConvertRequest({
    required this.backup,
    required this.threads,
    required this.quality,
    required this.onlyIfSmaller,
    required this.skipExistingWebp,
    required this.removeComicInfo,
    required this.renumber,
  });

  final bool backup;
  final int threads;
  final int quality;
  final bool onlyIfSmaller;
  final bool skipExistingWebp;
  final bool removeComicInfo;
  final bool renumber;
}

/// Asks how to convert: keep an `_OLD` backup or delete the originals, how
/// many files to convert in parallel and the reference's conversion options
/// (quality, only-if-smaller, skip existing WebP, ComicInfo, renumber).
/// [defaults] comes from the persisted settings.
Future<ConvertRequest?> showConvertOptionsDialog(
  BuildContext context, {
  required int fileCount,
  required AppSettings defaults,
}) {
  return showDialog<ConvertRequest>(
    context: context,
    builder: (context) =>
        _ConvertOptionsDialog(fileCount: fileCount, defaults: defaults),
  );
}

class _ConvertOptionsDialog extends StatefulWidget {
  const _ConvertOptionsDialog({
    required this.fileCount,
    required this.defaults,
  });

  final int fileCount;
  final AppSettings defaults;

  @override
  State<_ConvertOptionsDialog> createState() => _ConvertOptionsDialogState();
}

class _ConvertOptionsDialogState extends State<_ConvertOptionsDialog> {
  late bool _backup = widget.defaults.backupByDefault;
  late int _quality = widget.defaults.convertQuality;
  late bool _onlyIfSmaller = widget.defaults.convertOnlyIfSmaller;
  late bool _skipExistingWebp = widget.defaults.convertSkipExistingWebp;
  late bool _removeComicInfo = widget.defaults.convertRemoveComicInfo;
  late bool _renumber = widget.defaults.convertRenumber;
  late final _threads = TextEditingController(
    text: '${widget.defaults.convertThreads}',
  );

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
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.convertSummary(widget.fileCount, _quality),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(l10n.convertQuality),
                  Expanded(
                    child: Slider(
                      value: _quality.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      label: '$_quality%',
                      onChanged: (v) => setState(() => _quality = v.round()),
                    ),
                  ),
                  Text('$_quality%'),
                ],
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.convertOnlyIfSmaller),
                value: _onlyIfSmaller,
                onChanged: (v) => setState(() => _onlyIfSmaller = v ?? true),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.convertSkipExistingWebp),
                value: _skipExistingWebp,
                onChanged: (v) => setState(() => _skipExistingWebp = v ?? true),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.convertKeepComicInfo),
                value: !_removeComicInfo,
                onChanged: (v) =>
                    setState(() => _removeComicInfo = !(v ?? false)),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.renumberPages),
                value: _renumber,
                onChanged: (v) => setState(() => _renumber = v ?? true),
              ),
              const Divider(),
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
                quality: _quality,
                onlyIfSmaller: _onlyIfSmaller,
                skipExistingWebp: _skipExistingWebp,
                removeComicInfo: _removeComicInfo,
                renumber: _renumber,
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
  final skipped = outcomes.where((o) => o.skipped).length;
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
                  if (skipped > 0)
                    Chip(label: Text(l10n.skippedCount(skipped))),
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
