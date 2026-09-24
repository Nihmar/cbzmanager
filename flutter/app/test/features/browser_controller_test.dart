import 'package:cbzmanager/src/features/browser/browser_controller.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
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
