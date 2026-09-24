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
}
