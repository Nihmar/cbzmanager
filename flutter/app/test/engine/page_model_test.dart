import 'dart:convert';

import 'package:cbzmanager/src/engine/page_model.dart';
import 'package:cbzmanager/src/engine/zip_ops.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

PageState page(String name, [int index = -1]) =>
    PageState(origName: name, name: name, origIndex: index);

void main() {
  test('delete removes and logs a change', () {
    final model = PageEditModel([page('a.png'), page('b.png')]);
    model.deleteAt(0);
    expect(model.pages.single.name, 'b.png');
    expect(model.changes.single.kind, PageChangeKind.deleted);
  });

  test('move reorders and logs', () {
    final model = PageEditModel([page('a.png'), page('b.png'), page('c.png')]);
    model.move(2, 0);
    expect(model.pages.map((p) => p.name).toList(), [
      'c.png',
      'a.png',
      'b.png',
    ]);
    expect(model.changes.single.kind, PageChangeKind.moved);
  });

  test('insertAt adds pages and logs each', () {
    final model = PageEditModel([page('a.png')]);
    model.insertAt(1, [page('new1.png'), page('new2.png')]);
    expect(model.pages.length, 3);
    expect(model.changes.length, 2);
    expect(
      model.changes.every((c) => c.kind == PageChangeKind.inserted),
      isTrue,
    );
  });

  test('renumber uses 4-digit page names', () {
    final model = PageEditModel([page('a.png'), page('b.png')]);
    expect(model.renumber(), 2);
    expect(model.pages.map((p) => p.name).toList(), [
      'page_0001.png',
      'page_0002.png',
    ]);
  });

  test('revert restores the baseline', () {
    final model = PageEditModel([page('a.png'), page('b.png')]);
    model.deleteAt(0);
    model.renumber();
    expect(model.hasChanges, isTrue);
    model.revert();
    expect(model.pages.map((p) => p.name).toList(), ['a.png', 'b.png']);
    expect(model.hasChanges, isFalse);
  });

  test('buildEditedArchive filters gone, renumbers and preserves metadata', () {
    final original = collectZipEntries(
      makeZip({
        'page_001.png': makeSolidPng(4, 4),
        'page_002.png': makeSolidPng(4, 4),
        'ComicInfo.xml': utf8.encode('<ComicInfo/>'),
      }),
    );
    final model = PageEditModel([page('page_001.png'), page('page_002.png')]);
    model.deleteAt(0);

    final bytes = buildEditedArchive(original, model, renumber: true);
    final names = collectZipEntries(bytes).map((e) => e.name).toList();
    expect(names, ['page_0001.png', 'ComicInfo.xml']);
  });

  test('buildEditedArchive prefers edited data over the archive entry', () {
    final original = collectZipEntries(
      makeZip({
        'page_001.png': makeSolidPng(4, 4),
        'page_002.png': makeSolidPng(4, 4),
        'ComicInfo.xml': utf8.encode('<ComicInfo/>'),
      }),
    );
    final model = PageEditModel([page('page_001.png'), page('page_002.png')]);
    final replacement = makeSolidPng(8, 8);
    model.markEdited(0, replacement);

    final bytes = buildEditedArchive(original, model, renumber: false);
    final entries = collectZipEntries(bytes);
    final edited = entries.firstWhere((e) => e.name == 'page_001.png');
    expect(edited.bytes, replacement);
    expect(entries.map((e) => e.name), contains('ComicInfo.xml'));
  });

  test('split replaces the page and inserts pieces', () {
    final model = PageEditModel([page('a.png'), page('b.png')]);
    model.replaceWithPieces(0, [
      (name: 'a.png', data: makeSolidPng(4, 2)),
      (name: 'a2.png', data: makeSolidPng(4, 2)),
    ]);
    expect(model.pages.map((p) => p.name).toList(), [
      'a.png',
      'a2.png',
      'b.png',
    ]);
    expect(model.pages[0].data, isNotNull);
  });
}
