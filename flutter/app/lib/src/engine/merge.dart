import 'dart:convert';
import 'dart:typed_data';

import '../util/str_compare.dart';
import 'comicinfo.dart';
import 'format.dart';
import 'models.dart';
import 'zip_ops.dart';

/// Fallback chapters-per-volume when no data is available.
const int kDefaultChaptersPerVolume = 7;

/// Configuration for a merge run. Mirrors `TMergeOptions`.
class MergeOptions {
  const MergeOptions({
    this.seriesName = '',
    this.chapterStart = 0,
    this.chapterEnd = 0x7fffffff,
    this.chaptersPerVolume = 0,
    this.chaptersList = const <int>[],
    this.force = false,
    this.delete = false,
    this.generateComicInfo = false,
    this.threads = 0,
  });

  final String seriesName;
  final int chapterStart;
  final int chapterEnd;

  /// 0 = auto-calculate.
  final int chaptersPerVolume;

  /// Explicit chapter counts per volume (custom sequence). Wins over
  /// [chaptersPerVolume] when non-empty.
  final List<int> chaptersList;
  final bool force;
  final bool delete;
  final bool generateComicInfo;
  final int threads;
}

/// A chapter file and its numeric sort key.
class ChapterInfo {
  const ChapterInfo({
    required this.fileName,
    required this.number,
    required this.isSpecial,
  });

  final String fileName;
  final int number;
  final bool isSpecial;
}

/// One pre-planned volume.
class MergeBatch {
  const MergeBatch({
    required this.files,
    required this.volNum,
    required this.fileName,
  });

  final List<String> files;
  final int volNum;
  final String fileName;
}

/// A complete, I/O-free merge plan.
class MergePlan {
  const MergePlan({
    required this.seriesName,
    required this.cpv,
    required this.batches,
  });

  final String seriesName;
  final int cpv;
  final List<MergeBatch> batches;
}

class MergePlanResult {
  const MergePlanResult({this.plan, this.error});

  final MergePlan? plan;
  final String? error;
}

// ---------------------------------------------------------------------------
// Filename classification (port of the Pascal helpers)
// ---------------------------------------------------------------------------

String _stem(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot < 0 ? fileName : fileName.substring(0, dot);
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

bool _isAlpha(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5a) || (u >= 0x61 && u <= 0x7a);
}

/// Chapter-number portion of a filename, preserving leading zeros.
String extractChapterNumStr(String fileName) {
  final base = _stem(fileName);
  final dash = base.lastIndexOf(' -');
  if (dash > 0) {
    var result = base.substring(dash + 2).trim();
    if (result.startsWith('_')) result = result.substring(1);
    return result;
  }
  final v = base.lastIndexOf(' V');
  if (v > 0) {
    final s = base.substring(v + 2).trim();
    if (s.isNotEmpty && _isDigit(s[0])) return 'V$s';
  }
  return '';
}

/// Integer part of [extractChapterNumStr] (decimal/sub-chapter tags map to
/// their whole-number index).
int extractChapterNum(String fileName) {
  final s = extractChapterNumStr(fileName);
  var i = 0;
  while (i < s.length && _isDigit(s[i])) {
    i++;
  }
  return int.tryParse(s.substring(0, i)) ?? 0;
}

/// True when [fileName] is a volume of [seriesName]: stem == `Series V<digits>`.
bool isVolumeFile(String fileName, String seriesName) {
  if (seriesName.isEmpty) return false;
  final base = _stem(fileName);
  final prefix = '$seriesName V';
  if (!base.startsWith(prefix)) return false;
  final s = base.substring(prefix.length);
  if (s.isEmpty) return false;
  for (var i = 0; i < s.length; i++) {
    if (!_isDigit(s[i])) return false;
  }
  return true;
}

/// Strict chapter classification (numeric or alphabetic tag). Returns null when
/// the name is not a chapter (backups, decimals, other suffixes).
({String series, int number, bool isSpecial})? classifyChapter(
  String fileName,
) {
  final base = _stem(fileName);
  final dash = base.lastIndexOf(' -');
  if (dash <= 0) return null;
  final series = base.substring(0, dash).trim();
  if (series.isEmpty) return null;
  final tag = base.substring(dash + 2).trim();
  if (tag.isEmpty) return null;

  if (_isDigit(tag[0])) {
    var i = 0;
    while (i < tag.length && _isDigit(tag[i])) {
      i++;
    }
    final number = int.tryParse(tag.substring(0, i)) ?? 0;
    if (!_validSubGroups(tag, i)) return null;
    return (series: series, number: number, isSpecial: false);
  }
  if (_isAlpha(tag[0])) {
    var i = 1;
    while (i < tag.length && (_isAlpha(tag[i]) || _isDigit(tag[i]))) {
      i++;
    }
    if (!_validSubGroups(tag, i)) return null;
    return (series: series, number: 0, isSpecial: true);
  }
  return null;
}

