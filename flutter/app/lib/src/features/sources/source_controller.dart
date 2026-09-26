import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vfs/vfs.dart';

/// The active archive source: a [Vfs] plus the root path it was opened at.
class ArchiveSource {
  const ArchiveSource({
    required this.vfs,
    required this.root,
    required this.label,
  });

  final Vfs vfs;

  /// Browsing root this source was opened at (share-relative for SMB,
  /// absolute for local). Navigation inside [vfs] never climbs above it; the
  /// directory currently listed is `BrowserState.path`.
  final String root;
  final String label;
}

class SourceController extends Notifier<ArchiveSource?> {
  @override
  ArchiveSource? build() => null;

  /// Replaces the browsing source, releasing the previous one's resources
  /// (SMB worker pools) before it is dropped.  Fire-and-forget: closing a pool
  /// must not block the UI.
  void set(ArchiveSource? source) {
    final previous = state;
    state = source;
    if (previous != null && !identical(previous.vfs, source?.vfs)) {
      unawaited(previous.vfs.close());
    }
  }
}

final sourceProvider = NotifierProvider<SourceController, ArchiveSource?>(
  SourceController.new,
);
