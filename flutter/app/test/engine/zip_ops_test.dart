import 'dart:typed_data';

import 'package:cbzmanager/src/engine/models.dart';
import 'package:cbzmanager/src/engine/zip_ops.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  test('collect/write round-trip preserves entry names and bytes', () {
    final zip = makeZip({
      'page_001.png': makeSolidPng(4, 4),
      'ComicInfo.xml': '<ComicInfo/>'.codeUnits,
    });

    final entries = collectZipEntries(zip);
    expect(entries.map((e) => e.name), ['page_001.png', 'ComicInfo.xml']);

    final rebuilt = writeZipEntries(entries);
    final again = collectZipEntries(rebuilt);
    expect(again.map((e) => e.name), entries.map((e) => e.name));
    for (var i = 0; i < entries.length; i++) {
      expect(again[i].bytes, entries[i].bytes);
    }
  });

  test('findComicInfoIndex is case-insensitive', () {
    final entries = collectZipEntries(
      makeZip({
        'page_001.png': makeSolidPng(2, 2),
        'comicinfo.XML': '<x/>'.codeUnits,
      }),
    );
    expect(findComicInfoIndex(entries), 1);
  });

  test('findComicInfoIndex returns -1 when absent', () {
    final entries = collectZipEntries(
      makeZip({'page_001.png': makeSolidPng(2, 2)}),
    );
    expect(findComicInfoIndex(entries), -1);
  });

  test('stripComicInfoEntries removes only ComicInfo.xml', () {
    final entries = collectZipEntries(
      makeZip({
        'page_001.png': makeSolidPng(2, 2),
        'ComicInfo.xml': '<x/>'.codeUnits,
        'page_002.png': makeSolidPng(2, 2),
      }),
    );
    final stripped = stripComicInfoEntries(entries);
    expect(stripped.map((e) => e.name), ['page_001.png', 'page_002.png']);
  });

  test('rejects garbage without crashing', () {
    List<ZipEntryData>? entries;
    try {
      entries = collectZipEntries(Uint8List.fromList([1, 2, 3, 4]));
    } catch (_) {
      entries = null;
    }
    expect(entries == null || entries.isEmpty, isTrue);
  });
}
