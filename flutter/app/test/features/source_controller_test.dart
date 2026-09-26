import 'dart:typed_data';

import 'package:cbzmanager/src/features/sources/source_controller.dart';
import 'package:cbzmanager/src/vfs/vfs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal [Vfs] recording whether [close] ran.
class _TrackingVfs extends Vfs {
  bool closed = false;

  @override
  String get scheme => 'fake';

  @override
  Future<List<VfsEntry>> list(String dir) async => const <VfsEntry>[];

  @override
  Future<VfsStat> stat(String path) async => const VfsStat.missing();

  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<Uint8List> readAll(String path) async => Uint8List(0);

  @override
  Future<void> writeAll(String path, List<int> bytes) async {}

  @override
  Future<void> rename(String from, String to) async {}

  @override
  Future<void> delete(String path) async {}

  @override
  Future<void> mkdir(String path) async {}

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  // Regression: replacing the browsing source used to drop the old Vfs
  // without closing it, leaking the SMB worker pool (isolates) on every
  // share switch.
  test('replacing the source closes the previous vfs', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sourceProvider.notifier);
    final first = _TrackingVfs();
    final second = _TrackingVfs();

    notifier.set(ArchiveSource(vfs: first, root: '/', label: 'a'));
    expect(first.closed, isFalse, reason: 'still the active source');

    notifier.set(ArchiveSource(vfs: second, root: '/', label: 'b'));
    await Future<void>.delayed(Duration.zero); // close() is fire-and-forget
    expect(first.closed, isTrue);
    expect(second.closed, isFalse);

    notifier.set(null);
    await Future<void>.delayed(Duration.zero);
    expect(second.closed, isTrue);
  });

  test('re-setting the same source does not close its vfs', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sourceProvider.notifier);
    final vfs = _TrackingVfs();
    final source = ArchiveSource(vfs: vfs, root: '/', label: 'a');

    notifier.set(source);
    notifier.set(source);
    await Future<void>.delayed(Duration.zero);
    expect(vfs.closed, isFalse);
  });
}
