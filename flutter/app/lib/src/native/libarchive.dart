import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../engine/models.dart';

// libarchive return codes.
const int _archiveOk = 0;
const int _archiveEof = 1;

// Native (C) signatures.
typedef _ReadNewC = Pointer<Void> Function();
typedef _ReadSupportC = Int32 Function(Pointer<Void>);
typedef _ReadOpenMemoryC = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  IntPtr,
);
typedef _ReadNextHeaderC = Int32 Function(
  Pointer<Void>,
  Pointer<Pointer<Void>>,
);
typedef _EntryPathnameC = Pointer<Utf8> Function(Pointer<Void>);
typedef _ReadDataC = IntPtr Function(Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef _ReadFreeC = Int32 Function(Pointer<Void>);
typedef _ErrorStringC = Pointer<Utf8> Function(Pointer<Void>);

// Dart-facing signatures.
typedef _ReadNewDart = Pointer<Void> Function();
typedef _ReadSupportDart = int Function(Pointer<Void>);
typedef _ReadOpenMemoryDart = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _ReadNextHeaderDart = int Function(
  Pointer<Void>,
  Pointer<Pointer<Void>>,
);
typedef _EntryPathnameDart = Pointer<Utf8> Function(Pointer<Void>);
typedef _ReadDataDart = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _ReadFreeDart = int Function(Pointer<Void>);
typedef _ErrorStringDart = Pointer<Utf8> Function(Pointer<Void>);

/// Thin, lazily-loaded binding to libarchive, used only for CBR/RAR reading
/// (there is no pure-Dart RAR decoder).
///
/// Loaded dynamically exactly like the reference `uarchive.pas`: when the
/// library is missing the app degrades gracefully (`isAvailable == false`,
/// CBR operations report the missing dependency) instead of failing to start.
class Libarchive {
  Libarchive._(this._lib);

  final DynamicLibrary _lib;

  static Libarchive? _instance;
  static bool _loadAttempted = false;

  /// True when libarchive could be loaded on this platform.
  static bool get isAvailable => _load() != null;

  /// The loaded binding, or null when libarchive is unavailable.
  static Libarchive? tryLoad() => _load();

  static Libarchive? _load() {
    if (_loadAttempted) return _instance;
    _loadAttempted = true;
    for (final name in _candidateNames()) {
      try {
        return _instance = Libarchive._(DynamicLibrary.open(name));
      } catch (_) {
        // Try the next candidate name.
      }
    }
    return _instance = null;
  }

  static List<String> _candidateNames() {
    if (Platform.isWindows) {
      return const <String>['archive.dll', 'libarchive.dll'];
    }
    if (Platform.isMacOS) {
      return const <String>['libarchive.13.dylib', 'libarchive.dylib'];
    }
    // Linux and Android.
    return const <String>[
      'libarchive.so.13',
      'libarchive.so',
      'libarchive.so.12',
    ];
  }

  late final _ReadNewDart _readNew = _lib
      .lookupFunction<_ReadNewC, _ReadNewDart>('archive_read_new');
  late final _ReadSupportDart _supportFilterAll = _lib
      .lookupFunction<_ReadSupportC, _ReadSupportDart>(
        'archive_read_support_filter_all',
      );
  late final _ReadSupportDart _supportFormatAll = _lib
      .lookupFunction<_ReadSupportC, _ReadSupportDart>(
        'archive_read_support_format_all',
      );
  late final _ReadOpenMemoryDart _openMemory = _lib
      .lookupFunction<_ReadOpenMemoryC, _ReadOpenMemoryDart>(
        'archive_read_open_memory',
      );
  late final _ReadNextHeaderDart _nextHeader = _lib
      .lookupFunction<_ReadNextHeaderC, _ReadNextHeaderDart>(
        'archive_read_next_header',
      );
  late final _EntryPathnameDart _entryPathname = _lib
      .lookupFunction<_EntryPathnameC, _EntryPathnameDart>(
        'archive_entry_pathname',
      );
  late final _ReadDataDart _readData = _lib
      .lookupFunction<_ReadDataC, _ReadDataDart>('archive_read_data');
  late final _ReadFreeDart _readFree = _lib
      .lookupFunction<_ReadFreeC, _ReadFreeDart>('archive_read_free');
  late final _ErrorStringDart _errorString = _lib
      .lookupFunction<_ErrorStringC, _ErrorStringDart>('archive_error_string');

  /// Reads every file entry of a RAR/CBR archive held in [bytes].
  ///
  /// Throws [StateError] when libarchive reports an error (for example an
  /// encrypted or corrupt archive).
  List<ZipEntryData> collectEntries(Uint8List bytes) {
    final archive = _readNew();
    if (archive == nullptr) {
      throw StateError('libarchive: archive_read_new failed');
    }
    _supportFilterAll(archive);
    _supportFormatAll(archive);

    final buffer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final header = calloc<Pointer<Void>>();
    final chunk = calloc<Uint8>(64 * 1024);
    try {
      if (bytes.isNotEmpty) {
        buffer.asTypedList(bytes.length).setAll(0, bytes);
      }
      if (_openMemory(archive, buffer, bytes.length) != _archiveOk) {
        throw StateError('libarchive: ${_lastError(archive)}');
      }

      final out = <ZipEntryData>[];
      while (true) {
        final result = _nextHeader(archive, header);
        if (result == _archiveEof) break;
        if (result < _archiveOk) {
          throw StateError('libarchive: ${_lastError(archive)}');
        }
        final entry = header.value;
        final namePtr = _entryPathname(entry);
        final name = namePtr == nullptr ? '' : namePtr.toDartString();
        if (name.isEmpty || name.endsWith('/')) continue;

        // Copy each read out of the reusable native chunk buffer before
        // handing it to the builder.  `chunk.asTypedList(read)` is a view
        // over the *same* calloc'ed buffer for every iteration; with
        // `BytesBuilder(copy: false)` all the views alias one another, so
        // every 64 KiB block of an entry larger than one chunk ended up
        // holding the last chunk's bytes (silent corruption of any real
        // CBR page).  One explicit copy per chunk is the fix.
        final builder = BytesBuilder(copy: false);
        while (true) {
          final read = _readData(archive, chunk, 64 * 1024);
          if (read < 0) {
            throw StateError('libarchive: ${_lastError(archive)}');
          }
          if (read == 0) break;
          builder.add(Uint8List.fromList(chunk.asTypedList(read)));
        }
        out.add(ZipEntryData(name, builder.toBytes()));
      }
      return out;
    } finally {
      _readFree(archive);
      calloc.free(buffer);
      calloc.free(header);
      calloc.free(chunk);
    }
  }

  String _lastError(Pointer<Void> archive) {
    final ptr = _errorString(archive);
    return ptr == nullptr ? 'unknown error' : ptr.toDartString();
  }
}
