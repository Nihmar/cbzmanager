import 'dart:typed_data';

import 'package:cbzmanager/src/engine/cbr_convert.dart';
import 'package:cbzmanager/src/engine/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List data(List<int> bytes) => Uint8List.fromList(bytes);

  test('drops ComicInfo/non-images and renumbers images in order', () {
    final entries = [
      ZipEntryData('ComicInfo.xml', data([1])),
      ZipEntryData('cover.jpg', data([2])),
      ZipEntryData('credits.txt', data([3])),
      ZipEntryData('page2.png', data([4])),
      ZipEntryData('page1.png', data([5])),
    ];

    final out = renumberCbrImages(entries);
    expect(out.map((e) => e.name).toList(), [
      'page_001.jpg',
      'page_002.png',
      'page_003.png',
    ]);
    expect(out[0].bytes, [2]);
    expect(out[2].bytes, [5]);
  });

  test('padding widens with the image count', () {
    final entries = [
      for (var i = 0; i < 1000; i++) ZipEntryData('img$i.png', data([i % 256])),
    ];
    final out = renumberCbrImages(entries);
    expect(out.first.name, 'page_0001.png');
    expect(out.last.name, 'page_1000.png');
  });
}
