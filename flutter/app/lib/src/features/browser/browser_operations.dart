import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../engine/engine_provider.dart';
import '../../engine/zip_ops.dart';
import '../../jobs/job_controller.dart';
import '../../native/cbr_reader.dart';
import '../../vfs/local_vfs.dart';
import '../../vfs/smb_vfs.dart';
import '../batch_edit/batch_edit_dialog.dart';
import '../batch_edit/batch_edit_service.dart';
import '../cbr/cbr_dialog.dart';
import '../cbr/cbr_service.dart';
import '../comicinfo/comicinfo_editor_dialog.dart';
import '../comicinfo/comicinfo_service.dart';
import '../convert/convert_dialog.dart';
import '../convert/convert_service.dart';
import '../merge/merge_dialog.dart';
import '../merge/merge_service.dart';
import '../page_editor/page_edit_screen.dart';
import '../settings/settings.dart';
import '../sources/smb_dialog.dart';
import '../sources/source_controller.dart';
import '../validate/validate_results_dialog.dart';
import '../validate/validate_service.dart';
import 'archive_item.dart';
import 'browser_controller.dart';
import 'selection_controller.dart';

/// Shows a transient message.  Exposed for the browser shell and the tiles.
void snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Enters [dir] (the browsing root or a subfolder of it) and clears any
/// selection, so that a half-made selection never spans two folders.
void navigate(WidgetRef ref, ArchiveSource source, String dir) {
  ref.read(selectionProvider.notifier).clear();
  ref.read(browserProvider.notifier).load(source.vfs, dir);
}

/// Directory the single/batch operations of the browser act on.
String cwd(WidgetRef ref) => ref.read(browserProvider).path;

/// All archive operations launched from the browser shell and the tile
/// overflow menu.  Kept out of the screen so the widget file only builds UI;
/// every entry point takes the same (context, ref, source, items) shape.
class BrowserOperations {
  const BrowserOperations._();

