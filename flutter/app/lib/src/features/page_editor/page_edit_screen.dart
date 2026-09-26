import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';

import '../../engine/format.dart';
import '../../engine/page_model.dart';
import '../../engine/zip_ops.dart';
import '../../vfs/vfs.dart';
import '../browser/archive_item.dart';
import '../browser/thumbnail_isolate.dart';
import '../image_search/add_image_dialog.dart';
import 'page_edit_service.dart';
import 'page_editor_dialog.dart';

/// Page editor for one CBZ: grid of pages with delete/move/renumber and a
/// single-page editor (resize / colours / split). Changes are staged in a
/// [PageEditModel] and only written on Save.
class PageEditScreen extends StatefulWidget {
  const PageEditScreen({
    super.key,
    required this.vfs,
    required this.item,
    this.backup = true,
  });

  final Vfs vfs;
  final ArchiveItem item;

  /// Whether saving keeps an `_OLD.cbz` backup (persisted setting).
  final bool backup;

  @override
  State<PageEditScreen> createState() => _PageEditScreenState();
}

class _PageEditScreenState extends State<PageEditScreen> {
  PageEditModel? _model;
  Map<String, Uint8List> _byName = <String, Uint8List>{};
  final Set<int> _selected = <int>{};
  final Map<String, Future<Uint8List?>> _thumbs =
      <String, Future<Uint8List?>>{};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.vfs.readAll(widget.item.path);
      final entries = collectZipEntries(bytes);
      if (!mounted) return;
      setState(() {
        _byName = <String, Uint8List>{for (final e in entries) e.name: e.bytes};
        _model = PageEditService.loadModel(bytes);
        _selected.clear();
        _thumbs.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<int> get _visibleIndices {
    final model = _model;
    if (model == null) return const <int>[];
    return <int>[
      for (var i = 0; i < model.pages.length; i++)
        if (!model.pages[i].gone) i,
    ];
  }

  Future<void> _openEditor(int modelIndex) async {
    final model = _model!;
    final page = model.pages[modelIndex];
    final bytes = page.data ?? _byName[page.origName];
    if (bytes == null) return;

    final pieces = await showPageEditorDialog(
      context,
      pageBytes: bytes,
      pageName: page.name,
    );
    if (pieces == null || !mounted) return;

    final ext = encodeExtFor(extensionOf(page.name));
    final named = <({String name, Uint8List data})>[
      for (var i = 0; i < pieces.length; i++)
        (name: editedPieceName(page.name, ext, i), data: pieces[i]),
    ];
    setState(() {
      model.replaceWithPieces(modelIndex, named);
      _thumbs.clear();
      _selected
        ..clear()
        ..add(modelIndex);
    });
  }

  Future<void> _addImage() async {
    final result = await showAddImageDialog(context);
    if (result == null || !mounted) return;
    final model = _model!;
    setState(() {
      model.insertAt(0, [
        PageState(origName: '', name: 'added${result.ext}', data: result.bytes),
      ]);
      _thumbs.clear();
      _selected
        ..clear()
        ..add(0);
    });
  }

  Future<void> _save() async {
    final model = _model;
    if (model == null) return;
    setState(() => _saving = true);
    try {
      await const PageEditService().save(
        widget.vfs,
        widget.item.path,
        model,
        renumber: true,
        backup: widget.backup,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).changesSaved)),
        );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).saveFailed('$e')),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    final visible = _visibleIndices;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.name),
        actions: [
          IconButton(
            tooltip: l10n.editPage,
            icon: const Icon(Icons.edit_outlined),
            onPressed: _selected.length == 1
                ? () => _openEditor(_selected.first)
                : null,
          ),
          IconButton(
            tooltip: l10n.addImageInternet,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _addImage,
          ),
          IconButton(
            tooltip: l10n.deleteSelected,
            icon: const Icon(Icons.delete_outline),
            onPressed: _selected.isEmpty
                ? null
                : () => setState(() {
                    model!.deleteMany(_selected);
                    _selected.clear();
                    _thumbs.clear();
                  }),
          ),
          IconButton(
            tooltip: l10n.moveEarlier,
            icon: const Icon(Icons.arrow_upward),
            onPressed: _selected.isEmpty
                ? null
                : () => setState(() {
                    for (final i in _selected.toList()..sort()) {
                      model!.move(i, i - 1);
                    }
                    _selected.clear();
                    _thumbs.clear();
                  }),
          ),
          IconButton(
            tooltip: l10n.moveLater,
            icon: const Icon(Icons.arrow_downward),
            onPressed: _selected.isEmpty
                ? null
                : () => setState(() {
                    for (final i in _selected.toList()..sort((a, b) => b - a)) {
                      model!.move(i, i + 1);
                    }
                    _selected.clear();
                    _thumbs.clear();
                  }),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'renumber') {
                setState(() {
                  model!.renumber();
                  _thumbs.clear();
                });
              } else if (value == 'revert') {
                setState(() {
                  model!.revert();
                  _selected.clear();
                  _thumbs.clear();
                });
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'renumber', child: Text(l10n.renumberPages)),
              PopupMenuItem(value: 'revert', child: Text(l10n.revertChanges)),
            ],
          ),
        ],
      ),
      body: _buildBody(model, visible),
      bottomNavigationBar: model == null || !model.hasChanges
          ? null
          : BottomAppBar(
              child: Row(
                children: [
                  Text(l10n.pendingChanges(model.pendingChanges)),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            model.revert();
                            _selected.clear();
                            _thumbs.clear();
                          }),
                    child: Text(l10n.revert),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(l10n.saveChanges),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildBody(PageEditModel? model, List<int> visible) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (model == null || visible.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context).noPages));
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: visible.length,
      onReorderItem: (oldIndex, newIndex) {
        setState(() {
          model.move(oldIndex, newIndex);
          _selected.clear();
          _thumbs.clear();
        });
      },
      itemBuilder: (context, gridIndex) {
        final modelIndex = visible[gridIndex];
        final page = model.pages[modelIndex];
        final bytes = page.data ?? _byName[page.origName];
        final selected = _selected.contains(modelIndex);
        final key =
            '${identityHashCode(page)}:${page.data != null ? identityHashCode(page.data) : page.origName}';
        final future = bytes == null
            ? Future<Uint8List?>.value()
            : _thumbs.putIfAbsent(
                key,
                () => decodeBytesThumbnailInIsolate(bytes, 120, 160),
              );

        return Card(
          key: ValueKey(page),
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            selected: selected,
            onTap: () => setState(() {
              if (!_selected.remove(modelIndex)) _selected.add(modelIndex);
            }),
            leading: SizedBox(
              width: 44,
              height: 60,
              child: FutureBuilder<Uint8List?>(
                future: future,
                builder: (context, snapshot) {
                  final thumb = snapshot.data;
                  if (thumb == null) {
                    return const Center(child: Icon(Icons.image_outlined));
                  }
                  return Image.memory(thumb, fit: BoxFit.contain);
                },
              ),
            ),
            title: Text(
              page.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              AppLocalizations.of(context).pageNumberLabel(gridIndex + 1),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: AppLocalizations.of(context).editPage,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openEditor(modelIndex),
                ),
                ReorderableDragStartListener(
                  index: gridIndex,
                  child: const Icon(Icons.drag_handle),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
