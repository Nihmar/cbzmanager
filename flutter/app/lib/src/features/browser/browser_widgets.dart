import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:cbzmanager/l10n/generated/app_localizations.dart';

import '../../jobs/job_controller.dart';
import '../../jobs/job_monitor.dart';
import '../sources/source_controller.dart';
import 'archive_item.dart';
import 'browser_controller.dart';
import 'browser_operations.dart';
import 'preview_screen.dart';
import 'selection_controller.dart';
import 'thumbnail_service.dart';

/// Widgets of the browser grid: the job bar, the welcome screen, the body
/// (breadcrumbs + grid) and the folder/archive tiles.  `BrowserScreen` owns
/// the shell and composes these; keeping them out of the screen file keeps
/// both readable.

class BrowserJobBar extends ConsumerWidget {
  const BrowserJobBar({super.key, required this.job});

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

class BrowserWelcome extends StatelessWidget {
  const BrowserWelcome({super.key, required this.onLocal, required this.onSmb});

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

class BrowserBody extends ConsumerWidget {
  const BrowserBody({super.key, required this.source, required this.browser});

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
        BrowserBreadcrumbs(source: source, path: browser.path),
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
                      return FolderTile(
                        source: source,
                        folder: browser.folders[index],
                      );
                    }
                    return ArchiveTile(
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
class BrowserBreadcrumbs extends ConsumerWidget {
  const BrowserBreadcrumbs({
    super.key,
    required this.source,
    required this.path,
  });

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
class FolderTile extends ConsumerWidget {
  const FolderTile({super.key, required this.source, required this.folder});

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

class ArchiveTile extends ConsumerWidget {
  const ArchiveTile({super.key, required this.source, required this.item});

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
