import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../engine/engine_provider.dart';
import '../../jobs/job_controller.dart';
import '../../native/cbr_reader.dart';
import '../../vfs/local_vfs.dart';
import '../../vfs/smb_vfs.dart';
import '../cbr/cbr_dialog.dart';
import '../cbr/cbr_service.dart';
import '../comicinfo/comicinfo_editor_dialog.dart';
import '../comicinfo/comicinfo_service.dart';
import '../convert/convert_dialog.dart';
import '../convert/convert_service.dart';
import '../merge/merge_dialog.dart';
import '../merge/merge_service.dart';
import '../sources/smb_dialog.dart';
import '../sources/source_controller.dart';
import '../validate/validate_results_dialog.dart';
import '../validate/validate_service.dart';
import 'archive_item.dart';
import 'browser_controller.dart';
import 'preview_screen.dart';
import 'selection_controller.dart';
import 'thumbnail_service.dart';

class BrowserScreen extends ConsumerWidget {
  const BrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(sourceProvider);
    final browser = ref.watch(browserProvider);
    final selection = ref.watch(selectionProvider);
    final job = ref.watch(jobProvider);
    final selecting = selection.isNotEmpty;
    final selectedItems =
        browser.items.where((i) => selection.contains(i.path)).toList();

    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                tooltip: 'Cancel selection',
                icon: const Icon(Icons.close),
                onPressed: () => ref.read(selectionProvider.notifier).clear(),
              )
            : null,
        title: Text(
          selecting ? '${selection.length} selected' : (source?.label ?? 'CBZ Manager'),
        ),
        actions: selecting
            ? [
                IconButton(
                  tooltip: 'Validate',
                  icon: const Icon(Icons.fact_check_outlined),
                  onPressed: job?.running == true || source == null
                      ? null
                      : () => _validate(context, ref, source, selectedItems),
                ),
                IconButton(
                  tooltip: 'Convert to WebP',
                  icon: const Icon(Icons.transform),
                  onPressed: job?.running == true || source == null
                      ? null
                      : () => _convert(context, ref, source, selectedItems),
                ),
                IconButton(
                  tooltip: 'Remove ComicInfo',
                  icon: const Icon(Icons.bookmark_remove_outlined),
                  onPressed: job?.running == true || source == null
                      ? null
                      : () => _removeComicInfo(context, ref, source, selectedItems),
                ),
                IconButton(
                  tooltip: 'Select all',
                  icon: const Icon(Icons.select_all),
                  onPressed: () => ref
                      .read(selectionProvider.notifier)
                      .select(browser.items.map((i) => i.path)),
                ),
              ]
            : [
                if (source != null)
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                    onPressed: job?.running == true
                        ? null
                        : () => ref
                            .read(browserProvider.notifier)
                            .load(source.vfs, source.root),
                  ),
                if (source != null && browser.items.isNotEmpty)
                  IconButton(
                    tooltip: 'Select',
                    icon: const Icon(Icons.checklist),
                    onPressed: () => ref
                        .read(selectionProvider.notifier)
                        .select(browser.items.map((i) => i.path)),
                  ),
                if (source != null && browser.items.isNotEmpty)
                  IconButton(
                    tooltip: 'Merge chapters',
                    icon: const Icon(Icons.merge_type),
                    onPressed: job?.running == true
                        ? null
                        : () => _merge(context, ref, source, browser.items),
                  ),
                if (source != null && browser.items.any((i) => i.isCbr))
                  IconButton(
                    tooltip: 'Convert CBR to CBZ',
                    icon: const Icon(Icons.swap_horiz),
                    onPressed: job?.running == true
                        ? null
                        : () => _convertCbr(
                              context,
                              ref,
                              source,
                              [
                                for (final i in browser.items)
                                  if (i.isCbr) i.name,
                              ],
                            ),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Open source',
                  onSelected: (value) {
                    if (value == 'local') {
                      _openLocal(context, ref);
                    } else {
                      _openSmb(context, ref);
                    }
                  },
                  itemBuilder: (context) => [
                    if (!kIsWeb &&
                        defaultTargetPlatform != TargetPlatform.android)
                      const PopupMenuItem(
                        value: 'local',
                        child: Text('Open local folder'),
                      ),
                    const PopupMenuItem(
                      value: 'smb',
                      child: Text('Connect to SMB share'),
                    ),
                  ],
                ),
              ],
        bottom: job == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: _JobBar(job: job),
              ),
      ),
      body: source == null
          ? _Welcome(
              onLocal: () => _openLocal(context, ref),
              onSmb: () => _openSmb(context, ref),
            )
          : _BrowserBody(source: source, browser: browser),
    );
  }

  Future<void> _openLocal(BuildContext context, WidgetRef ref) async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    _apply(
      ref,
      ArchiveSource(vfs: const LocalVfs(), root: dir, label: p.basename(dir)),
    );
  }

  Future<void> _openSmb(BuildContext context, WidgetRef ref) async {
    final config = await showSmbConnectDialog(context);
    if (config == null) return;
    _apply(
      ref,
      ArchiveSource(
        vfs: SmbVfs(config),
        root: '',
        label: 'smb://${config.host}/${config.share}',
      ),
    );
  }

  void _apply(WidgetRef ref, ArchiveSource source) {
    ref.read(selectionProvider.notifier).clear();
    ref.read(sourceProvider.notifier).set(source);
    ref.read(browserProvider.notifier).load(source.vfs, source.root);
  }

  Future<void> _validate(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    List<ArchiveItem> items,
  ) async {
    final job = ref.read(jobProvider.notifier);
    job.start('Validate', message: 'Validating ${items.length} file(s)...');
    List<ValidateOutcome> outcomes;
    try {
      outcomes = await ValidateService(ref.read(cbzEngineProvider)).validateMany(
        source.vfs,
        items,
        onProgress: (done, total, message) =>
            job.progress(total == 0 ? 0 : done * 100 ~/ total, message),
        isCancelled: () => job.cancelRequested,
      );
    } catch (e) {
      job.finish();
      if (context.mounted) _snack(context, 'Validation failed: $e');
      return;
    }
    job.finish();
    if (context.mounted) await showValidateResultsDialog(context, outcomes);
  }

  Future<void> _merge(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    List<ArchiveItem> items,
  ) async {
    final files = <String>[
      for (final item in items)
        if (item.name.toLowerCase().endsWith('.cbz')) item.name,
    ];
    if (files.isEmpty) {
      _snack(context, 'No CBZ files to merge');
      return;
    }

    final options = await showMergeDialog(context, files: files);
    if (options == null || !context.mounted) return;

    final job = ref.read(jobProvider.notifier);
    job.start('Merge', message: 'Planning...');
    try {
      final outcome = await const MergeService().merge(
        source.vfs,
        source.root,
        options,
        onProgress: (percent, message) => job.progress(percent, message),
        isCancelled: () => job.cancelRequested,
      );
      job.finish();
      if (!context.mounted) return;
      if (outcome.success) {
        _snack(context, 'Created ${outcome.volumesCreated} volume(s)');
        await ref
            .read(browserProvider.notifier)
            .load(source.vfs, source.root);
      } else {
        _snack(context, outcome.error ?? 'Merge produced no volumes');
      }
    } catch (e) {
      job.finish();
      if (context.mounted) _snack(context, 'Merge failed: $e');
    }
  }

  Future<void> _convert(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    List<ArchiveItem> items,
  ) async {
    final request = await showConvertOptionsDialog(
      context,
      fileCount: items.length,
    );
    if (request == null || !context.mounted) return;

    final job = ref.read(jobProvider.notifier);
    job.start('Convert to WebP', message: 'Converting ${items.length} file(s)...');
    try {
      final outcomes = await const ConvertService().convertMany(
        source.vfs,
        items,
        backup: request.backup,
        threads: request.threads,
        onProgress: (done, total, message) =>
            job.progress(total == 0 ? 0 : done * 100 ~/ total, message),
        isCancelled: () => job.cancelRequested,
      );
      job.finish();
      if (context.mounted) await showConvertResultsDialog(context, outcomes);
    } catch (e) {
      job.finish();
      if (context.mounted) _snack(context, 'Conversion failed: $e');
    }
  }

  Future<void> _convertCbr(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    List<String> names,
  ) async {
    if (names.isEmpty) {
      _snack(context, 'No CBR files to convert');
      return;
    }
    if (!CbrReader.isSupported) {
      _snack(context, 'CBR support requires libarchive, which is not available');
      return;
    }

    final request = await showCbrOptionsDialog(
      context,
      fileCount: names.length,
    );
    if (request == null || !context.mounted) return;

    final job = ref.read(jobProvider.notifier);
    job.start('CBR → CBZ', message: 'Converting ${names.length} file(s)...');
    try {
      final outcomes = await const CbrConvertService().convertMany(
        source.vfs,
        source.root,
        names,
        skipExisting: request.skipExisting,
        deleteSource: request.deleteSource,
        threads: request.threads,
        onProgress: (percent, message) => job.progress(percent, message),
        isCancelled: () => job.cancelRequested,
      );
      job.finish();
      if (!context.mounted) return;
      await showCbrResultsDialog(context, outcomes);
      await ref.read(browserProvider.notifier).load(source.vfs, source.root);
    } catch (e) {
      job.finish();
      if (context.mounted) _snack(context, 'CBR conversion failed: $e');
    }
  }

  Future<void> _removeComicInfo(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    List<ArchiveItem> items,
  ) async {
    final job = ref.read(jobProvider.notifier);
    job.start('Remove ComicInfo', message: 'Scanning ${items.length} file(s)...');
    try {
      final result = await ComicInfoService(ref.read(cbzEngineProvider))
          .removeMany(
        source.vfs,
        items,
        onProgress: (done, total, message) =>
            job.progress(total == 0 ? 0 : done * 100 ~/ total, message),
        isCancelled: () => job.cancelRequested,
      );
      job.finish();
      if (context.mounted) {
        _snack(
          context,
          'ComicInfo removed from ${result.changed} of ${result.scanned} '
          'file(s), ${result.skipped} already clean'
          '${result.errors.isEmpty ? '' : ', ${result.errors.length} error(s)'}',
        );
      }
    } catch (e) {
      job.finish();
      if (context.mounted) _snack(context, 'Remove failed: $e');
    }
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class _JobBar extends ConsumerWidget {
  const _JobBar({required this.job});

  final JobState job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: job.percent <= 0 ? null : job.percent / 100.0,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${job.label}: ${job.message}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              TextButton(
                onPressed: job.cancelled
                    ? null
                    : () => ref.read(jobProvider.notifier).requestCancel(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onLocal, required this.onSmb});

  final VoidCallback onLocal;
  final VoidCallback onSmb;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories, size: 64),
            const SizedBox(height: 16),
            Text(
              'Open a comics folder',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a local folder or connect to an SMB share.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              children: [
                if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android)
                  FilledButton.icon(
                    onPressed: onLocal,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Local folder'),
                  ),
                OutlinedButton.icon(
                  onPressed: onSmb,
                  icon: const Icon(Icons.lan),
                  label: const Text('SMB share'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserBody extends ConsumerWidget {
  const _BrowserBody({required this.source, required this.browser});

  final ArchiveSource source;
  final BrowserState browser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (browser.loading && browser.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (browser.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(browser.error!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (browser.items.isEmpty) {
      return const Center(child: Text('No CBZ/CBR files in this folder'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.62,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: browser.items.length,
      itemBuilder: (context, index) =>
          _ArchiveTile(source: source, item: browser.items[index]),
    );
  }
}

class _ArchiveTile extends ConsumerWidget {
  const _ArchiveTile({required this.source, required this.item});

  final ArchiveSource source;
  final ArchiveItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnails = ref.read(thumbnailServiceProvider);
    final selected = ref.watch(selectionProvider).contains(item.path);
    final selecting = ref.watch(selectionProvider).isNotEmpty;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: selected ? scheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? scheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (selecting) {
            ref.read(selectionProvider.notifier).toggle(item.path);
          } else {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PreviewScreen(vfs: source.vfs, item: item),
              ),
            );
          }
        },
        onLongPress: () => ref.read(selectionProvider.notifier).toggle(item.path),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: thumbnails.archiveThumbnail(source.vfs, item),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final bytes = snapshot.data;
                      if (bytes == null) {
                        return const Center(
                          child: Icon(Icons.broken_image_outlined),
                        );
                      }
                      return Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      );
                    },
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Icon(Icons.check_circle, color: scheme.primary),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 0, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '${item.isCbr ? 'CBR' : 'CBZ'} · ${_size(item.size)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  if (!selecting)
                    PopupMenuButton<String>(
                      tooltip: 'Actions',
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      onSelected: (value) async {
                        switch (value) {
                          case 'validate':
                            await _BrowserActions.validate(
                              context,
                              ref,
                              source,
                              item,
                            );
                          case 'convert':
                            await _BrowserActions.convert(
                              context,
                              ref,
                              source,
                              item,
                            );
                          case 'cbr':
                            await _BrowserActions.cbrToCbz(
                              context,
                              ref,
                              source,
                              item,
                            );
                          case 'comicinfo':
                            await _BrowserActions.editComicInfo(
                              context,
                              ref,
                              source,
                              item,
                            );
                          case 'remove':
                            await _BrowserActions.removeComicInfo(
                              context,
                              ref,
                              source,
                              item,
                            );
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'validate',
                          child: Text('Validate'),
                        ),
                        const PopupMenuItem(
                          value: 'convert',
                          child: Text('Convert to WebP'),
                        ),
                        if (item.isCbr)
                          const PopupMenuItem(
                            value: 'cbr',
                            child: Text('Convert to CBZ'),
                          ),
                        const PopupMenuItem(
                          value: 'comicinfo',
                          child: Text('Edit ComicInfo…'),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove ComicInfo'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Shared single-item actions used by the tile overflow menu.
class _BrowserActions {
  const _BrowserActions._();

  static Future<void> validate(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    ArchiveItem item,
  ) async {
    final job = ref.read(jobProvider.notifier);
    job.start('Validate', message: 'Validating ${item.name}');
    final outcomes =
        await ValidateService(ref.read(cbzEngineProvider)).validateMany(
      source.vfs,
      [item],
      onProgress: (done, total, message) =>
          job.progress(total == 0 ? 0 : done * 100 ~/ total, message),
      isCancelled: () => job.cancelRequested,
    );
    job.finish();
    if (context.mounted) await showValidateResultsDialog(context, outcomes);
  }

  static Future<void> convert(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    ArchiveItem item,
  ) async {
    final request = await showConvertOptionsDialog(context, fileCount: 1);
    if (request == null || !context.mounted) return;
    final job = ref.read(jobProvider.notifier);
    job.start('Convert to WebP', message: item.name);
    try {
      final outcomes = await const ConvertService().convertMany(
        source.vfs,
        [item],
        backup: request.backup,
        threads: request.threads,
      );
      job.finish();
      if (context.mounted) await showConvertResultsDialog(context, outcomes);
    } catch (e) {
      job.finish();
      if (context.mounted) _snack(context, 'Conversion failed: $e');
    }
  }

  static Future<void> cbrToCbz(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    ArchiveItem item,
  ) async {
    final request = await showCbrOptionsDialog(context, fileCount: 1);
    if (request == null || !context.mounted) return;
    final job = ref.read(jobProvider.notifier);
    job.start('CBR → CBZ', message: item.name);
    try {
      final outcomes = await const CbrConvertService().convertMany(
        source.vfs,
        source.root,
        [item.name],
        skipExisting: request.skipExisting,
        deleteSource: request.deleteSource,
        threads: request.threads,
      );
      job.finish();
      if (context.mounted) await showCbrResultsDialog(context, outcomes);
    } catch (e) {
      job.finish();
      if (context.mounted) _snack(context, 'CBR conversion failed: $e');
    }
  }

  static Future<void> editComicInfo(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    ArchiveItem item,
  ) async {
    final service = ComicInfoService(ref.read(cbzEngineProvider));
    final job = ref.read(jobProvider.notifier);
    job.start('ComicInfo', message: 'Reading ${item.name}');
    final read = await service.read(source.vfs, item);
    job.finish();
    if (!context.mounted) return;
    if (read.error != null) {
      _snack(context, 'Cannot read ${item.name}: ${read.error}');
      return;
    }
    final edited = await showComicInfoEditor(
      context,
      archiveName: item.name,
      initial: read.info,
    );
    if (edited == null || !context.mounted) return;
    job.start('ComicInfo', message: 'Saving ${item.name}');
    try {
      await service.write(source.vfs, item, edited);
      if (context.mounted) {
        _snack(context, 'ComicInfo saved for ${item.name}');
      }
    } catch (e) {
      if (context.mounted) _snack(context, 'Save failed: $e');
    } finally {
      job.finish();
    }
  }

  static Future<void> removeComicInfo(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    ArchiveItem item,
  ) async {
    final job = ref.read(jobProvider.notifier);
    job.start('Remove ComicInfo', message: item.name);
    try {
      final removed = await ComicInfoService(ref.read(cbzEngineProvider))
          .remove(source.vfs, item);
      if (context.mounted) {
        _snack(
          context,
          removed
              ? 'ComicInfo removed from ${item.name}'
              : '${item.name} has no ComicInfo.xml',
        );
      }
    } catch (e) {
      if (context.mounted) _snack(context, 'Remove failed: $e');
    } finally {
      job.finish();
    }
  }
}