bool _validSubGroups(String tag, int i) {
  while (i < tag.length) {
    if (tag[i] != '_' || i == tag.length - 1 || !_isDigit(tag[i + 1])) {
      return false;
    }
    i += 2;
    while (i < tag.length && _isDigit(tag[i])) {
      i++;
    }
  }
  return true;
}

/// First `"Series - NNNN"` series name found in [files], or ''.
String detectSeriesName(List<String> files) {
  for (final file in files) {
    final n = _stem(file).lastIndexOf(' -');
    if (n > 0) return _stem(file).substring(0, n).trim();
  }
  return '';
}

/// Python-exact CPV estimate `(lowest_chapter - 1) / num_volumes`, or 0.0.
double calculateChaptersPerVolumeFloat(List<String> files, String seriesName) {
  if (seriesName.isEmpty || files.isEmpty) return 0;
  var lowest = 0x7fffffff;
  var volCount = 0;
  for (final file in files) {
    if (isVolumeFile(file, seriesName)) {
      volCount++;
      continue;
    }
    final chapter = classifyChapter(file);
    if (chapter != null &&
        chapter.series == seriesName &&
        !chapter.isSpecial &&
        chapter.number < lowest) {
      lowest = chapter.number;
    }
  }
  if (volCount > 0 && lowest > 1 && lowest < 0x7fffffff) {
    return (lowest - 1) / volCount;
  }
  return 0;
}

int calculateChaptersPerVolume(List<String> files, String seriesName) =>
    calculateChaptersPerVolumeFloat(files, seriesName).truncate();

/// Largest existing `<SeriesName> VNNN.cbz` number, or 0.
int lastVolumeNumber(List<String> files, String seriesName) {
  if (seriesName.isEmpty) return 0;
  var result = 0;
  for (final file in files) {
    if (!isVolumeFile(file, seriesName)) continue;
    final num = int.tryParse(_stem(file).substring(seriesName.length + 3)) ?? 0;
    if (num > result) result = num;
  }
  return result;
}

List<T> _stableSort<T>(List<T> items, int Function(T a, T b) compare) {
  final indexed = <(int, T)>[
    for (var i = 0; i < items.length; i++) (i, items[i]),
  ];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return <T>[for (final e in indexed) e.$2];
}

/// Ordered chapters of [seriesName]; specials get sequential numbers after the
/// highest regular chapter.
List<ChapterInfo> collectChapters(List<String> files, String seriesName) {
  if (seriesName.isEmpty) return const <ChapterInfo>[];
  final chapters = <ChapterInfo>[];
  var maxNum = 0;
  for (final file in files) {
    final c = classifyChapter(file);
    if (c == null || c.series != seriesName) continue;
    chapters.add(
      ChapterInfo(fileName: file, number: c.number, isSpecial: c.isSpecial),
    );
    if (!c.isSpecial && c.number > maxNum) maxNum = c.number;
  }

  var sorted = _stableSort<ChapterInfo>(chapters, (a, b) {
    if (a.number != b.number) return a.number - b.number;
    return compareStr(a.fileName, b.fileName);
  });

  var next = maxNum + 1;
  sorted = [
    for (final c in sorted)
      if (c.isSpecial)
        ChapterInfo(fileName: c.fileName, number: next++, isSpecial: true)
      else
        c,
  ];

  return _stableSort<ChapterInfo>(sorted, (a, b) {
    if (a.number != b.number) return a.number - b.number;
    return compareStr(a.fileName, b.fileName);
  });
}

// ---------------------------------------------------------------------------
// Planning
// ---------------------------------------------------------------------------

