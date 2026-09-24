import 'package:cbzmanager/src/engine/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isImageExt', () {
    test('accepts known image extensions regardless of case/dot', () {
      expect(isImageExt('.jpg'), isTrue);
      expect(isImageExt('.JPEG'), isTrue);
      expect(isImageExt('png'), isTrue);
      expect(isImageExt('.WebP'), isTrue);
      expect(isImageExt('.tiff'), isTrue);
    });

    test('rejects non-images', () {
      expect(isImageExt('.xml'), isFalse);
      expect(isImageExt('.txt'), isFalse);
      expect(isImageExt(''), isFalse);
    });
  });

  group('formatPageName', () {
    test('uses 4-digit padding by default (PAGE_PAD_DEFAULT)', () {
      expect(formatPageName(1, '.jpg'), 'page_0001.jpg');
      expect(formatPageName(42, 'png'), 'page_0042.png');
      expect(formatPageName(12345, '.webp'), 'page_12345.webp');
    });

    test('honours an explicit padding', () {
      expect(formatPageName(7, '.png', padding: 3), 'page_007.png');
    });
  });

  group('pagePaddingFor', () {
    test('never below PAGE_PAD_MIN (3)', () {
      expect(pagePaddingFor(1), 3);
      expect(pagePaddingFor(999), 3);
    });

    test('widens with the digit count', () {
      expect(pagePaddingFor(1000), 4);
      expect(pagePaddingFor(123456), 6);
    });
  });

  group('encodeExtFor', () {
    test('keeps jpeg/webp/png/bmp', () {
      expect(encodeExtFor('.jpg'), '.jpg');
      expect(encodeExtFor('.jpeg'), '.jpg');
      expect(encodeExtFor('.webp'), '.webp');
      expect(encodeExtFor('.png'), '.png');
      expect(encodeExtFor('.bmp'), '.bmp');
    });

    test('maps formats without a writer to png', () {
      expect(encodeExtFor('.gif'), '.png');
      expect(encodeExtFor('.tiff'), '.png');
      expect(encodeExtFor('.xyz'), '.png');
    });
  });
}
