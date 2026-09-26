import 'package:cbzmanager/src/features/browser/browser_controller.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:cbzmanager/src/vfs/vfs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lists only archives, byte-wise sorted', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll('/lib/book2.cbz', [1]);
    await vfs.writeAll('/lib/book1.cbz', [1]);
    await vfs.writeAll('/lib/book10.cbz', [1]);
    await vfs.writeAll('/lib/notes.txt', [1]);
    await vfs.writeAll('/lib/scan.CBR', [1]);
    await vfs.mkdir('/lib/sub');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(browserProvider.notifier).load(vfs, '/lib');

    final state = container.read(browserProvider);
    expect(state.error, isNull);
    expect(
      state.items.map((e) => e.name).toList(),
      ['book1.cbz', 'book10.cbz', 'book2.cbz', 'scan.CBR'],
    );
    expect(state.items.last.isCbr, isTrue);
    // Directories are never archives: they are listed separately.
    expect(state.folders.map((e) => e.name).toList(), ['sub']);
  });

  test('lists subdirectories separately, byte-wise sorted', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll('/lib/book1.cbz', [1]);
    await vfs.mkdir('/lib/zeta');
    await vfs.mkdir('/lib/alpha');
    await vfs.mkdir('/lib/Beta');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(browserProvider.notifier).load(vfs, '/lib');

    final state = container.read(browserProvider);
    expect(
      state.folders.map((e) => e.name).toList(),
      ['Beta', 'alpha', 'zeta'],
    );
    expect(
      state.folders.map((e) => e.path).toList(),
      ['/lib/Beta', '/lib/alpha', '/lib/zeta'],
    );
    expect(state.items.map((e) => e.name).toList(), ['book1.cbz']);
    expect(state.isEmpty, isFalse);
  });

  test('an empty folder reports empty state', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll('/lib/keep.cbz', [1]);
    await vfs.mkdir('/lib/empty');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(browserProvider.notifier).load(vfs, '/lib');
    expect(container.read(browserProvider).isEmpty, isFalse);

    await container.read(browserProvider.notifier).load(vfs, '/lib/empty');
    final state = container.read(browserProvider);
    expect(state.error, isNull);
    expect(state.isEmpty, isTrue);
  });

  test('moving to another folder drops the previous tiles', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll('/lib/top.cbz', [1]);
    await vfs.mkdir('/lib/sub');
    await vfs.writeAll('/lib/sub/deep.cbz', [2]);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(browserProvider.notifier).load(vfs, '/lib');
    expect(container.read(browserProvider).items, isNotEmpty);

    await container.read(browserProvider.notifier).load(vfs, '/lib/sub');
    final state = container.read(browserProvider);
    expect(state.path, '/lib/sub');
    expect(state.folders, isEmpty);
    expect(state.items.map((e) => e.name).toList(), ['deep.cbz']);
  });

  // Regression: a slow listing (SMB) that finishes after a newer one used to
  // overwrite the grid with the previous directory's entries.
  test('a slow earlier load cannot overwrite a newer one', () async {
    final vfs = _SlowListVfs('/slow');
    await vfs.mkdir('/slow');
    await vfs.mkdir('/fast');
    await vfs.writeAll('/slow/old.cbz', [1]);
    await vfs.writeAll('/fast/new.cbz', [2]);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(browserProvider.notifier);

    final slow = notifier.load(vfs, '/slow');
    await notifier.load(vfs, '/fast');
    await slow; // the delayed listing completes last

    final state = container.read(browserProvider);
    expect(state.path, '/fast');
    expect(state.items.map((e) => e.name).toList(), ['new.cbz']);
  });

  group('browserParentPath', () {
    test('walks up inside the browsing root', () {
      expect(browserParentPath('', ''), isNull);
      expect(browserParentPath('/lib', '/lib'), isNull);
      expect(browserParentPath('/lib', '/lib/a/b'), '/lib/a');
      expect(browserParentPath('/lib', '/lib/a'), '/lib');
    });

    test('never climbs above the root', () {
      // SMB root is the share root, spelled as the empty path.
      expect(browserParentPath('', 'Manga/OnePiece'), 'Manga');
      expect(browserParentPath('', 'Manga'), '');
    });
  });

  test('surfaces a listing error', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(browserProvider.notifier)
        .load(MemoryVfs(), '/missing');

    final state = container.read(browserProvider);
    expect(state.error, isNotNull);
    expect(state.items, isEmpty);
  });
}

/// [MemoryVfs] whose [slowDir] listing is delayed past a following load.
class _SlowListVfs extends MemoryVfs {
  _SlowListVfs(this.slowDir);

  final String slowDir;

  @override
  Future<List<VfsEntry>> list(String dir) async {
    if (dir == slowDir) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return super.list(dir);
  }
}
