import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:cbzmanager/l10n/generated/app_localizations.dart';

import '../../jobs/job_controller.dart';
import '../../jobs/job_monitor.dart';
import '../settings/settings_dialog.dart';
import '../sources/source_controller.dart';
import 'archive_item.dart';
import 'browser_controller.dart';
import 'browser_operations.dart';
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
    final l10n = AppLocalizations.of(context);
    final selecting = selection.isNotEmpty;
    final selectedItems = browser.items
        .where((i) => selection.contains(i.path))
        .toList();
    final up = source == null
        ? null
        : browserParentPath(source.root, browser.path);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
            BrowserOperations.openLocal(context, ref),
        const SingleActivator(
          LogicalKeyboardKey.keyO,
          control: true,
          shift: true,
        ): () =>
            BrowserOperations.openSmb(context, ref),
        const SingleActivator(LogicalKeyboardKey.f5): () {
          final current = ref.read(sourceProvider);
          if (current != null) {
            final dir = ref.read(browserProvider).path;
            ref.read(browserProvider.notifier).load(current.vfs, dir);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => ref
            .read(selectionProvider.notifier)
            .select(ref.read(browserProvider).items.map((i) => i.path)),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            ref.read(selectionProvider.notifier).clear(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: selecting
                ? IconButton(
                    tooltip: 'Cancel selection',
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        ref.read(selectionProvider.notifier).clear(),
                  )
                : up == null
                ? null
                : IconButton(
                    tooltip: 'Up',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => navigate(ref, source!, up),
                  ),
            title: Text(
              selecting
                  ? '${selection.length} selected'
                  : (source?.label ?? l10n.appTitle),
            ),
            actions: selecting
                ? [
                    IconButton(
                      tooltip: 'Validate',
                      icon: const Icon(Icons.fact_check_outlined),
                      onPressed: job?.running == true || source == null
                          ? null
                          : () => BrowserOperations.validate(
                              context,
                              ref,
                              source,
                              selectedItems,
                            ),
                    ),
                    IconButton(
                      tooltip: 'Convert to WebP',
                      icon: const Icon(Icons.transform),
                      onPressed: job?.running == true || source == null
                          ? null
                          : () => BrowserOperations.convert(
                              context,
                              ref,
                              source,
                              selectedItems,
                            ),
                    ),
                    IconButton(
                      tooltip: 'Batch edit pages',
                      icon: const Icon(Icons.tune),
                      onPressed: job?.running == true || source == null
                          ? null
                          : () => BrowserOperations.batchEdit(
                              context,
                              ref,
                              source,
                              selectedItems,
                            ),
                    ),
                    IconButton(
                      tooltip: 'Remove ComicInfo',
                      icon: const Icon(Icons.bookmark_remove_outlined),
                      onPressed: job?.running == true || source == null
                          ? null
                          : () => BrowserOperations.removeComicInfo(
                              context,
                              ref,
                              source,
                              selectedItems,
                            ),
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
                                  .load(source.vfs, browser.path),
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
                            : () => BrowserOperations.merge(
                                context,
                                ref,
                                source,
                                browser.items,
                              ),
                      ),
                    if (source != null && browser.items.any((i) => i.isCbr))
                      IconButton(
                        tooltip: 'Convert CBR to CBZ',
                        icon: const Icon(Icons.swap_horiz),
                        onPressed: job?.running == true
                            ? null
                            : () => BrowserOperations.convertCbr(
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
                          BrowserOperations.openLocal(context, ref);
                        } else {
                          BrowserOperations.openSmb(context, ref);
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
                    IconButton(
                      tooltip: l10n.settings,
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => showSettingsDialog(context),
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
                  onLocal: () => BrowserOperations.openLocal(context, ref),
                  onSmb: () => BrowserOperations.openSmb(context, ref),
                )
              : PopScope(
                  // System back climbs out of a subfolder before leaving the app.
                  canPop: up == null,
                  onPopInvokedWithResult: (didPop, _) {
                    if (didPop || up == null) return;
                    navigate(ref, source, up);
                  },
                  child: _BrowserBody(source: source, browser: browser),
                ),
        ),
      ),
    );
  }
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
                onPressed: () => showJobMonitor(context),
                child: const Text('Details'),
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
    final l10n = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories, size: 64),
            const SizedBox(height: 16),
            Text(
              l10n.welcomeTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(l10n.welcomeSubtitle, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              children: [
                if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android)
                  FilledButton.icon(
                    onPressed: onLocal,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.localFolder),
                  ),
                OutlinedButton.icon(
                  onPressed: onSmb,
                  icon: const Icon(Icons.lan),
                  label: Text(l10n.smbShare),
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
    if (browser.loading && browser.isEmpty) {
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

    return Column(
      children: [
        _Breadcrumbs(source: source, path: browser.path),
        Expanded(
          child: browser.isEmpty
              ? Center(child: Text(AppLocalizations.of(context).noArchives))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 0.62,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: browser.folders.length + browser.items.length,
                  itemBuilder: (context, index) {
                    // Folders come first, then the archives of this folder.
                    if (index < browser.folders.length) {
                      return _FolderTile(
                        source: source,
                        folder: browser.folders[index],
                      );
                    }
                    return _ArchiveTile(
                      source: source,
                      item: browser.items[index - browser.folders.length],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Trail from the browsing root to the current folder; hidden at the root,
/// where the app bar already names the source.
class _Breadcrumbs extends ConsumerWidget {
  const _Breadcrumbs({required this.source, required this.path});

  final ArchiveSource source;
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = source.root;
    final relative = base.isEmpty ? path : p.relative(path, from: base);
    if (relative.isEmpty || relative == '.') return const SizedBox.shrink();

    final crumbs = <({String label, String path})>[
      (label: source.label, path: base),
    ];
    var current = base;
    for (final segment in p.split(relative)) {
      current = p.join(current, segment);
      crumbs.add((label: segment, path: current));
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: crumbs.length,
        separatorBuilder: (_, _) => const Icon(Icons.chevron_right, size: 16),
        itemBuilder: (context, index) {
          final crumb = crumbs[index];
          final last = index == crumbs.length - 1;
          return TextButton(
            onPressed: last ? null : () => navigate(ref, source, crumb.path),
            child: Text(
              crumb.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }
}

/// A subdirectory of the current folder.
class _FolderTile extends ConsumerWidget {
  const _FolderTile({required this.source, required this.folder});

  final ArchiveSource source;
  final BrowserFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => navigate(ref, source, folder.path),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder, size: 48, color: scheme.primary),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                folder.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
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
        onLongPress: () =>
            ref.read(selectionProvider.notifier).toggle(item.path),
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
                            await BrowserOperations.validate(
                              context,
                              ref,
                              source,
                              [item],
                            );
                          case 'convert':
                            await BrowserOperations.convert(
                              context,
                              ref,
                              source,
                              [item],
                            );
                          case 'cbr':
                            await BrowserOperations.convertCbr(
                              context,
                              ref,
                              source,
                              [item.name],
                            );
                          case 'pages':
                            await BrowserOperations.editPages(
                              context,
                              ref,
                              source,
                              item,
                            );
                          case 'comicinfo':
                            await BrowserOperations.editComicInfo(
                              context,
                              ref,
                              source,
                              item,
                            );
                          case 'remove':
                            await BrowserOperations.removeComicInfo(
                              context,
                              ref,
                              source,
                              [item],
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
                        if (!item.isCbr)
                          const PopupMenuItem(
                            value: 'pages',
                            child: Text('Edit pages…'),
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
