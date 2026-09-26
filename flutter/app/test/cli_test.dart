@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Integration test for the headless CLI: it must run under plain `dart run`
/// (no Flutter widgetset) and honour the reference exit codes.
void main() {
  test('--version exits 0 and prints the version', () async {
    final result = await Process.run('dart', [
      'run',
      'bin/cbzmanager.dart',
      '--version',
    ]);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('cbzmanager'));
  });

  test('an unknown command exits 2', () async {
    final result = await Process.run('dart', [
      'run',
      'bin/cbzmanager.dart',
      'bogus',
    ]);
    expect(result.exitCode, 2);
  });

  test('a missing directory exits 2', () async {
    final result = await Process.run('dart', [
      'run',
      'bin/cbzmanager.dart',
      'validate',
    ]);
    expect(result.exitCode, 2);
  });
}