  static Future<void> openLocal(BuildContext context, WidgetRef ref) async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    apply(
      ref,
      ArchiveSource(vfs: const LocalVfs(), root: dir, label: p.basename(dir)),
    );
  }

  static Future<void> openSmb(BuildContext context, WidgetRef ref) async {
    final config = await showSmbConnectDialog(context);
    if (config == null) return;
    apply(
      ref,
      ArchiveSource(
        vfs: SmbVfs(config),
        root: '',
        label: 'smb://${config.host}/${config.share}',
      ),
    );
  }

  static void apply(WidgetRef ref, ArchiveSource source) {
    ref.read(selectionProvider.notifier).clear();
    ref.read(sourceProvider.notifier).set(source);
    ref.read(browserProvider.notifier).load(source.vfs, source.root);
  }

  static Future<void> validate(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    List<ArchiveItem> items,
  ) async {
    final job = ref.read(jobProvider.notifier);
    job.start('Validate', message: 'Validating ${items.length} file(s)...');
    List<ValidateOutcome> outcomes;
    try {
      outcomes = await ValidateService(ref.read(cbzEngineProvider))
          .validateMany(
            source.vfs,
            items,
            onProgress: (done, total, message) =>
                job.progress(total == 0 ? 0 : done * 100 ~/ total, message),
            isCancelled: () => job.cancelRequested,
          );
    } catch (e) {
      job.finish();
      if (context.mounted) snack(context, 'Validation failed: $e');
      return;
    }
    job.finish();
    if (context.mounted) await showValidateResultsDialog(context, outcomes);
  }

  static Future<void> merge(
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
      snack(context, 'No CBZ files to merge');
      return;
    }

    final settings = ref.read(settingsProvider);
    final options = await showMergeDialog(
      context,
      files: files,
      defaultThreads: settings.mergeThreads,
      defaultBackup: settings.backupByDefault,
    );
    if (options == null || !context.mounted) return;

    final job = ref.read(jobProvider.notifier);
    final dir = cwd(ref);
    job.start('Merge', message: 'Planning...');
    try {
      final outcome = await const MergeService().merge(
        source.vfs,
        dir,
        options,
        onProgress: (percent, message) => job.progress(percent, message),
        isCancelled: () => job.cancelRequested,
      );
      job.finish();
      if (!context.mounted) return;
      if (outcome.success) {
        snack(context, 'Created ${outcome.volumesCreated} volume(s)');
        await ref.read(browserProvider.notifier).load(source.vfs, dir);
      } else {
        snack(context, outcome.error ?? 'Merge produced no volumes');
      }
    } catch (e) {
      job.finish();
      if (context.mounted) snack(context, 'Merge failed: $e');
    }
  }

  static Future<void> batchEdit(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    List<ArchiveItem> items,
  ) async {
    final editable = <ArchiveItem>[
      for (final item in items)
        if (!item.isCbr) item,
    ];
    if (editable.isEmpty) {
      snack(context, 'CBR archives are read-only — convert them first');
      return;
    }

    final previewBytes = await _firstPageBytes(source, editable.first);
    if (!context.mounted) return;

    final params = await showBatchEditDialog(
      context,
      fileCount: editable.length,
      previewBytes: previewBytes,
      defaultBackup: ref.read(settingsProvider).backupByDefault,
    );
    if (params == null || !context.mounted) return;

    final job = ref.read(jobProvider.notifier);
    job.start('Batch edit', message: 'Editing ${editable.length} file(s)...');
    try {
      final outcomes = await const BatchEditService().applyMany(
        source.vfs,
        editable,
        params,
        threads: ref.read(settingsProvider).batchThreads,
        onProgress: (percent, message) => job.progress(percent, message),
        isCancelled: () => job.cancelRequested,
      );
      job.finish();
      if (!context.mounted) return;
      final ok = outcomes.where((o) => o.success).length;
      snack(context, 'Edited $ok of ${outcomes.length} file(s)');
      await ref.read(browserProvider.notifier).load(source.vfs, cwd(ref));
    } catch (e) {
      job.finish();
      if (context.mounted) snack(context, 'Batch edit failed: $e');
    }
  }

  static Future<void> convert(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    List<ArchiveItem> items,
  ) async {
    final settings = ref.read(settingsProvider);
    final request = await showConvertOptionsDialog(
      context,
      fileCount: items.length,
      defaultThreads: settings.convertThreads,
      defaultBackup: settings.backupByDefault,
    );
    if (request == null || !context.mounted) return;

    final job = ref.read(jobProvider.notifier);
    job.start(
      'Convert to WebP',
      message: 'Converting ${items.length} file(s)...',
    );
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
      if (context.mounted) snack(context, 'Conversion failed: $e');
    }
  }

  static Future<void> convertCbr(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    List<String> names,
  ) async {
    if (names.isEmpty) {
      snack(context, 'No CBR files to convert');
      return;
    }
    if (!CbrReader.isSupported) {
      snack(context, 'CBR support requires libarchive, which is not available');
      return;
    }

    final request = await showCbrOptionsDialog(
      context,
      fileCount: names.length,
      defaultThreads: ref.read(settingsProvider).cbrThreads,
    );
    if (request == null || !context.mounted) return;

    final job = ref.read(jobProvider.notifier);
    final dir = cwd(ref);
    job.start('CBR → CBZ', message: 'Converting ${names.length} file(s)...');
    try {
      final outcomes = await const CbrConvertService().convertMany(
        source.vfs,
        dir,
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
      await ref.read(browserProvider.notifier).load(source.vfs, dir);
    } catch (e) {
      job.finish();
      if (context.mounted) snack(context, 'CBR conversion failed: $e');
    }
  }

  static Future<void> removeComicInfo(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    List<ArchiveItem> items,
  ) async {
    final job = ref.read(jobProvider.notifier);
    job.start(
      'Remove ComicInfo',
      message: 'Scanning ${items.length} file(s)...',
    );
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
        snack(
          context,
          'ComicInfo removed from ${result.changed} of ${result.scanned} '
          'file(s), ${result.skipped} already clean'
          '${result.errors.isEmpty ? '' : ', ${result.errors.length} error(s)'}',
        );
      }
    } catch (e) {
      job.finish();
      if (context.mounted) snack(context, 'Remove failed: $e');
    }
  }

  /// Opens the page editor for one archive, then refreshes the folder (the
  /// editor can rewrite the file on save).
  static Future<void> editPages(
    BuildContext context,
    WidgetRef ref,
    ArchiveSource source,
    ArchiveItem item,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PageEditScreen(
          vfs: source.vfs,
          item: item,
          backup: ref.read(settingsProvider).backupByDefault,
        ),
      ),
    );
    if (context.mounted) {
      await ref.read(browserProvider.notifier).load(source.vfs, cwd(ref));
    }
  }

  /// Opens the ComicInfo viewer/editor for one archive.
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
      snack(context, 'Cannot read ${item.name}: ${read.error}');
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
        snack(context, 'ComicInfo saved for ${item.name}');
      }
    } catch (e) {
      if (context.mounted) snack(context, 'Save failed: $e');
    } finally {
      job.finish();
    }
  }

  static Future<Uint8List?> _firstPageBytes(
    ArchiveSource source,
    ArchiveItem item,
  ) async {
    try {
      final bytes = await source.vfs.readAll(item.path);
      final names = sortedImageNamesInZip(bytes);
      if (names.isEmpty) return null;
      return readZipEntryByName(bytes, names.first);
    } catch (_) {
      return null;
    }
  }
}
