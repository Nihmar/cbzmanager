import 'package:flutter/material.dart';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';

import '../../engine/merge.dart';
import '../../util/service_messages.dart';
import 'sequence_builder_dialog.dart';

/// Merge configuration dialog with a live volume preview and optional custom
/// sequence. Returns the chosen [MergeOptions], or null when cancelled.
/// [defaultThreads]/[defaultBackup] come from the persisted settings.
Future<MergeOptions?> showMergeDialog(
  BuildContext context, {
  required List<String> files,
  int defaultThreads = 0,
  bool defaultBackup = true,
}) {
  return showDialog<MergeOptions>(
    context: context,
    builder: (context) => _MergeDialog(
      files: files,
      defaultThreads: defaultThreads,
      defaultBackup: defaultBackup,
    ),
  );
}

class _MergeDialog extends StatefulWidget {
  const _MergeDialog({
    required this.files,
    this.defaultThreads = 0,
    this.defaultBackup = true,
  });

  final List<String> files;
  final int defaultThreads;
  final bool defaultBackup;

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  late String _series = detectSeriesName(widget.files);
  final _start = TextEditingController(text: '0');
  final _end = TextEditingController();
  final _cpv = TextEditingController();
  late final _threads = TextEditingController(text: '${widget.defaultThreads}');

  bool _autoCpv = true;
  bool _force = false;
  late bool _backup = widget.defaultBackup;
  bool _comicInfo = false;
  List<int> _chaptersList = const <int>[];

  @override
  void initState() {
    super.initState();
    if (_series.isEmpty || _series == 'Unknown') {
      _series = detectSeriesName(widget.files);
    }
    final auto = calculateChaptersPerVolume(widget.files, _series);
    _cpv.text = '${auto >= 1 ? auto : kDefaultChaptersPerVolume}';
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _cpv.dispose();
    _threads.dispose();
    super.dispose();
  }

  MergeOptions get _options => MergeOptions(
    seriesName: _series,
    chapterStart: int.tryParse(_start.text.trim()) ?? 0,
    chapterEnd: _end.text.trim().isEmpty
        ? 0x7fffffff
        : (int.tryParse(_end.text.trim()) ?? 0x7fffffff),
    chaptersPerVolume: _autoCpv ? 0 : (int.tryParse(_cpv.text.trim()) ?? 0),
    chaptersList: _chaptersList,
    force: _force,
    delete: !_backup,
    generateComicInfo: _comicInfo,
    threads: int.tryParse(_threads.text.trim()) ?? 0,
  );

  Future<void> _openSequenceBuilder() async {
    final chapters = collectChapters(widget.files, _series);
    if (chapters.isEmpty) return;
    final sequence = await showSequenceBuilder(
      context,
      chapters: chapters,
      lastVolume: lastVolumeNumber(widget.files, _series),
    );
    if (sequence != null) {
      setState(() => _chaptersList = sequence);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final autoCpv = calculateChaptersPerVolumeFloat(widget.files, _series);
    final plan = planMerge(widget.files, _options);
    final batches = plan.plan?.batches ?? const <MergeBatch>[];

    return AlertDialog(
      title: Text(l10n.mergeTitle),
      content: SizedBox(
        width: 600,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.seriesLabel(_series), style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _start,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: l10n.chapterFrom,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _end,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: l10n.chapterTo,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.autoCpv),
                      subtitle: Text(
                        autoCpv >= 1
                            ? l10n.calculatedCpv(autoCpv.toStringAsFixed(2))
                            : l10n.noExistingVolumesDefault(
                                kDefaultChaptersPerVolume,
                              ),
                      ),
                      value: _autoCpv,
                      onChanged: (v) => setState(() => _autoCpv = v),
                    ),
                    if (!_autoCpv)
                      TextField(
                        controller: _cpv,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.chaptersPerVolume,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.forceRemaining),
                      value: _force,
                      onChanged: (v) => setState(() => _force = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.generateComicInfoPerVolume),
                      value: _comicInfo,
                      onChanged: (v) => setState(() => _comicInfo = v),
                    ),
                    const SizedBox(height: 8),
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
                      onSelectionChanged: (s) =>
                          setState(() => _backup = s.first),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _threads,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: l10n.parallelVolumes,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openSequenceBuilder,
                            icon: const Icon(Icons.playlist_add),
                            label: Text(
                              _chaptersList.isEmpty
                                  ? l10n.customSequence
                                  : l10n.sequenceValue(
                                      _chaptersList.join(', '),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.preview, style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    if (batches.isEmpty)
                      Text(
                        plan.error != null
                            ? localizeServiceMessage(l10n, plan.error!)
                            : l10n.nothingToMerge,
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.volumesWillBeCreated(batches.length),
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          for (final batch in batches)
                            Text(
                              l10n.volumeAndChapters(
                                batch.fileName,
                                batch.files.length,
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
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
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: batches.isEmpty
              ? null
              : () => Navigator.of(context).pop(_options),
          icon: const Icon(Icons.merge_type),
          label: Text(l10n.merge),
        ),
      ],
    );
  }
}