MergePlanResult planMerge(List<String> files, MergeOptions options) {
  var seriesName = options.seriesName;
  if (seriesName.isEmpty) seriesName = detectSeriesName(files);
  if (seriesName.isEmpty) seriesName = 'Unknown';

  double cpvf;
  if (options.chaptersPerVolume >= 1) {
    cpvf = options.chaptersPerVolume.toDouble();
  } else {
    cpvf = calculateChaptersPerVolumeFloat(files, seriesName);
    if (cpvf < 1.0) cpvf = kDefaultChaptersPerVolume.toDouble();
  }
  final cpv = cpvf.truncate();

  final chapterList = collectChapters(files, seriesName)
      .where(
        (c) =>
            c.number >= options.chapterStart && c.number <= options.chapterEnd,
      )
      .toList();
  if (chapterList.isEmpty) {
    return const MergePlanResult(error: 'No matching chapter files found');
  }

  final useList = options.chaptersList.isNotEmpty;
  final totalBatches = useList
      ? options.chaptersList.length
      : (chapterList.length / cpvf).truncate();

  var volNum = lastVolumeNumber(files, seriesName) + 1;
  var chIdx = 0;
  var listIdx = 0;
  final batches = <MergeBatch>[];

  while (chIdx < chapterList.length) {
    if (!options.force && batches.length >= totalBatches) break;
    final remaining = chapterList.length - chIdx;
    int batchSize;

    if (useList) {
      if (listIdx > options.chaptersList.length - 1) break;
      batchSize = options.chaptersList[listIdx];
      listIdx++;
      if (batchSize <= 0 || batchSize > remaining) break;
    } else {
      batchSize = cpv;
      if (batchSize > remaining) {
        if (options.force) {
          batchSize = remaining;
        } else {
          break;
        }
      } else if (options.force &&
          totalBatches > 0 &&
          batches.length + 1 >= totalBatches) {
        batchSize = remaining;
      }
    }

    batches.add(
      MergeBatch(
        files: [
          for (var n = 0; n < batchSize; n++) chapterList[chIdx + n].fileName,
        ],
        volNum: volNum,
        fileName: '$seriesName V${volNum.toString().padLeft(3, '0')}.cbz',
      ),
    );
    volNum++;
    chIdx += batchSize;
  }

  return MergePlanResult(
    plan: MergePlan(seriesName: seriesName, cpv: cpv, batches: batches),
  );
}

// ---------------------------------------------------------------------------
// Volume building
// ---------------------------------------------------------------------------

/// Merges chapter archives into one volume.
///
/// Images only (ComicInfo filtered, non-images dropped), sorted byte-wise then
/// renumbered `page_NNNN.*`. Returns null when no image was found (empty
/// batches produce no volume). Optionally appends a generated ComicInfo.xml.
Uint8List? buildVolumeBytes(
  List<Uint8List> chapterArchives, {
  required String seriesName,
  required int volNum,
  required List<int> chapterNumbers,
  bool generateComicInfo = false,
}) {
  final pages = <Uint8List>[];
  final exts = <String>[];

  for (final archiveBytes in chapterArchives) {
    final entries = collectZipEntries(archiveBytes);
    final sorted = _stableSort<ZipEntryData>(
      entries,
      (a, b) => compareStr(a.name, b.name),
    );
    for (final entry in sorted) {
      if (entry.name.toLowerCase() == comicInfoName.toLowerCase()) continue;
      final ext = _extOf(entry.name);
      if (!isImageExt(ext)) continue;
      pages.add(entry.bytes);
      exts.add(ext);
    }
  }

  if (pages.isEmpty) return null;

  final padding = pagePaddingFor(pages.length);
  final output = <ZipEntryData>[
    for (var i = 0; i < pages.length; i++)
      ZipEntryData(formatPageName(i + 1, exts[i], padding: padding), pages[i]),
  ];

  if (generateComicInfo) {
    final first = chapterNumbers.isNotEmpty ? chapterNumbers.first : 0;
    final last = chapterNumbers.isNotEmpty ? chapterNumbers.last : 0;
    final info = ComicInfo(
      series: seriesName,
      volume: volNum,
      manga: 'Unknown',
    );
    info.number = (first > 0 && last > 0) ? '$first-$last' : '$volNum';
    info.title = '$seriesName Vol.$volNum';
    info.pageCount = output.length;
    output.add(
      ZipEntryData(
        comicInfoName,
        Uint8List.fromList(utf8.encode(info.toXml())),
      ),
    );
  }

  return writeZipEntries(output);
}

String _extOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot).toLowerCase();
}

/// Volume-column labels for a custom sequence (chapter counts per volume),
/// continuing after [lastVolume]. A batch that does not fully fit the remaining
/// rows is skipped (its chapters stay unassigned, shown as '-'). Pure function
/// used by the sequence-builder preview.
List<String> customSequenceLabels(
  int count,
  List<int> sequence,
  int lastVolume,
) {
  final result = List<String>.filled(count, '');
  if (count == 0) return result;
  if (sequence.isEmpty) {
    for (var i = 0; i < count; i++) {
      result[i] = '?';
    }
    return result;
  }

  var volNum = lastVolume + 1;
  var consumed = 0;
  var seqIdx = 0;
  for (var i = 0; i < count; i++) {
    if (seqIdx < sequence.length) {
      // Check the fit only at the start of a batch, so a batch that has
      // already consumed rows is not cut short. This keeps the preview
      // consistent with the merge service's planning (the reference preview
      // checked on every row and could disagree with the merge).
      if (consumed == 0 &&
          (sequence[seqIdx] <= 0 || sequence[seqIdx] > count - i)) {
        for (var j = i; j < count; j++) {
          result[j] = '-';
        }
        break;
      }
      result[i] = 'Vol.$volNum';
      consumed++;
      if (consumed >= sequence[seqIdx]) {
        volNum++;
        seqIdx++;
        consumed = 0;
      }
    } else {
      result[i] = '-';
    }
  }
  return result;
}
