import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'models.dart';
import 'zip_ops.dart';

/// Sentinel for "unset" integer fields, matching the reference `UNSET_INT`.
const int kComicUnsetInt = -1;

/// Sentinel for "unset" rating, matching the reference `UNSET_RATING`.
const double kComicUnsetRating = -1.0;

/// ComicInfo.xml metadata. Port of `ucomicinfo.pas` `TComicInfo`.
class ComicInfo {
  ComicInfo({
    this.title = '',
    this.series = '',
    this.number = '',
    this.count = kComicUnsetInt,
    this.volume = kComicUnsetInt,
    this.alternateSeries = '',
    this.alternateNumber = '',
    this.alternateCount = kComicUnsetInt,
    this.summary = '',
    this.notes = '',
    this.year = kComicUnsetInt,
    this.month = kComicUnsetInt,
    this.day = kComicUnsetInt,
    this.writer = '',
    this.penciller = '',
    this.inker = '',
    this.colorist = '',
    this.letterer = '',
    this.coverArtist = '',
    this.editor = '',
    this.publisher = '',
    this.imprint = '',
    this.genre = '',
    this.tags = '',
    this.web = '',
    this.pageCount = kComicUnsetInt,
    this.languageIso = '',
    this.format = '',
    this.blackAndWhite = '',
    this.manga = '',
    this.characters = '',
    this.teams = '',
    this.locations = '',
    this.scanInformation = '',
    this.storyArc = '',
    this.storyArcNumber = '',
    this.seriesGroup = '',
    this.ageRating = '',
    this.communityRating = kComicUnsetRating,
  });

  factory ComicInfo.empty() => ComicInfo();

  String title;
  String series;
  String number;
  int count;
  int volume;
  String alternateSeries;
  String alternateNumber;
  int alternateCount;
  String summary;
  String notes;
  int year;
  int month;
  int day;
  String writer;
  String penciller;
  String inker;
  String colorist;
  String letterer;
  String coverArtist;
  String editor;
  String publisher;
  String imprint;
  String genre;
  String tags;
  String web;
  int pageCount;
  String languageIso;
  String format;
  String blackAndWhite;
  String manga;
  String characters;
  String teams;
  String locations;
  String scanInformation;
  String storyArc;
  String storyArcNumber;
  String seriesGroup;
  String ageRating;
  double communityRating;

  /// Parses a ComicInfo.xml document. Empty/invalid input yields [ComicInfo.empty].
  static ComicInfo parse(String xml) {
    if (xml.trim().isEmpty) return ComicInfo.empty();
    final XmlElement root;
    try {
      root = XmlDocument.parse(xml).rootElement;
    } catch (_) {
      return ComicInfo.empty();
    }

    String text(String tag) => root.getElement(tag)?.innerText ?? '';
    int asInt(String tag) {
      final raw = text(tag).trim();
      if (raw.isEmpty) return kComicUnsetInt;
      return int.tryParse(raw) ?? kComicUnsetInt;
    }

    double asDouble(String tag) {
      final raw = text(tag).trim();
      if (raw.isEmpty) return kComicUnsetRating;
      return double.tryParse(raw.replaceAll(',', '.')) ?? kComicUnsetRating;
    }

    return ComicInfo(
      title: text('Title'),
      series: text('Series'),
      number: text('Number'),
      count: asInt('Count'),
      volume: asInt('Volume'),
      alternateSeries: text('AlternateSeries'),
      alternateNumber: text('AlternateNumber'),
      alternateCount: asInt('AlternateCount'),
      summary: text('Summary'),
      notes: text('Notes'),
      year: asInt('Year'),
      month: asInt('Month'),
      day: asInt('Day'),
      writer: text('Writer'),
      penciller: text('Penciller'),
      inker: text('Inker'),
      colorist: text('Colorist'),
      letterer: text('Letterer'),
      coverArtist: text('CoverArtist'),
      editor: text('Editor'),
      publisher: text('Publisher'),
      imprint: text('Imprint'),
      genre: text('Genre'),
      tags: text('Tags'),
      web: text('Web'),
      pageCount: asInt('PageCount'),
      languageIso: text('LanguageISO'),
      format: text('Format'),
      blackAndWhite: text('BlackAndWhite'),
      manga: text('Manga'),
      characters: text('Characters'),
      teams: text('Teams'),
      locations: text('Locations'),
      scanInformation: text('ScanInformation'),
      storyArc: text('StoryArc'),
      storyArcNumber: text('StoryArcNumber'),
      seriesGroup: text('SeriesGroup'),
      ageRating: text('AgeRating'),
      communityRating: asDouble('CommunityRating'),
    );
  }

