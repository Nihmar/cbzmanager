import 'dart:typed_data';

import 'format.dart';
import 'models.dart';
import 'zip_ops.dart';

enum PageChangeKind { deleted, moved, edited, inserted }

class PageChange {
  const PageChange(this.kind, this.pageName);

  final PageChangeKind kind;
  final String pageName;
}

/// In-memory state of one page. Port of `TPageState`.
class PageState {
  PageState({
    required this.origName,
    required this.name,
    this.data,
    this.gone = false,
    this.origIndex = -1,
  });

  /// Name in the source archive (lookup key on save); '' for inserted pages.
  String origName;

  /// Current display/output name.
  String name;

  /// Edited/inserted bytes; wins over the archive entry on save (null = keep).
  Uint8List? data;

  bool gone;
  final int origIndex;

  PageState copy() => PageState(
    origName: origName,
    name: name,
    data: data,
    gone: gone,
    origIndex: origIndex,
  );
}

/// Editable page list with an undo/log and baseline for revert. Port of the
/// pure part of `uPageEditModel`.
class PageEditModel {
  PageEditModel(List<PageState> initial)
    : _baseline = [for (final p in initial) p.copy()],
      pages = [for (final p in initial) p.copy()];

  final List<PageState> pages;
  final List<PageState> _baseline;
  final List<PageChange> changes = <PageChange>[];

  /// Original names of pages removed from [pages]; consumed on save so their
  /// archive entries are not re-added as "leftover" metadata.
  final List<String> deletedOrigNames = <String>[];

  bool get hasChanges => changes.isNotEmpty;
  int get pendingChanges => changes.length;

  List<PageState> get visible => <PageState>[
    for (final p in pages)
      if (!p.gone) p,
  ];

  void _log(PageChangeKind kind, String name) =>
      changes.add(PageChange(kind, name));

  String _key(PageState p) => p.origName.isNotEmpty ? p.origName : p.name;

  void deleteAt(int index) {
    if (index < 0 || index >= pages.length) return;
    deletedOrigNames.add(_key(pages[index]));
    _log(PageChangeKind.deleted, _key(pages[index]));
    pages.removeAt(index);
  }

  void deleteMany(Iterable<int> indices) {
    final sorted = indices.toSet().toList()..sort((a, b) => b.compareTo(a));
    for (final index in sorted) {
      deleteAt(index);
    }
  }

  void move(int from, int to) {
    if (from < 0 || from >= pages.length) return;
    final target = to.clamp(0, pages.length - 1);
    if (from == target) return;
    _log(PageChangeKind.moved, _key(pages[from]));
    final page = pages.removeAt(from);
    pages.insert(target, page);
  }

  void insertAt(int index, List<PageState> newPages) {
    final at = index.clamp(0, pages.length);
    pages.insertAll(at, newPages);
    for (final page in newPages) {
      _log(PageChangeKind.inserted, _key(page));
    }
  }

  /// Records an edited page (new bytes, optionally a new extension/name).
  void markEdited(int index, Uint8List data, {String? name}) {
    if (index < 0 || index >= pages.length) return;
    pages[index].data = data;
    if (name != null) pages[index].name = name;
    _log(PageChangeKind.edited, _key(pages[index]));
  }

  /// Replaces the page at [index] with the first piece and inserts the rest
  /// after it. Each piece is (name, bytes).
  void replaceWithPieces(
    int index,
    List<({String name, Uint8List data})> pieces,
  ) {
    if (index < 0 || index >= pages.length || pieces.isEmpty) return;
    final original = pages[index];
    original.data = pieces.first.data;
    original.name = pieces.first.name;
    _log(PageChangeKind.edited, _key(original));

    if (pieces.length > 1) {
      final inserted = <PageState>[
        for (var i = 1; i < pieces.length; i++)
          PageState(origName: '', name: pieces[i].name, data: pieces[i].data),
      ];
      pages.insertAll(index + 1, inserted);
      for (final page in inserted) {
        _log(PageChangeKind.inserted, page.name);
      }
    }
  }

  /// Renumbers every visible page `page_NNNN.*` (PAGE_PAD_DEFAULT).
  int renumber() {
    var n = 0;
    for (final page in pages) {
      if (page.gone) continue;
      n++;
      page.name = formatPageName(n, extensionOf(page.name));
    }
    return n;
  }

  void revert() {
    pages
      ..clear()
      ..addAll(_baseline.map((p) => p.copy()));
    changes.clear();
    deletedOrigNames.clear();
  }
}

/// Rebuilds an archive from the model.
///
/// Visible pages are written in list order, taking edited/inserted [PageState.data]
/// when present and the original entry otherwise. Non-page entries (e.g.
/// ComicInfo.xml) are preserved, and an original entry is claimed by at most one
/// page. When [renumber] is true surviving pages are renamed `page_NNNN.*`.
Uint8List buildEditedArchive(
  List<ZipEntryData> originalEntries,
  PageEditModel model, {
  required bool renumber,
}) {
  final consumed = List<bool>.filled(originalEntries.length, false);
  // Index entries by lower-case name so each page lookup is O(1) instead of a
  // linear rescan (O(n²) on a long book).  The per-name cursor keeps the
  // linear scan's semantics: the first entry with that name not yet claimed.
  final byName = <String, List<int>>{};
  for (var i = 0; i < originalEntries.length; i++) {
    byName
        .putIfAbsent(originalEntries[i].name.toLowerCase(), () => <int>[])
        .add(i);
  }
  final cursor = <String, int>{};
  int findOriginal(String name) {
    final lower = name.toLowerCase();
    final candidates = byName[lower];
    if (candidates == null) return -1;
    var at = cursor[lower] ?? 0;
    while (at < candidates.length && consumed[candidates[at]]) {
      at++;
    }
    cursor[lower] = at;
    return at < candidates.length ? candidates[at] : -1;
  }

  // Deleted pages still claim their original entry so it is not re-added.
  for (final name in model.deletedOrigNames) {
    final index = findOriginal(name);
    if (index >= 0) consumed[index] = true;
  }

  final output = <ZipEntryData>[];
  var pageNum = 0;
  for (final page in model.pages) {
    final index = page.origName.isEmpty ? -1 : findOriginal(page.origName);
    if (index >= 0) consumed[index] = true;
    if (page.gone) continue;

    final data =
        page.data ?? (index >= 0 ? originalEntries[index].bytes : null);
    if (data == null) {
      // The archive changed under us (or a page reference was lost): fail
      // loudly instead of silently writing an archive without that page.
      // Same contract as the Pascal TSaveChangesThread.
      final name = page.origName.isNotEmpty ? page.origName : page.name;
      throw StateError(
        'Page $name is missing from the archive — nothing was saved',
      );
    }

    pageNum++;
    final name = renumber
        ? formatPageName(pageNum, extensionOf(page.name))
        : page.name;
    output.add(ZipEntryData(name, data));
  }

  // Preserve leftover (non-page) entries such as ComicInfo.xml.
  for (var i = 0; i < originalEntries.length; i++) {
    if (!consumed[i]) output.add(originalEntries[i]);
  }

  return writeZipEntries(output);
}
