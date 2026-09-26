import 'dart:typed_data';

import 'package:cbzmanager/src/features/browser/thumbnail_isolate.dart';
import 'package:cbzmanager/src/native/cbr_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  test('first-page thumbnail, page count and ComicInfo for a CBZ', () {
    final bytes = makeZip({
      'page_002.png': makeSolidPng(32, 32),
      'page_001.png': makeSolidPng(32, 32),
      'ComicInfo.xml': '<x/>'.codeUnits,
    });

    expect(countImagePages(bytes, 'book.cbz'), 2);
    expect(hasComicInfo(bytes, 'book.cbz'), isTrue);

    final thumb = decodeFirstPageThumbnail(bytes, 'book.cbz', 64, 64);
    expect(thumb, isNotNull);
    expect(thumb!.sublist(0, 2), [0xFF, 0xD8]); // JPEG SOI

    expect(decodePageThumbnail(bytes, 'book.cbz', 1, 64, 64), isNotNull);
    expect(decodePageThumbnail(bytes, 'book.cbz', 5, 64, 64), isNull);
  });

  test('unreadable archive yields no pages', () {
    final garbage = Uint8List.fromList([1, 2, 3, 4]);
    expect(countImagePages(garbage, 'x.cbz'), 0);
    expect(decodeFirstPageThumbnail(garbage, 'x.cbz', 64, 64), isNull);
  });

  test('zip-format CBR reads through libarchive when available', () {
    if (!CbrReader.isSupported) {
      markTestSkipped('libarchive is not available on this host');
      return;
    }
    final bytes = makeZip({'page_001.png': makeSolidPng(32, 32)});
    expect(countImagePages(bytes, 'book.cbr'), 1);
    expect(decodeFirstPageThumbnail(bytes, 'book.cbr', 64, 64), isNotNull);
  });

  // The preview reader used to call collectEntries once per thumbnail; the
  // whole archive is now decompressed once into a packed buffer.
  test('cbrPages packs the image pages once, sorted by name', () {
    if (!CbrReader.isSupported) {
      markTestSkipped('libarchive is not available on this host');
      return;
    }
    final small = makeSolidPng(4, 4);
    final large = makeSolidPng(8, 8);
    final bytes = makeZip({
      'page_002.png': large, // stored first, must sort second
      'ComicInfo.xml': '<x/>'.codeUnits,
      'page_001.png': small,
    });

    final pages = cbrPages(bytes);
    expect(pages.offsets, [0, small.length, small.length + large.length]);
    expect(
      Uint8List.sublistView(pages.buffer, 0, small.length),
      small,
      reason: 'page_001 first by name',
    );
    expect(
      Uint8List.sublistView(pages.buffer, small.length),
      large,
      reason: 'page_002 second by name; ComicInfo.xml excluded',
    );
  });

  test('cbrPagesInIsolate transfers the packed pages', () async {
    if (!CbrReader.isSupported) {
      markTestSkipped('libarchive is not available on this host');
      return;
    }
    final page = makeSolidPng(4, 4);
    final bytes = makeZip({'page_001.png': page});

    final pages = await cbrPagesInIsolate(bytes);
    expect(pages.offsets, [0, page.length]);
    expect(pages.buffer, page);
  });
}