  /// Serialises to the same shape/order as `GenerateComicInfoXML`.
  String toXml() {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="utf-8"?>\n')
      ..write('<ComicInfo xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
          'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n');

    void elem(String tag, String value) {
      if (value.isNotEmpty) {
        b.write('  <$tag>${_escape(value)}</$tag>\n');
      }
    }

    void intElem(String tag, int value) {
      if (value != kComicUnsetInt) b.write('  <$tag>$value</$tag>\n');
    }

    void doubleElem(String tag, double value) {
      if (value > kComicUnsetRating + 0.5) {
        final text = value == value.roundToDouble()
            ? value.toInt().toString()
            : value.toString();
        b.write('  <$tag>$text</$tag>\n');
      }
    }

    elem('Title', title);
    elem('Series', series);
    elem('Number', number);
    intElem('Count', count);
    intElem('Volume', volume);
    elem('AlternateSeries', alternateSeries);
    elem('AlternateNumber', alternateNumber);
    intElem('AlternateCount', alternateCount);
    elem('Summary', summary);
    elem('Notes', notes);
    intElem('Year', year);
    intElem('Month', month);
    intElem('Day', day);
    elem('Writer', writer);
    elem('Penciller', penciller);
    elem('Inker', inker);
    elem('Colorist', colorist);
    elem('Letterer', letterer);
    elem('CoverArtist', coverArtist);
    elem('Editor', editor);
    elem('Publisher', publisher);
    elem('Imprint', imprint);
    elem('Genre', genre);
    elem('Tags', tags);
    elem('Web', web);
    intElem('PageCount', pageCount);
    elem('LanguageISO', languageIso);
    elem('Format', format);
    elem('BlackAndWhite', blackAndWhite);
    elem('Manga', manga);
    elem('Characters', characters);
    elem('Teams', teams);
    elem('Locations', locations);
    elem('ScanInformation', scanInformation);
    elem('StoryArc', storyArc);
    elem('StoryArcNumber', storyArcNumber);
    elem('SeriesGroup', seriesGroup);
    elem('AgeRating', ageRating);
    doubleElem('CommunityRating', communityRating);

    b.write('</ComicInfo>\n');
    return b.toString();
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// Parses ComicInfo.xml from already-collected entries, or null when absent.
ComicInfo? comicInfoFromEntries(List<ZipEntryData> entries) {
  final index = findComicInfoIndex(entries);
  if (index < 0) return null;
  final xml = utf8.decode(entries[index].bytes, allowMalformed: true);
  return ComicInfo.parse(xml);
}

/// Returns a copy of [entries] with ComicInfo.xml replaced or appended.
List<ZipEntryData> withComicInfo(
  List<ZipEntryData> entries,
  ComicInfo info,
) {
  final xml = info.toXml();
  final result = <ZipEntryData>[...entries];
  final index = findComicInfoIndex(result);
  final entry = ZipEntryData(
    comicInfoName,
    Uint8List.fromList(utf8.encode(xml)),
  );
  if (index >= 0) {
    result[index] = entry;
  } else {
    result.add(entry);
  }
  return result;
}
