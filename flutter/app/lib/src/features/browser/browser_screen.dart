import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../vfs/local_vfs.dart';
import '../../vfs/smb_vfs.dart';
import '../sources/smb_dialog.dart';
import '../sources/source_controller.dart';
import 'archive_item.dart';
import 'browser_controller.dart';
import 'preview_screen.dart';
import 'thumbnail_service.dart';

class BrowserScreen extends ConsumerWidget {
  const BrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(sourceProvider);
    final browser = ref.watch(browserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(source == null ? 'CBZ Manager' : source.label),
        actions: [
          if (source != null)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref
                  .read(browserProvider.notifier)
                  .load(source.vfs, source.root),
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
              if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android)
                const PopupMenuItem(value: 'local', child: Text('Open local folder')),
              const PopupMenuItem(value: 'smb', child: Text('Connect to SMB share')),
            ],
          ),
        ],
      ),
      body: source == null
          ? _Welcome(onLocal: () => _openLocal(context, ref), onSmb: () => _openSmb(context, ref))
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
    ref.read(sourceProvider.notifier).set(source);
    ref.read(browserProvider.notifier).load(source.vfs, source.root);
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
      itemBuilder: (context, index) {
        final item = browser.items[index];
        return _ArchiveTile(source: source, item: item);
      },
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PreviewScreen(vfs: source.vfs, item: item),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FutureBuilder<Uint8List?>(
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
                    return const Center(child: Icon(Icons.broken_image_outlined));
                  }
                  return Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
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
