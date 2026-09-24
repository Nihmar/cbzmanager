import 'dart:isolate';
import 'dart:typed_data';

import '../../engine/merge.dart';

/// Builds one volume inside a background isolate.
///
/// Lives at the top level so the isolate closure captures only sendable values
/// (a `List<Uint8List>`, strings, ints, bools). Never create the `Isolate.run`
/// closure inside a `Pool.withResource` callback: it would capture the pool.
Future<Uint8List?> buildVolumeInIsolate(
  List<Uint8List> chapterArchives,
  String seriesName,
  int volNum,
  List<int> chapterNumbers,
  bool generateComicInfo,
) {
  return Isolate.run(
    () => buildVolumeBytes(
      chapterArchives,
      seriesName: seriesName,
      volNum: volNum,
      chapterNumbers: chapterNumbers,
      generateComicInfo: generateComicInfo,
    ),
  );
}
