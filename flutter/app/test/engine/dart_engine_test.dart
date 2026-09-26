import 'dart:typed_data';

import 'package:cbzmanager/src/engine/dart_engine.dart';
import 'package:cbzmanager/src/engine/models.dart';
import 'package:cbzmanager/src/engine/zip_ops.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  const engine = DartCbzEngine();

  group('validate', () {
    test('accepts an archive whose images all decode', () async {
      final zip = makeZip({
        'page_001.png': makeSolidPng(8, 8),
        'page_002.png': makeSolidPng(8, 8),
      });
      final result = await engine.validate(ArchiveData('ok.cbz', zip));
      expect(result.valid, isTrue);
      expect(result.imageCount, 2);
      expect(result.errors, isEmpty);
    });

    test('flags an undecodable image', () async {
      final zip = makeZip({
        'page_001.png': makeSolidPng(8, 8),
        'page_002.jpg': <int>[0, 1, 2, 3, 4],
      });
      final result = await engine.validate(ArchiveData('bad.cbz', zip));
      expect(result.valid, isFalse);
      expect(result.errors.single.page, 'page_002.jpg');
    });

    test('reports a file-level error for a non-ZIP', () async {
      final result = await engine.validate(
        ArchiveData('nope.cbz', Uint8List.fromList([1, 2, 3, 4])),
      );
      expect(result.valid, isFalse);
      expect(result.error, isNotNull);
      expect(result.imageCount, 0);
    });

    test('rejects an archive with no images', () async {
      final zip = makeZip({'ComicInfo.xml': '<x/>'.codeUnits});
      final result = await engine.validate(ArchiveData('empty.cbz', zip));
      expect(result.valid, isFalse);
      expect(result.error, contains('No images'));
    });
  });

  group('convertWebp', () {
    test('forces conversion and renames/removes entries', () async {
      final zip = makeZip({
        'first.png': makeSolidPng(16, 16),
        'ComicInfo.xml': '<x/>'.codeUnits,
        'second.png': makeSolidPng(16, 16),
      });
      final result = await engine.convertWebp(
        ArchiveData('book.cbz', zip),
        const ConvertOptions(onlyIfSmaller: false),
      );
      expect(result.success, isTrue);
      expect(result.converted, 2);

      final entries = collectZipEntries(result.output!);
      expect(entries.map((e) => e.name), ['page_0001.webp', 'page_0002.webp']);
    });

    test('keeps ComicInfo.xml (in place) when removeComicInfo is false',
        () async {
      // The flag used to be ignored: the output was built from the image
      // entries alone, so ComicInfo.xml was always dropped.
      final zip = makeZip({
        'first.png': makeSolidPng(16, 16),
        'ComicInfo.xml': '<x/>'.codeUnits,
        'second.png': makeSolidPng(16, 16),
      });
      final result = await engine.convertWebp(
        ArchiveData('book.cbz', zip),
        const ConvertOptions(
          onlyIfSmaller: false,
          removeComicInfo: false,
        ),
      );
      expect(result.success, isTrue);
      final entries = collectZipEntries(result.output!);
      expect(
        entries.map((e) => e.name),
        ['page_0001.webp', 'ComicInfo.xml', 'page_0002.webp'],
      );
    });

    test('drops ComicInfo.xml (the default), leaving images renumbered',
        () async {
      final zip = makeZip({
        'first.png': makeSolidPng(16, 16),
        'ComicInfo.xml': '<x/>'.codeUnits,
        'second.png': makeSolidPng(16, 16),
      });
      final result = await engine.convertWebp(
        ArchiveData('book.cbz', zip),
        const ConvertOptions(onlyIfSmaller: false),
      );
      final entries = collectZipEntries(result.output!);
      expect(entries.map((e) => e.name), ['page_0001.webp', 'page_0002.webp']);
    });

    test('keeps an undecodable page as-is and counts it kept', () async {
      // A page that cannot be decoded is left untouched (the reference keeps
      // the original bytes rather than dropping the page).
      final zip = makeZip({
        'page_0001.png': <int>[0, 1, 2, 3, 4, 5, 6, 7],
      });
      final result = await engine.convertWebp(
        ArchiveData('book.cbz', zip),
        const ConvertOptions(onlyIfSmaller: true),
      );
      expect(result.success, isTrue);
      expect(result.converted, 0);
      expect(result.kept, 1);
      final entries = collectZipEntries(result.output!);
      expect(entries.single.name, 'page_0001.png');
      expect(entries.single.bytes, [0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('converts a noisy page when WebP is smaller', () async {
      final zip = makeZip({'page_0001.png': makeNoisePng(96, 96)});
      final result = await engine.convertWebp(
        ArchiveData('book.cbz', zip),
        const ConvertOptions(onlyIfSmaller: true),
      );
      expect(result.success, isTrue);
      final entries = collectZipEntries(result.output!);
      expect(entries.single.name, 'page_0001.webp');
      expect(result.converted, 1);
    });
  });

  group('comicinfo', () {
    test('scans and strips', () async {
      final zip = makeZip({
        'page_001.png': makeSolidPng(4, 4),
        'ComicInfo.xml': '<ComicInfo/>'.codeUnits,
      });
      final scan = await engine.scanComicInfo(ArchiveData('b.cbz', zip));
      expect(scan.found, isTrue);

      final stripped = await engine.stripComicInfo(ArchiveData('b.cbz', zip));
      final entries = collectZipEntries(stripped.bytes);
      expect(entries.map((e) => e.name), ['page_001.png']);
    });
  });
}
