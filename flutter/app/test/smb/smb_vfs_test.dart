import 'dart:io';
import 'dart:typed_data';

import 'package:cbzmanager/src/engine/dart_engine.dart';
import 'package:cbzmanager/src/engine/models.dart';
import 'package:cbzmanager/src/vfs/smb_vfs.dart';
import 'package:cbzmanager/src/vfs/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Live SMB integration test. Disabled by default; set `CBZ_SMB_TEST=1` and
/// point it at a share to run. CI runs it against a Samba container (see
/// `flutter/PLAN.md`).
///
/// A local Samba container with user `test`/`testpass` and share `books`
/// bound to host port 445 is enough.
void main() {
  final enabled = Platform.environment['CBZ_SMB_TEST'] == '1';

  test('SmbVfs round-trip against a live share', () async {
    if (!enabled) {
      markTestSkipped('set CBZ_SMB_TEST=1 to run the live SMB test');
      return;
    }

    final vfs = SmbVfs(
      SmbConfig(
        host: Platform.environment['CBZ_SMB_HOST'] ?? '127.0.0.1',
        share: Platform.environment['CBZ_SMB_SHARE'] ?? 'books',
        user: Platform.environment['CBZ_SMB_USER'] ?? 'test',
        password: Platform.environment['CBZ_SMB_PASSWORD'] ?? 'testpass',
        workers: 1,
      ),
    );

    try {
      await vfs.mkdir('poc');
      await vfs.writeAll(
        'poc/hello.txt',
        Uint8List.fromList('ciao'.codeUnits),
      );

      expect(await vfs.exists('poc/hello.txt'), isTrue);
      expect(String.fromCharCodes(await vfs.readAll('poc/hello.txt')), 'ciao');

      final stat = await vfs.stat('poc/hello.txt');
      expect(stat.exists, isTrue);
      expect(stat.isDirectory, isFalse);
      expect(stat.size, 4);

      final names = (await vfs.list('poc')).map((e) => e.name).toList();
      expect(names, contains('hello.txt'));

      await vfs.rename('poc/hello.txt', 'poc/bye.txt');
      expect(await vfs.exists('poc/hello.txt'), isFalse);
      expect(await vfs.exists('poc/bye.txt'), isTrue);

      await vfs.delete('poc/bye.txt');
      expect(await vfs.exists('poc/bye.txt'), isFalse);
      await vfs.delete('poc');
    } finally {
      await vfs.disconnect();
    }
  });

  test('engine + workspace round-trip over SMB', () async {
    if (!enabled) {
      markTestSkipped('set CBZ_SMB_TEST=1 to run the live SMB test');
      return;
    }

    final vfs = SmbVfs(
      SmbConfig(
        host: Platform.environment['CBZ_SMB_HOST'] ?? '127.0.0.1',
        share: Platform.environment['CBZ_SMB_SHARE'] ?? 'books',
        user: Platform.environment['CBZ_SMB_USER'] ?? 'test',
        password: Platform.environment['CBZ_SMB_PASSWORD'] ?? 'testpass',
        workers: 1,
      ),
    );
    const engine = DartCbzEngine();
    const workspace = Workspace();

    try {
      final source = makeZip({'page_001.png': makeNoisePng(96, 96)});
      await vfs.mkdir('engine');
      await vfs.writeAll('engine/book.cbz', source);

      final data = await workspace.read(vfs, 'engine/book.cbz');
      expect((await engine.validate(data)).valid, isTrue);

      final converted = await engine.convertWebp(
        data,
        const ConvertOptions(),
      );
      expect(converted.success, isTrue);
      expect(converted.converted, 1);

      await workspace.publish(vfs, 'engine/book.cbz', converted.output!);
      expect(await vfs.exists('engine/book_OLD.cbz'), isTrue);

      final reparsed = await workspace.read(vfs, 'engine/book.cbz');
      expect((await engine.validate(reparsed)).valid, isTrue);

      await vfs.delete('engine/book.cbz');
      await vfs.delete('engine/book_OLD.cbz');
      await vfs.delete('engine');
    } finally {
      await vfs.disconnect();
    }
  });
}
