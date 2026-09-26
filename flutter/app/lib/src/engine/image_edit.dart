import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'format.dart';

/// Parameters of the colour-adjustment pipeline, applied in this fixed order:
///
/// 1. invert, 2. grayscale, 3. sepia, 4. per-channel gains, 5. saturation,
/// 6. contrast around 128, 7. brightness, 8. gamma (`255*(c/255)^(1/gamma)`).
///
/// Port of `TColorAdjust` from `uimageedit.pas`. All defaults are identity.
class ColorAdjust {
  const ColorAdjust({
    this.invert = false,
    this.grayscale = false,
    this.sepia = false,
    this.rGain = 1.0,
    this.gGain = 1.0,
    this.bGain = 1.0,
    this.saturation = 1.0,
    this.contrast = 1.0,
    this.brightness = 0.0,
    this.gamma = 1.0,
  });

  static const ColorAdjust neutral = ColorAdjust();

  final bool invert;
  final bool grayscale;
  final bool sepia;
  final double rGain;
  final double gGain;
  final double bGain;
  final double saturation;
  final double contrast;
  final double brightness;
  final double gamma;

  bool get isNeutral =>
      !invert &&
      !grayscale &&
      !sepia &&
      rGain == 1.0 &&
      gGain == 1.0 &&
      bGain == 1.0 &&
      saturation == 1.0 &&
      contrast == 1.0 &&
      brightness == 0.0 &&
      gamma == 1.0;
}

/// Box-filter resample (nearest-neighbour quality), both for enlarge and shrink.
/// Port of `ResampleIntfImage` (with its `MaxSamples` stepping). Returns null
/// for invalid input.
img.Image? resampleImage(img.Image source, int newWidth, int newHeight) {
  if (source.width <= 0 || source.height <= 0) return null;
  if (newWidth <= 0 || newHeight <= 0) return null;

  final dst = img.Image(width: newWidth, height: newHeight, numChannels: 4);
  const maxSamples = 4;

  for (var y = 0; y < newHeight; y++) {
    var sy0 = (y * source.height) ~/ newHeight;
    var sy1 = ((y + 1) * source.height) ~/ newHeight;
    if (sy1 <= sy0) sy1 = sy0 + 1;
    final stepY = _step(sy0, sy1, maxSamples);

    for (var x = 0; x < newWidth; x++) {
      var sx0 = (x * source.width) ~/ newWidth;
      var sx1 = ((x + 1) * source.width) ~/ newWidth;
      if (sx1 <= sx0) sx1 = sx0 + 1;
      final stepX = _step(sx0, sx1, maxSamples);

      var r = 0;
      var g = 0;
      var b = 0;
      var a = 0;
      var n = 0;
      for (var iy = sy0; iy < sy1; iy += stepY) {
        for (var ix = sx0; ix < sx1; ix += stepX) {
          final p = source.getPixel(ix, iy);
          r += p.r.toInt();
          g += p.g.toInt();
          b += p.b.toInt();
          a += p.a.toInt();
          n++;
        }
      }
      if (n == 0) continue;
      dst.setPixelRgba(x, y, r ~/ n, g ~/ n, b ~/ n, a ~/ n);
    }
  }
  return dst;
}

int _step(int from, int to, int maxSamples) {
  final span = to - from;
  return span <= 0 ? 1 : ((span + maxSamples - 1) ~/ maxSamples).clamp(1, span);
}

/// Applies [adjust] to [source]. Alpha is preserved. Returns null for invalid
/// input.
img.Image? adjustColors(img.Image source, ColorAdjust adjust) {
  if (source.width <= 0 || source.height <= 0) return null;
  final dst = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final p = source.getPixel(x, y);
      final t = _transform(
        p.r.toDouble(),
        p.g.toDouble(),
        p.b.toDouble(),
        adjust,
      );
      dst.setPixelRgba(x, y, t.$1, t.$2, t.$3, p.a.toInt());
    }
  }
  return dst;
}

(int, int, int) _transform(double r, double g, double b, ColorAdjust adj) {
  if (adj.invert) {
    r = 255 - r;
    g = 255 - g;
    b = 255 - b;
  }
  if (adj.grayscale) {
    final l = 0.299 * r + 0.587 * g + 0.114 * b;
    r = l;
    g = l;
    b = l;
  }
  if (adj.sepia) {
    final sr = 0.393 * r + 0.769 * g + 0.189 * b;
    final sg = 0.349 * r + 0.686 * g + 0.168 * b;
    final sb = 0.272 * r + 0.534 * g + 0.131 * b;
    r = sr;
    g = sg;
    b = sb;
  }
  r *= adj.rGain;
  g *= adj.gGain;
  b *= adj.bGain;
  if (adj.saturation != 1.0) {
    final l = 0.299 * r + 0.587 * g + 0.114 * b;
    r = l + (r - l) * adj.saturation;
    g = l + (g - l) * adj.saturation;
    b = l + (b - l) * adj.saturation;
  }
  if (adj.contrast != 1.0) {
    r = (r - 128) * adj.contrast + 128;
    g = (g - 128) * adj.contrast + 128;
    b = (b - 128) * adj.contrast + 128;
  }
  if (adj.brightness != 0.0) {
    r += adj.brightness;
    g += adj.brightness;
    b += adj.brightness;
  }
  if (adj.gamma != 1.0) {
    r = (255 * math.pow(r / 255, 1 / adj.gamma)).toDouble();
    g = (255 * math.pow(g / 255, 1 / adj.gamma)).toDouble();
    b = (255 * math.pow(b / 255, 1 / adj.gamma)).toDouble();
  }
  return (_clamp255(r), _clamp255(g), _clamp255(b));
}

