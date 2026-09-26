@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// Integration test for the headless CLI: it must run under plain `dart run`
/// (no Flutter widgetset) and honour the reference exit codes.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cbzmanager-cli');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<ProcessResult> run(List<String> args) =>
      Process.run('dart', ['run', 'bin/cbzmanager.dart', ...args]);

  test('--version exits 0 and prints the version', () async {
    final result = await run(['--version']);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('cbzmanager'));
  });

  test('an unknown command exits 2', () async {
    final result = await run(['bogus']);
    expect(result.exitCode, 2);
  });

  test('a missing directory exits 2', () async {
    final result = await run(['validate']);
    expect(result.exitCode, 2);
  });

  test('--chapters with --chapters-per-volume exits 1', () async {
    // Runtime error, not a usage error: the reference returns 1 here.
    final result = await run([
      'merge',
      tmp.path,
      '--chapters',
      '2',
      '--chapters-per-volume',
      '3',
    ]);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('mutually exclusive'));
  });

  test('validate rejects merge-only flags with exit 2', () async {
    final result = await run(['validate', tmp.path, '--force']);
    expect(result.exitCode, 2);
    expect(result.stderr, contains('not valid'));
  });

  test('convert-webp on a ComicInfo-only archive exits 0', () async {
    // Benign no-op like the reference ("already up to date"), not a failure.
    File('${tmp.path}/empty.cbz')
        .writeAsBytesSync(makeZip({'ComicInfo.xml': '<ComicInfo/>'.codeUnits}));
    final result = await run(['convert-webp', tmp.path]);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('SKIP empty.cbz'));
  });
}
