import 'package:cbzmanager/src/engine/comicinfo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips the supported fields through XML', () {
    final info = ComicInfo(
      title: 'The Title',
      series: 'Saga',
      number: '3',
      count: 12,
      volume: 2,
      summary: 'A & B <C>',
      year: 2024,
      month: 6,
      day: 1,
      writer: 'W',
      publisher: 'P',
      genre: 'Sci-Fi',
      pageCount: 32,
      manga: 'No',
      communityRating: 8.5,
    );

    final parsed = ComicInfo.parse(info.toXml());
    expect(parsed.title, 'The Title');
    expect(parsed.series, 'Saga');
    expect(parsed.number, '3');
    expect(parsed.count, 12);
    expect(parsed.volume, 2);
    expect(parsed.summary, 'A & B <C>');
    expect(parsed.year, 2024);
    expect(parsed.pageCount, 32);
    expect(parsed.manga, 'No');
    expect(parsed.communityRating, 8.5);
  });

  test('omits unset values and keeps the reference element order', () {
    final xml = ComicInfo.empty().toXml();
    expect(xml, contains('<ComicInfo'));
    expect(xml, isNot(contains('<Volume>')));
    expect(xml, isNot(contains('<PageCount>')));
    expect(xml.indexOf('<Series>'), lessThan(xml.indexOf('</ComicInfo>') + 1));
  });

  test('parses arbitrary documents and ignores unknown elements', () {
    const xml = '<?xml version="1.0"?><ComicInfo><Series>X</Series>'
        '<Unknown>y</Unknown><PageCount>10</PageCount></ComicInfo>';
    final info = ComicInfo.parse(xml);
    expect(info.series, 'X');
    expect(info.pageCount, 10);
  });

  test('invalid input yields an empty record', () {
    expect(ComicInfo.parse('<not-xml').series, '');
    expect(ComicInfo.parse('').series, '');
  });

  test('escapes XML special characters', () {
    final xml = ComicInfo(series: 'A & B "quote" <tag>').toXml();
    expect(xml, contains('A &amp; B &quot;quote&quot; &lt;tag&gt;'));
    expect(ComicInfo.parse(xml).series, 'A & B "quote" <tag>');
  });
}
