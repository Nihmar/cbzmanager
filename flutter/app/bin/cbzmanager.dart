// Headless CLI for CBZ Manager, mirroring the Lazarus binary's commands and
// exit codes (0 success/benign no-op, 1 runtime error, 2 usage error).
//
// Only the pure-Dart engine/services are imported (no Flutter), so this runs
// with `dart run bin/cbzmanager.dart ...`.
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:cbzmanager/src/engine/merge.dart';
import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/features/cbr/cbr_service.dart';
import 'package:cbzmanager/src/features/convert/convert_service.dart';
import 'package:cbzmanager/src/features/merge/merge_service.dart';
import 'package:cbzmanager/src/features/validate/validate_service.dart';
import 'package:cbzmanager/src/engine/dart_engine.dart';
import 'package:cbzmanager/src/vfs/local_vfs.dart';
import 'package:cbzmanager/src/vfs/vfs.dart';

const String _version = '1.0.0';
const int _exitOk = 0;
const int _exitError = 1;
const int _exitUsage = 2;

const Set<String> _commands = {
  'validate',
  'convert-webp',
  'merge',
  'cbr-to-cbz',
};

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h' || args.first == 'help') {
    _usage();
    exit(args.isEmpty ? _exitUsage : _exitOk);
  }
  if (args.first == '--version') {
    stdout.writeln('cbzmanager $_version');
    exit(_exitOk);
  }

  final command = args.first;
  if (!_commands.contains(command)) {
    stderr.writeln("Error: unknown command '$command'");
    exit(_exitUsage);
  }

  final options = _parseOptions(args.skip(1).toList());
  if (options.error != null) {
    stderr.writeln('Error: ${options.error}');
    stderr.writeln('Try \'cbzmanager --help\' for usage.');
    exit(_exitUsage);
  }
  final dir = options.directory;
  if (dir == null) {
    stderr.writeln("Error: missing directory for '$command'");
    exit(_exitUsage);
  }
  if (!Directory(dir).existsSync()) {
    stderr.writeln('Error: not a directory: $dir');
    exit(_exitError);
  }

  final vfs = const LocalVfs();
  switch (command) {
    case 'validate':
      exit(await _validate(vfs, dir, options));
    case 'convert-webp':
      exit(await _convert(vfs, dir, options));
    case 'merge':
      exit(await _merge(vfs, dir, options));
    case 'cbr-to-cbz':
      exit(await _cbrToCbz(vfs, dir, options));
  }
}

class _Options {
  String? directory;
  int threads = 0;
  bool delete = false;
  bool force = false;
  List<int>? chapters;
  int chaptersPerVolume = 0;
  String? error;
}

_Options _parseOptions(List<String> args) {
  final options = _Options();
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--delete':
        options.delete = true;
      case '--force':
        options.force = true;
      case '--threads':
        if (i + 1 >= args.length) {
          options.error = '--threads expects a value';
          return options;
        }
        final v = int.tryParse(args[++i]);
        if (v == null || v < 0) {
          options.error = '--threads expects a positive integer';
          return options;
        }
        options.threads = v;
      case '--chapters-per-volume':
        if (i + 1 >= args.length) {
          options.error = '--chapters-per-volume expects a value';
          return options;
        }
        final v = int.tryParse(args[++i]);
        if (v == null || v < 1) {
          options.error = '--chapters-per-volume expects a positive integer';
          return options;
        }
        options.chaptersPerVolume = v;
      case '--chapters':
        if (i + 1 >= args.length) {
          options.error = '--chapters expects a value';
          return options;
        }
        final parts = args[++i].split(',');
        final values = <int>[];
        for (final part in parts) {
          final v = int.tryParse(part.trim());
          if (v == null || v < 1) {
            options.error = '--chapters expects a comma-separated list of positive integers';
            return options;
          }
          values.add(v);
        }
        options.chapters = values;
      default:
        if (arg.startsWith('-')) {
          options.error = "unknown option '$arg'";
          return options;
        }
        if (options.directory != null) {
          options.error = 'unexpected argument: $arg';
          return options;
        }
        options.directory = arg;
    }
  }
  if (options.chapters != null && options.chaptersPerVolume > 0) {
    options.error = '--chapters and --chapters-per-volume are mutually exclusive';
  }
  return options;
}

Future<List<ArchiveItem>> _archives(
  Vfs vfs,
  String dir, {
  required String extension,
}) async {
  final entries = await vfs.list(dir);
  return <ArchiveItem>[
    for (final entry in entries)
      if (!entry.isDirectory && entry.name.toLowerCase().endsWith(extension))
        ArchiveItem(
          name: entry.name,
          path: p.join(dir, entry.name),
          size: entry.size,
          isCbr: extension == '.cbr',
        ),
  ];
}

