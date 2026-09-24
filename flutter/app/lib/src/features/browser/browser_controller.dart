import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../util/str_compare.dart';
import '../../vfs/vfs.dart';
import 'archive_item.dart';

class BrowserState {
  const BrowserState({
    this.items = const <ArchiveItem>[],
    this.loading = false,
    this.error,
    this.path = '',
  });

  final List<ArchiveItem> items;
  final bool loading;
  final String? error;
  final String path;
}

/// Lists the CBZ/CBR files of a directory, byte-wise sorted, and tracks the
/// loading/error state for the browser screen.
class BrowserController extends Notifier<BrowserState> {
  @override
  BrowserState build() => const BrowserState();

  Future<void> load(Vfs vfs, String dir) async {
    state = BrowserState(loading: true, path: dir, items: state.items);
    try {
      final entries = await vfs.list(dir);
      final items = <ArchiveItem>[];
      for (final entry in entries) {
        if (entry.isDirectory || !ArchiveItem.isArchiveName(entry.name)) {
          continue;
        }
        items.add(
          ArchiveItem(
            name: entry.name,
            path: p.join(dir, entry.name),
            size: entry.size,
            isCbr: entry.name.toLowerCase().endsWith('.cbr'),
          ),
        );
      }
      items.sort((a, b) => compareStr(a.name, b.name));
      state = BrowserState(items: items, path: dir);
    } catch (e) {
      state = BrowserState(error: e.toString(), path: dir);
    }
  }
}

final browserProvider = NotifierProvider<BrowserController, BrowserState>(
  BrowserController.new,
);
