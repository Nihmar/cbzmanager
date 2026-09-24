import 'package:flutter/material.dart';

import '../../engine/comicinfo.dart';

/// Opens the ComicInfo viewer/editor. Returns the edited metadata, or null when
/// cancelled. Pass null [initial] to create a fresh record.
Future<ComicInfo?> showComicInfoEditor(
  BuildContext context, {
  required String archiveName,
  ComicInfo? initial,
}) {
  return showDialog<ComicInfo>(
    context: context,
    builder: (context) => _ComicInfoEditorDialog(
      archiveName: archiveName,
      initial: initial ?? ComicInfo.empty(),
    ),
  );
}

class _ComicInfoEditorDialog extends StatefulWidget {
  const _ComicInfoEditorDialog({
    required this.archiveName,
    required this.initial,
  });

  final String archiveName;
  final ComicInfo initial;

  @override
  State<_ComicInfoEditorDialog> createState() => _ComicInfoEditorDialogState();
}

class _ComicInfoEditorDialogState extends State<_ComicInfoEditorDialog> {
  late final ComicInfo _i = widget.initial;

  late final _series = TextEditingController(text: _i.series);
  late final _number = TextEditingController(text: _i.number);
  late final _title = TextEditingController(text: _i.title);
  late final _writer = TextEditingController(text: _i.writer);
  late final _penciller = TextEditingController(text: _i.penciller);
  late final _publisher = TextEditingController(text: _i.publisher);
  late final _genre = TextEditingController(text: _i.genre);
  late final _web = TextEditingController(text: _i.web);
  late final _language = TextEditingController(text: _i.languageIso);
  late final _manga = TextEditingController(text: _i.manga);
  late final _ageRating = TextEditingController(text: _i.ageRating);
  late final _summary = TextEditingController(text: _i.summary);

  late final _volume = TextEditingController(text: _num(_i.volume));
  late final _count = TextEditingController(text: _num(_i.count));
  late final _year = TextEditingController(text: _num(_i.year));
  late final _month = TextEditingController(text: _num(_i.month));
  late final _day = TextEditingController(text: _num(_i.day));
  late final _pageCount = TextEditingController(text: _num(_i.pageCount));
  late final _rating = TextEditingController(text: _ratingText(_i.communityRating));

  static String _num(int v) => v == kComicUnsetInt ? '' : '$v';
  static String _ratingText(double v) =>
      v == kComicUnsetRating ? '' : v.toString();

  @override
  void dispose() {
    for (final controller in [
      _series, _number, _title, _writer, _penciller, _publisher, _genre,
      _web, _language, _manga, _ageRating, _summary, _volume, _count,
      _year, _month, _day, _pageCount, _rating,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int _intOf(TextEditingController c) {
    final raw = c.text.trim();
    if (raw.isEmpty) return kComicUnsetInt;
    return int.tryParse(raw) ?? kComicUnsetInt;
  }

  double _doubleOf(TextEditingController c) {
    final raw = c.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return kComicUnsetRating;
    return double.tryParse(raw) ?? kComicUnsetRating;
  }

  ComicInfo _collect() => ComicInfo(
        title: _title.text,
        series: _series.text,
        number: _number.text,
        count: _intOf(_count),
        volume: _intOf(_volume),
        alternateSeries: _i.alternateSeries,
        alternateNumber: _i.alternateNumber,
        alternateCount: _i.alternateCount,
        summary: _summary.text,
        notes: _i.notes,
        year: _intOf(_year),
        month: _intOf(_month),
        day: _intOf(_day),
        writer: _writer.text,
        penciller: _penciller.text,
        inker: _i.inker,
        colorist: _i.colorist,
        letterer: _i.letterer,
        coverArtist: _i.coverArtist,
        editor: _i.editor,
        publisher: _publisher.text,
        imprint: _i.imprint,
        genre: _genre.text,
        tags: _i.tags,
        web: _web.text,
        pageCount: _intOf(_pageCount),
        languageIso: _language.text,
        format: _i.format,
        blackAndWhite: _i.blackAndWhite,
        manga: _manga.text,
        characters: _i.characters,
        teams: _i.teams,
        locations: _i.locations,
        scanInformation: _i.scanInformation,
        storyArc: _i.storyArc,
        storyArcNumber: _i.storyArcNumber,
        seriesGroup: _i.seriesGroup,
        ageRating: _ageRating.text,
        communityRating: _doubleOf(_rating),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('ComicInfo — ${widget.archiveName}'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _text('Series', _series)),
                  const SizedBox(width: 12),
                  Expanded(child: _text('Number', _number)),
                  const SizedBox(width: 12),
                  Expanded(child: _text('Volume', _volume, numeric: true)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _text('Title', _title)),
                  const SizedBox(width: 12),
                  Expanded(child: _text('Count', _count, numeric: true)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _text('Writer', _writer)),
                  const SizedBox(width: 12),
                  Expanded(child: _text('Penciller', _penciller)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _text('Publisher', _publisher)),
                  const SizedBox(width: 12),
                  Expanded(child: _text('Genre', _genre)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _text('Year', _year, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _text('Month', _month, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _text('Day', _day, numeric: true)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _text('Page count', _pageCount, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _text('Community rating', _rating, numeric: true),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _text('Language ISO', _language)),
                  const SizedBox(width: 12),
                  Expanded(child: _text('Manga', _manga)),
                  const SizedBox(width: 12),
                  Expanded(child: _text('Age rating', _ageRating)),
                ],
              ),
              _text('Web', _web),
              _text('Summary', _summary, lines: 4),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_collect()),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Widget _text(
    String label,
    TextEditingController controller, {
    bool numeric = false,
    int lines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: lines,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
