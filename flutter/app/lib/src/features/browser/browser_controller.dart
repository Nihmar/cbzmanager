import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../util/str_compare.dart';
import '../../vfs/vfs.dart';
import 'archive_item.dart';

/// A subdirectory of the folder currently shown, rendered as a navigable tile.
class BrowserFolder {
  const BrowserFolder({required this.name, required this.path});

  final String name;
  final String path;
}

class BrowserState {
  const BrowserState({
    this.items = const <ArchiveItem>[],
    this.folders = const <BrowserFolder>[],
    this.loading = false,
    this.error,
    this.path = '',
  });

  final List<ArchiveItem> items;

  /// Subdirectories of [path], byte-wise sorted.
  final List<BrowserFolder> folders;
  final bool loading;
  final String? error;

  /// The directory currently listed (the working directory for operations).
  final String path;

  bool get isEmpty => items.isEmpty && folders.isEmpty;
}

/// The parent of [path] while browsing inside [base], or null when [path] is
/// already the browsing root. Navigation never climbs above [base].
String? browserParentPath(String base, String path) {
  if (path.isEmpty || p.equals(path, base)) return null;
  final dir = p.dirname(path);
  if (dir == path) return null;
  if (dir == '.' || dir == '/' || dir.isEmpty) return base;
  return dir;
}

/// Lists the CBZ/CBR files and the subdirectories of a directory, byte-wise
/// sorted, and tracks the loading/error state for the browser screen.
class BrowserController extends Notifier<BrowserState> {
  @override
  BrowserState build() => const BrowserState();

  Future<void> load(Vfs vfs, String dir) async {
    // Refreshing the same directory keeps the current tiles on screen; moving
    // to another directory starts with a clean grid.
    final sameDir = dir == state.path;
    state = BrowserState(
      loading: true,
      path: dir,
      items: sameDir ? state.items : const <ArchiveItem>[],
      folders: sameDir ? state.folders : const <BrowserFolder>[],
    );
    try {
      final entries = await vfs.list(dir);
      final items = <ArchiveItem>[];
      final folders = <BrowserFolder>[];
      for (final entry in entries) {
        if (entry.isDirectory) {
          folders.add(
            BrowserFolder(name: entry.name, path: p.join(dir, entry.name)),
          );
          continue;
        }
        if (!ArchiveItem.isArchiveName(entry.name)) continue;
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
      folders.sort((a, b) => compareStr(a.name, b.name));
      state = BrowserState(items: items, folders: folders, path: dir);
    } catch (e) {
      state = BrowserState(error: e.toString(), path: dir);
    }
  }
}

final browserProvider = NotifierProvider<BrowserController, BrowserState>(
  BrowserController.new,
);