Future<int> _validate(Vfs vfs, String dir, _Options options) async {
  final items = await _archives(vfs, dir, extension: '.cbz');
  if (items.isEmpty) {
    stdout.writeln('No chapter files found');
    return _exitOk;
  }
  final outcomes = await ValidateService(const DartCbzEngine()).validateMany(
    vfs,
    items,
    onProgress: (done, total, message) => stdout.writeln('[$done/$total] $message'),
  );
  var invalid = 0;
  for (final outcome in outcomes) {
    if (outcome.result.valid) {
      stdout.writeln('OK   ${outcome.item.name} (${outcome.result.imageCount} images)');
    } else {
      invalid++;
      stderr.writeln('FAIL ${outcome.item.name}: '
          '${outcome.result.error ?? '${outcome.result.errors.length} bad page(s)'}');
      for (final error in outcome.result.errors) {
        stderr.writeln('     ${error.page}: ${error.message}');
      }
    }
  }
  stdout.writeln('${outcomes.length - invalid} valid, $invalid failed');
  return invalid == 0 ? _exitOk : _exitError;
}

Future<int> _convert(Vfs vfs, String dir, _Options options) async {
  final items = await _archives(vfs, dir, extension: '.cbz');
  if (items.isEmpty) {
    stdout.writeln('No chapter files found');
    return _exitOk;
  }
  final outcomes = await const ConvertService().convertMany(
    vfs,
    items,
    backup: !options.delete,
    threads: options.threads,
    onProgress: (done, total, message) => stdout.writeln('[$done/$total] $message'),
  );
  var failed = 0;
  for (final outcome in outcomes) {
    if (outcome.success) {
      stdout.writeln('OK   ${outcome.item.name} '
          '(${outcome.converted} converted, ${outcome.kept} kept)');
    } else {
      failed++;
      stderr.writeln('FAIL ${outcome.item.name}: ${outcome.error}');
    }
  }
  return failed == 0 ? _exitOk : _exitError;
}

Future<int> _merge(Vfs vfs, String dir, _Options options) async {
  final all = await _archives(vfs, dir, extension: '.cbz');
  if (all.isEmpty) {
    stdout.writeln('No chapter files found');
    return _exitOk;
  }
  final series = <String>{
    for (final item in all)
      if (detectSeriesName([item.name]).isNotEmpty) detectSeriesName([item.name]),
  }.toList()
    ..sort();

  var created = 0;
  var failed = 0;
  for (final name in series) {
    stdout.writeln('Merging series: $name');
    final result = await const MergeService().merge(
      vfs,
      dir,
      MergeOptions(
        seriesName: name,
        chaptersList: options.chapters ?? const <int>[],
        chaptersPerVolume: options.chaptersPerVolume,
        force: options.force,
        delete: options.delete,
        threads: options.threads,
      ),
      onProgress: (percent, message) => stdout.writeln('  [$percent%] $message'),
    );
    if (result.success) {
      stdout.writeln('$name: ${result.volumesCreated} volume(s) created');
      created += result.volumesCreated;
    } else {
      if (result.error == 'No matching chapter files found' ||
          result.error == 'Not enough chapters for a full volume') {
        stdout.writeln('$name: ${result.error}');
      } else {
        failed++;
        stderr.writeln('$name: ${result.error}');
      }
    }
  }
  if (failed > 0) return _exitError;
  stdout.writeln(created == 0 ? 'No volumes created' : '$created volume(s) created');
  return _exitOk;
}

Future<int> _cbrToCbz(Vfs vfs, String dir, _Options options) async {
  final items = await _archives(vfs, dir, extension: '.cbr');
  if (items.isEmpty) {
    stdout.writeln('No CBR files found');
    return _exitOk;
  }
  final outcomes = await const CbrConvertService().convertMany(
    vfs,
    dir,
    [for (final item in items) item.name],
    skipExisting: true,
    deleteSource: options.delete,
    threads: options.threads,
    onProgress: (percent, message) => stdout.writeln('[$percent%] $message'),
  );
  var failed = 0;
  for (final outcome in outcomes) {
    if (outcome.error != null) {
      failed++;
      stderr.writeln('FAIL ${outcome.name}: ${outcome.error}');
    } else if (outcome.skipped) {
      stdout.writeln('SKIP ${outcome.name} (target exists)');
    } else {
      stdout.writeln('OK   ${outcome.name} (${outcome.pages} pages)');
    }
  }
  return failed == 0 ? _exitOk : _exitError;
}

void _usage() {
  stdout.writeln('cbzmanager $_version — comic archive manager');
  stdout.writeln('');
  stdout.writeln('Usage: cbzmanager <command> <dir> [options]');
  stdout.writeln('');
  stdout.writeln('Commands:');
  stdout.writeln('  validate <dir>            Validate every *.cbz');
  stdout.writeln('  convert-webp <dir>        Convert images to WebP (only if smaller)');
  stdout.writeln('  merge <dir>               Merge chapters into volumes');
  stdout.writeln('  cbr-to-cbz <dir>          Convert CBR archives to CBZ');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --delete                  Replace originals (no _OLD backup) / delete CBR source');
  stdout.writeln('  --force                   Append remaining chapters to the last volume');
  stdout.writeln('  --chapters N1,N2,...      Exact chapter counts per volume');
  stdout.writeln('  --chapters-per-volume N   Fixed chapters per volume');
  stdout.writeln('  --threads N               Worker threads (0 = auto)');
  stdout.writeln('  --version                 Print the version');
  stdout.writeln('  --help, -h                Show this help');
}
