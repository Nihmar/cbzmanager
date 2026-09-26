import 'package:cbzmanager/src/engine/image_edit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image solid(int w, int h, int r, int g, int b, [int a = 255]) {
  final im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(r, g, b, a));
  return im;
}

List<int> rgb(img.Image im) {
  final p = im.getPixel(0, 0);
  return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
}

void main() {
  group('resample', () {
    test('identity keeps pixels', () {
      final out = resampleImage(solid(4, 4, 10, 20, 30), 4, 4)!;
      expect(rgb(out), [10, 20, 30]);
    });

    test('downscale averages source blocks', () {
      final src = img.Image(width: 4, height: 1, numChannels: 4);
      for (var x = 0; x < 4; x++) {
        src.setPixelRgba(x, 0, x < 2 ? 200 : 0, 0, x < 2 ? 0 : 200, 255);
      }
      final out = resampleImage(src, 2, 1)!;
      expect(out.getPixel(0, 0).r.toInt(), 200);
      expect(out.getPixel(1, 0).b.toInt(), 200);
    });

    test('rejects invalid dimensions', () {
      expect(resampleImage(solid(4, 4, 0, 0, 0), 0, 4), isNull);
      expect(resampleImage(solid(4, 4, 0, 0, 0), 4, -1), isNull);
    });
  });

  group('adjustColors', () {
    test('neutral is identity', () {
      final out = adjustColors(solid(2, 2, 12, 34, 56), ColorAdjust.neutral)!;
      expect(rgb(out), [12, 34, 56]);
      expect(ColorAdjust.neutral.isNeutral, isTrue);
    });

    test('invert', () {
      final out = adjustColors(
        solid(1, 1, 10, 20, 30),
        const ColorAdjust(invert: true),
      )!;
      expect(rgb(out), [245, 235, 225]);
    });

    test('grayscale uses Rec.601 luma', () {
      final out = adjustColors(
        solid(1, 1, 255, 0, 0),
        const ColorAdjust(grayscale: true),
      )!;
      expect(out.getPixel(0, 0).r.toInt(), 76);
    });

    test('brightness clamps to 255', () {
      final out = adjustColors(
        solid(1, 1, 250, 0, 0),
        const ColorAdjust(brightness: 50),
      )!;
      expect(out.getPixel(0, 0).r.toInt(), 255);
    });

    test('preserves alpha', () {
      final out = adjustColors(
        solid(1, 1, 10, 10, 10, 128),
        const ColorAdjust(invert: true),
      )!;
      expect(out.getPixel(0, 0).a.toInt(), 128);
    });
  });

  group('split', () {
    test('horizontal cut into two equal pieces', () {
      final pieces = splitImage(
        solid(2, 4, 1, 2, 3),
        horizontal: true,
        cuts: [0.5],
      );
      expect(pieces.length, 2);
      expect(pieces[0].height, 2);
      expect(pieces[1].height, 2);
      expect(pieces[0].width, 2);
    });

    test('vertical cut keeps full height', () {
      final pieces = splitImage(
        solid(4, 2, 0, 0, 0),
        horizontal: false,
        cuts: [0.5],
      );
      expect(pieces.length, 2);
      expect(pieces[0].width, 2);
      expect(pieces[0].height, 2);
    });

    test('clamps, sorts and deduplicates cuts', () {
      final pieces = splitImage(
        solid(40, 40, 0, 0, 0),
        horizontal: true,
        cuts: [0.5, 0.5, 0.0, 1.0],
      );
      // 0.0 -> 1px, 0.5 -> 20px, 1.0 -> 39px  => 3 cuts, 4 pieces.
      expect(pieces.length, 4);
    });

    test('no cuts yields no pieces', () {
      expect(
        splitImage(solid(4, 4, 0, 0, 0), horizontal: true, cuts: const []),
        isEmpty,
      );
    });
  });

  group('applyEditPipeline', () {
    test('honours explicit cut fractions', () {
      final pieces = applyEditPipeline(
        solid(10, 10, 0, 0, 0),
        split: true,
        horizontal: true,
        cuts: const [0.2, 0.8],
        targetExt: '.png',
      );
      expect(pieces.length, 3);
      expect([for (final p in pieces) img.decodeImage(p)!.height], [2, 6, 2]);
    });

    test('falls back to equal pieces when no cuts are given', () {
      final pieces = applyEditPipeline(
        solid(10, 10, 0, 0, 0),
        split: true,
        horizontal: true,
        pieces: 2,
        targetExt: '.png',
      );
      expect(pieces.length, 2);
    });
  });
}
