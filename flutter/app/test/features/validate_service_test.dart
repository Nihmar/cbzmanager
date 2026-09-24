import 'package:cbzmanager/src/features/validate/validate_service.dart';
import 'package:cbzmanager/src/engine/dart_engine.dart';
import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  const service = ValidateService(DartCbzEngine());

  ArchiveItem item(String name) =>
      ArchiveItem(name: name, path: name, size: 0, isCbr: false);

  test('validates each archive, never aborting on a bad one', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      'good.cbz',
      makeZip({'page_001.png': makeSolidPng(8, 8)}),
    );
    await vfs.writeAll('bad.cbz', [1, 2, 3, 4]);

    final outcomes = await service.validateMany(
      vfs,
      [item('good.cbz'), item('bad.cbz')],
    );

    expect(outcomes.length, 2);
    expect(outcomes[0].result.valid, isTrue);
    expect(outcomes[1].result.valid, isFalse);
  });

  test('reports progress ending at 100 percent', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll('a.cbz', makeZip({'p.png': makeSolidPng(4, 4)}));
    final percentages = <int>[];
    await service.validateMany(
      vfs,
      [item('a.cbz')],
      onProgress: (done, total, _) =>
          percentages.add(total == 0 ? 0 : done * 100 ~/ total),
    );
    expect(percentages.last, 100);
  });

  test('honours cancellation', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll('a.cbz', makeZip({'p.png': makeSolidPng(4, 4)}));
    final outcomes = await service.validateMany(
      vfs,
      [item('a.cbz'), item('b.cbz')],
      isCancelled: () => true,
    );
    expect(outcomes, isEmpty);
  });
}