int _clamp255(double v) => v < 0
    ? 0
    : v > 255
    ? 255
    : v.round();

/// Encodes [image] for [targetExt] using the reference writers: JPEG q92,
/// PNG/BMP lossless, WebP q75; anything else falls back to PNG. [targetExt] is
/// expected to come from [encodeExtFor].
Uint8List encodeImage(img.Image image, String targetExt) {
  switch (targetExt.toLowerCase()) {
    case '.jpg':
    case '.jpeg':
      return Uint8List.fromList(img.encodeJpg(image, quality: 92));
    case '.bmp':
      return Uint8List.fromList(img.encodeBmp(image));
    case '.webp':
      return Uint8List.fromList(
        img.encodeWebP(image, lossless: false, quality: 75),
      );
    case '.png':
    default:
      return Uint8List.fromList(img.encodePng(image));
  }
}

/// Applies an edit pipeline to [src] and returns the encoded page piece(s):
/// optional resize → colour adjust → optional split → encode for [targetExt].
///
/// When [split] is set, the cut positions come from [cuts] (fractions 0..1) when
/// non-empty, otherwise [pieces] equal slices are produced.
List<Uint8List> applyEditPipeline(
  img.Image src, {
  int? width,
  int? height,
  ColorAdjust adjust = ColorAdjust.neutral,
  bool split = false,
  bool horizontal = true,
  int pieces = 2,
  List<double>? cuts,
  required String targetExt,
}) {
  var image = src;
  if (width != null && height != null) {
    image = resampleImage(image, width, height) ?? image;
  }
  if (!adjust.isNeutral) {
    image = adjustColors(image, adjust) ?? image;
  }

  final List<img.Image> images;
  if (split) {
    final effective = (cuts != null && cuts.isNotEmpty)
        ? cuts
        : <double>[for (var i = 1; i < pieces; i++) i / pieces];
    images = splitImage(image, horizontal: horizontal, cuts: effective);
  } else {
    images = [image];
  }
  return [for (final im in images) encodeImage(im, targetExt)];
}

/// Cuts [source] along parallel lines into N+1 pieces, in reading order.
///
/// [cuts] are fractions 0..1; they are clamped to [1, dim-1] pixels, sorted and
/// deduplicated. Returns an empty list when there is no usable cut. Port of
/// `SplitIntfImage`.
List<img.Image> splitImage(
  img.Image source, {
  required bool horizontal,
  required List<double> cuts,
}) {
  if (source.width <= 0 || source.height <= 0 || cuts.isEmpty) {
    return const <img.Image>[];
  }
  final dim = horizontal ? source.height : source.width;
  final normalized = _normalizeCuts(cuts, dim);
  if (normalized.isEmpty) return const <img.Image>[];

  final pieces = <img.Image>[];
  var start = 0;
  for (var i = 0; i <= normalized.length; i++) {
    final end = i < normalized.length ? normalized[i] : dim;
    final size = end - start;
    if (size > 0) {
      pieces.add(
        horizontal
            ? _copyHorizontal(source, start, size)
            : _copyVertical(source, start, size),
      );
    }
    start = end;
  }
  return pieces;
}

List<int> _normalizeCuts(List<double> cutPos, int dim) {
  final cuts = <int>[];
  for (final c in cutPos) {
    var p = (c * dim).round();
    if (p < 1) p = 1;
    if (p > dim - 1) p = dim - 1;
    cuts.add(p);
  }
  cuts.sort();
  final out = <int>[];
  for (final c in cuts) {
    if (out.isNotEmpty && out.last == c) continue;
    out.add(c);
  }
  return out;
}

img.Image _copyHorizontal(img.Image source, int y0, int height) {
  final piece = img.Image(width: source.width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < source.width; x++) {
      final p = source.getPixel(x, y0 + y);
      piece.setPixelRgba(
        x,
        y,
        p.r.toInt(),
        p.g.toInt(),
        p.b.toInt(),
        p.a.toInt(),
      );
    }
  }
  return piece;
}

img.Image _copyVertical(img.Image source, int x0, int width) {
  final piece = img.Image(width: width, height: source.height, numChannels: 4);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < width; x++) {
      final p = source.getPixel(x0 + x, y);
      piece.setPixelRgba(
        x,
        y,
        p.r.toInt(),
        p.g.toInt(),
        p.b.toInt(),
        p.a.toInt(),
      );
    }
  }
  return piece;
}
