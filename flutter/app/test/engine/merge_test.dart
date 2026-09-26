import 'dart:convert';

import 'package:cbzmanager/src/engine/comicinfo.dart';
import 'package:cbzmanager/src/engine/merge.dart';
import 'package:cbzmanager/src/engine/zip_ops.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  group('filename classification', () {
    test('extractChapterNum', () {
      expect(extractChapterNumStr('Test - 001.cbz'), '001');
      expect(extractChapterNumStr('Spider-Man - 010.cbz'), '010');
      expect(extractChapterNumStr('Test - 010.5.cbz'), '010.5');
      expect(extractChapterNumStr('Test V002.cbz'), 'V002');
      expect(extractChapterNum('Test - 010.5.cbz'), 10);
      expect(extractChapterNum('Test - 010_15.cbz'), 10);
    });

    test('isVolumeFile is strict', () {
      expect(isVolumeFile('Test V001.cbz', 'Test'), isTrue);
      expect(isVolumeFile('Test V001_OLD.cbz', 'Test'), isFalse);
      expect(isVolumeFile('Other V001.cbz', 'Test'), isFalse);
      expect(isVolumeFile('Test - 001.cbz', 'Test'), isFalse);
    });

    test('classifyChapter accepts numeric, sub-chapter and special tags', () {
      expect(classifyChapter('Test - 001.cbz')!.number, 1);
      expect(classifyChapter('Test - 010_15.cbz')!.number, 10);
      expect(classifyChapter('Test - SP01.cbz')!.isSpecial, isTrue);
      expect(classifyChapter('Test - 001_OLD.cbz'), isNull);
      expect(classifyChapter('Test - 010.5.cbz'), isNull);
      expect(classifyChapter('Test V001.cbz'), isNull);
    });

    test('detectSeriesName uses the rightmost " -"', () {
      expect(detectSeriesName(['Spider-Man - 001.cbz']), 'Spider-Man');
      expect(detectSeriesName(['a.txt', 'Bleach - 01.cbz']), 'Bleach');
    });
  });

  group('CPV and numbering', () {
    test('auto CPV is (lowest-1)/volumes with real division', () {
      final files = ['Test V001.cbz', 'Test - 05.cbz', 'Test - 06.cbz'];
      expect(calculateChaptersPerVolumeFloat(files, 'Test'), 4.0);
      expect(calculateChaptersPerVolume(files, 'Test'), 4);
    });

    test('lastVolumeNumber ignores backups and other series', () {
      final files = [
        'Test V001.cbz',
        'Test V012.cbz',
        'Test V012_OLD.cbz',
        'Other V099.cbz',
      ];
      expect(lastVolumeNumber(files, 'Test'), 12);
    });

    test('lastVolumeNumber parses numbers of any width', () {
      // Regression: the substring offset was copied from Pascal's 1-based
      // Copy, so "V100" parsed as "00" and every 3-digit volume was ignored
      // (a merge then restarted at V100 and overwrote the existing file).
      expect(isVolumeFile('Test V100.cbz', 'Test'), isTrue);
      expect(lastVolumeNumber(['Test V099.cbz', 'Test V100.cbz'], 'Test'), 100);
      expect(lastVolumeNumber(['Test V123.cbz'], 'Test'), 123);
      expect(lastVolumeNumber(['Test V1000.cbz'], 'Test'), 1000);
    });

    test('collectChapters orders specials after regular chapters', () {
      final chapters = collectChapters([
        'Test - 003.cbz',
        'Test - 001.cbz',
        'Test - SP01.cbz',
      ], 'Test');
      expect(chapters.map((c) => c.number).toList(), [1, 3, 4]);
      expect(chapters.last.isSpecial, isTrue);
    });
  });

  group('planMerge', () {
    List<String> chapters(int n) => [
      for (var i = 1; i <= n; i++) 'Test - ${i.toString().padLeft(2, '0')}.cbz',
    ];

    test('only full volumes without force', () {
      final result = planMerge(
        chapters(5),
        const MergeOptions(chaptersPerVolume: 2),
      );
      expect(result.error, isNull);
      expect(result.plan!.batches.length, 2);
      expect(result.plan!.batches.first.files.length, 2);
    });

    test('force absorbs the remainder into the last volume', () {
      final result = planMerge(
        chapters(5),
        const MergeOptions(chaptersPerVolume: 2, force: true),
      );
      expect(result.plan!.batches.length, 2);
      expect(result.plan!.batches.last.files.length, 3);
    });

    test('custom sequence plans one batch per list entry', () {
      final result = planMerge(
        chapters(6),
        const MergeOptions(chaptersList: [1, 2, 3]),
      );
      expect(result.plan!.batches.map((b) => b.files.length).toList(), [
        1,
        2,
        3,
      ]);
    });

    test('no chapters yields an error', () {
      final result = planMerge([
        'Test V001.cbz',
      ], const MergeOptions(seriesName: 'Test'));
      expect(result.error, isNotNull);
    });

    test('continues after existing volumes', () {
      final files = [...chapters(4), 'Test V001.cbz'];
      final result = planMerge(files, const MergeOptions(chaptersPerVolume: 2));
      expect(result.plan!.batches.first.fileName, 'Test V002.cbz');
    });
  });

  test('customSequenceLabels marks overflow rows as unassigned', () {
    expect(customSequenceLabels(5, [2, 3], 0), [
      'Vol.1',
      'Vol.1',
      'Vol.2',
      'Vol.2',
      'Vol.2',
    ]);
    expect(customSequenceLabels(3, [5], 0), ['-', '-', '-']);
  });

  group('buildVolumeBytes', () {
    test('merges images, renumbers and optionally adds ComicInfo', () {
      final a = makeZip({'a1.png': makeSolidPng(8, 8)});
      final b = makeZip({
        'b1.png': makeSolidPng(8, 8),
        'ComicInfo.xml': [1],
      });

      final bytes = buildVolumeBytes(
        [a, b],
        seriesName: 'Test',
        volNum: 2,
        chapterNumbers: [5, 6],
        generateComicInfo: true,
      )!;

      final entries = collectZipEntries(bytes);
      expect(entries.map((e) => e.name).toList(), [
        'page_001.png',
        'page_002.png',
        'ComicInfo.xml',
      ]);
      final info = ComicInfo.parse(
        utf8.decode(entries.last.bytes, allowMalformed: true),
      );
      expect(info.series, 'Test');
      expect(info.number, '5-6');
      expect(info.volume, 2);
    });

    test('an imageless batch produces no volume', () {
      final empty = makeZip({
        'credits.txt': [1, 2],
      });
      expect(
        buildVolumeBytes(
          [empty],
          seriesName: 'Test',
          volNum: 1,
          chapterNumbers: [1],
        ),
        isNull,
      );
    });
  });
}
