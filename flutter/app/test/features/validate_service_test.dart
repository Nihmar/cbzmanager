import 'dart:async';

import 'package:cbzmanager/src/engine/dart_engine.dart';
import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/features/validate/validate_service.dart';
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

    final outcomes = await service.validateMany(vfs, [
      item('good.cbz'),
      item('bad.cbz'),
    ]);

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
    final outcomes = await service.validateMany(vfs, [
      item('a.cbz'),
      item('b.cbz'),
    ], isCancelled: () => true);
    expect(outcomes, isEmpty);
  });

  test('reports per-page errors of undecodable entries', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      'mixed.cbz',
      makeZip({
        'page_001.png': makeSolidPng(8, 8),
        'page_002.png': [1, 2, 3, 4],
      }),
    );

    final outcomes = await service.validateMany(vfs, [item('mixed.cbz')]);
    final result = outcomes.single.result;
    expect(result.valid, isFalse);
    expect(result.imageCount, 2);
    expect(result.errors.single.page, 'page_002.png');
    expect(result.errors.single.message, isNotEmpty);
  });

  test('outcomes are identical for any thread count', () async {
    final vfs = MemoryVfs();
    for (final name in ['b.cbz', 'a.cbz', 'c.cbz']) {
      await vfs.writeAll(name, makeZip({'p.png': makeSolidPng(4, 4)}));
    }
    await vfs.writeAll('bad.cbz', [1, 2, 3]);
    final items = [
      item('b.cbz'),
      item('bad.cbz'),
      item('a.cbz'),
      item('c.cbz'),
    ];

    final serial = await service.validateMany(vfs, items, threads: 1);
    final parallel = await service.validateMany(vfs, items, threads: 4);

    expect(
      parallel.map((o) => '${o.item.name}:${o.result.valid}').toList(),
      serial.map((o) => '${o.item.name}:${o.result.valid}').toList(),
    );
  });

  // Regression: validation used to decode every page on the UI isolate, which
  // froze the app. A pending timer can only run if the main isolate is handed
  // back to the event loop, which now happens while the isolate works.
  test('leaves the UI isolate free to run timers', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      'big.cbz',
      makeZip({
        for (var i = 0; i < 6; i++) 'page_00$i.png': makeNoisePng(300, 300, i),
      }),
    );

    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks++,
    );
    addTearDown(timer.cancel);

    final outcomes = await service.validateMany(vfs, [item('big.cbz')]);

    expect(outcomes.single.result.valid, isTrue);
    expect(ticks, greaterThan(0));
  });
}
