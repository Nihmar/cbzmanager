import 'package:flutter/material.dart';

import '../../engine/merge.dart';
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
  late final _threads =
      TextEditingController(text: '${widget.defaultThreads}');

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
        chaptersPerVolume:
            _autoCpv ? 0 : (int.tryParse(_cpv.text.trim()) ?? 0),
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
    final autoCpv = calculateChaptersPerVolumeFloat(widget.files, _series);
    final plan = planMerge(widget.files, _options);
    final batches = plan.plan?.batches ?? const <MergeBatch>[];

    return AlertDialog(
      title: const Text('Merge chapters into volumes'),
      content: SizedBox(
        width: 600,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Series: $_series', style: theme.textTheme.titleMedium),
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
                            decoration:
                                const InputDecoration(labelText: 'Chapter from'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _end,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Chapter to (empty = all)',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Automatic chapters per volume'),
                      subtitle: Text(
                        autoCpv >= 1
                            ? 'Calculated: ${autoCpv.toStringAsFixed(2)}'
                            : 'No existing volumes — default '
                                '$kDefaultChaptersPerVolume',
                      ),
                      value: _autoCpv,
                      onChanged: (v) => setState(() => _autoCpv = v),
                    ),
                    if (!_autoCpv)
                      TextField(
                        controller: _cpv,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Chapters per volume'),
                        onChanged: (_) => setState(() {}),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Force remaining chapters into last volume'),
                      value: _force,
                      onChanged: (v) => setState(() => _force = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Generate ComicInfo.xml per volume'),
                      value: _comicInfo,
                      onChanged: (v) => setState(() => _comicInfo = v),
                    ),
                    const SizedBox(height: 8),
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
                            decoration: const InputDecoration(
                              labelText: 'Parallel volumes (0 = auto)',
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
                                  ? 'Custom sequence…'
                                  : 'Sequence: ${_chaptersList.join(', ')}',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Preview', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    if (batches.isEmpty)
                      Text(
                        plan.error ?? 'Nothing to merge.',
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${batches.length} volume(s) will be created',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          for (final batch in batches)
                            Text(
                              '${batch.fileName} — ${batch.files.length} '
                              'chapter(s)',
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
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: batches.isEmpty
              ? null
              : () => Navigator.of(context).pop(_options),
          icon: const Icon(Icons.merge_type),
          label: const Text('Merge'),
        ),
      ],
    );
  }
}
