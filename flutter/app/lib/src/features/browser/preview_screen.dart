import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vfs/vfs.dart';
import 'archive_item.dart';
import 'thumbnail_service.dart';

/// Immersive page reader: swipe through pages, pinch/double-tap to zoom, with a
/// thumbnail rail for quick navigation. CBR archives are read-only.
class PreviewScreen extends ConsumerStatefulWidget {
  const PreviewScreen({super.key, required this.vfs, required this.item});

  final Vfs vfs;
  final ArchiveItem item;

  @override
  ConsumerState<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends ConsumerState<PreviewScreen> {
  final _controller = PageController();
  Uint8List? _bytes;
  int _pageCount = 0;
  int _current = 0;
  bool _loading = true;
  String? _error;

  String get _keyBase => '${widget.vfs.scheme}:${widget.item.path}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.vfs.readAll(widget.item.path);
      final count = await ref
          .read(thumbnailServiceProvider)
          .pageCount(bytes, widget.item.name);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _pageCount = count;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _goTo(int index) {
    if (index < 0 || index >= _pageCount) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.name,
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
            if (_pageCount > 0)
              Text(
                '${_current + 1} / $_pageCount',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white70),
              ),
          ],
        ),
        actions: [
          if (widget.item.isCbr)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: const Icon(Icons.lock_outline, size: 16),
                label: const Text('read-only'),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar:
          _pageCount > 1 && _bytes != null ? _buildRail(context) : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.white54),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }
    if (_pageCount == 0) {
      return const Center(
        child: Text('No pages', style: TextStyle(color: Colors.white70)),
      );
    }

    final service = ref.read(thumbnailServiceProvider);
    return PageView.builder(
      controller: _controller,
      itemCount: _pageCount,
      onPageChanged: (i) => setState(() => _current = i),
      itemBuilder: (context, index) => _PageView(
        future: service.pageThumbnail(
          '$_keyBase:main',
          _bytes!,
          widget.item.name,
          index,
        ),
      ),
    );
  }

  Widget _buildRail(BuildContext context) {
    final service = ref.read(thumbnailServiceProvider);
    return Container(
      height: 92,
      color: Colors.black.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _pageCount,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == _current;
          return GestureDetector(
            onTap: () => _goTo(index),
            child: Container(
              width: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? Theme.of(context).colorScheme.primary : Colors.white24,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: FutureBuilder<Uint8List?>(
                future: service.pageThumbnail(
                  '$_keyBase:rail',
                  _bytes!,
                  widget.item.name,
                  index,
                  maxWidth: 96,
                  maxHeight: 128,
                ),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return const SizedBox.shrink();
                  }
                  return Image.memory(bytes, fit: BoxFit.cover);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({required this.future});

  final Future<Uint8List?> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
          );
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Center(
            child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
          ),
        );
      },
    );
  }
}
