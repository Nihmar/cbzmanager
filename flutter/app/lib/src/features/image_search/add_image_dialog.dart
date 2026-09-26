import 'dart:typed_data';

import 'package:flutter/material.dart' hide ImageProvider;

import '../../engine/image_search.dart';
import 'image_search_service.dart';

/// "Add image from internet" dialog. Returns the downloaded bytes with their
/// inferred extension, or null when cancelled.
Future<({Uint8List bytes, String ext, String title})?> showAddImageDialog(
  BuildContext context,
) {
  return showDialog<({Uint8List bytes, String ext, String title})>(
    context: context,
    builder: (context) => const _AddImageDialog(),
  );
}

class _AddImageDialog extends StatefulWidget {
  const _AddImageDialog();

  @override
  State<_AddImageDialog> createState() => _AddImageDialogState();
}

class _AddImageDialogState extends State<_AddImageDialog> {
  final _service = ImageSearchService();
  final _query = TextEditingController();

  ImageProvider _provider = ImageProvider.mangaDex;
  List<ImageResult> _results = const <ImageResult>[];
  bool _searching = false;
  bool _downloading = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _error = null;
      _results = const <ImageResult>[];
    });
    try {
      final results = await _service.search(_provider, _query.text);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(ImageResult result) async {
    setState(() => _downloading = true);
    try {
      final bytes = await _service.download(result.fullUrl);
      if (!mounted) return;
      final ext = result.ext.isNotEmpty
          ? result.ext
          : guessExtFromURL(result.fullUrl);
      Navigator.of(context).pop((
        bytes: bytes,
        ext: ext.isEmpty ? '.jpg' : ext,
        title: result.title,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Add image from internet'),
      content: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ImageProvider>(
                    initialValue: _provider,
                    decoration: const InputDecoration(labelText: 'Source'),
                    items: [
                      for (final p in ImageProvider.values)
                        DropdownMenuItem(
                          value: p,
                          child: Text(providerName(p)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _provider = value ?? _provider),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(
                      labelText: 'Search (or paste an image URL)',
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _searching ? null : _search,
                  icon: _searching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            Expanded(
              child: _downloading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                  ? const Center(child: Text('No results yet'))
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            childAspectRatio: 0.66,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: _downloading ? null : () => _add(result),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: Image.network(
                                    result.thumbUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Icon(Icons.broken_image_outlined),
                                    ),
                                    loadingBuilder:
                                        (context, child, progress) =>
                                            progress == null
                                            ? child
                                            : const Center(
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    result.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
