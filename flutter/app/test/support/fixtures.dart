import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

/// Small solid PNG, cheap to decode.
Uint8List makeSolidPng(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 30, 200));
  return Uint8List.fromList(img.encodePng(image));
}

/// Noisy PNG. Lossy WebP is much smaller, which forces the "convert when
/// smaller" branch deterministically.
Uint8List makeNoisePng(int width, int height, [int seed = 1]) {
  final rnd = Random(seed);
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        rnd.nextInt(256),
        rnd.nextInt(256),
        rnd.nextInt(256),
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Builds a deflate ZIP/CBZ from an ordered map of entry name -> bytes.
Uint8List makeZip(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((name, bytes) {
    archive.add(ArchiveFile.bytes(name, bytes));
  });
  return Uint8List.fromList(
    ZipEncoder().encodeBytes(archive, level: DeflateLevel.defaultCompression),
  );
}
