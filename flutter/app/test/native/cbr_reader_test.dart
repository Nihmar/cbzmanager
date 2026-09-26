import 'dart:typed_data';

import 'package:cbzmanager/src/native/cbr_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Deterministic incompressible-ish payload spanning several 64 KiB reads.
Uint8List makePatternBytes(int length, [int seed = 7]) {
  final out = Uint8List(length);
  var x = seed;
  for (var i = 0; i < length; i++) {
    // Cheap LCG: reproducible, non-repeating at chunk boundaries.
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    out[i] = (x >> 16) & 0xff;
  }
  return out;
}

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

  // Regression: the read loop used `BytesBuilder(copy: false)` with
  // `chunk.asTypedList(read)` views over the single reusable native buffer.
  // Every view aliased the same memory, so each 64 KiB block of an entry
  // larger than one chunk came back as the last chunk's bytes.  Real comic
  // pages are hundreds of KiB, i.e. every CBR page was silently corrupted.
  test('entries larger than one 64 KiB read survive intact', () {
    if (!CbrReader.isSupported) {
      markTestSkipped('libarchive is not available on this host');
      return;
    }

    final payload = makePatternBytes(200000); // > 3 chunks
    final bytes = makeZip({'page_001.bin': payload});

    final entries = CbrReader.collectEntries(bytes);
    final got = entries.singleWhere((e) => e.name == 'page_001.bin').bytes;
    expect(got.length, payload.length);
    expect(got, equals(payload));
  });

  test('reports availability consistently', () {
    // On desktop CI libarchive is present; on a bare host it may not be.
    // Either way the API must answer without throwing.
    expect(CbrReader.isSupported, isA<bool>());
  });
}
