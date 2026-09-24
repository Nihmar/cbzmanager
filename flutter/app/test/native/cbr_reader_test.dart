import 'package:cbzmanager/src/native/cbr_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  test('reads image entries through libarchive (zip-format CBR)', () {
    if (!CbrReader.isSupported) {
      markTestSkipped('libarchive is not available on this host');
      return;
    }

    final bytes = makeZip({
      'ComicInfo.xml': '<x/>'.codeUnits,
      'page_001.png': makeSolidPng(4, 4),
      'page_002.png': makeSolidPng(4, 4),
    });

    final images = CbrReader.imageEntries(bytes);
    expect(images.map((e) => e.name), ['page_001.png', 'page_002.png']);
    for (final entry in images) {
      expect(entry.bytes, isNotEmpty);
    }
  });

  test('reports availability consistently', () {
    // On desktop CI libarchive is present; on a bare host it may not be.
    // Either way the API must answer without throwing.
    expect(CbrReader.isSupported, isA<bool>());
  });
}
