import 'dart:typed_data';

/// Connection parameters for an SMB2/3 share.
///
/// Passwords are supplied by the caller and kept in memory only: the app does
/// not persist them (the connect dialog asks every time).
class SmbConfig {
  const SmbConfig({
    required this.host,
    required this.share,
    this.user,
    this.password,
    this.domain,
    this.workers = 4,
  });

  final String host;
  final String share;
  final String? user;
  final String? password;
  final String? domain;
  final int workers;

  @override
  String toString() => 'smb://$host/$share${user == null ? '' : ' ($user)'}';
}

/// One directory entry as returned by an [SmbBackend].
class SmbBackendEntry {
  const SmbBackendEntry({
    required this.name,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });

  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
}

/// Stat of an [SmbBackend] path.
class SmbBackendStat {
  const SmbBackendStat({
    required this.exists,
    this.isDirectory = false,
    this.size = 0,
    this.modified,
  });

  const SmbBackendStat.missing()
    : exists = false,
      isDirectory = false,
      size = 0,
      modified = null;

  final bool exists;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
}

/// The minimal SMB surface [SmbVfs] needs, in share-relative path terms.
///
/// Keeping it abstract is what contains the `dart_smb2` 0.x dependency:
/// `dart_smb2_backend.dart` is the only file importing the package, so a
/// breaking release (or a switch to another client) touches one file.  It also
/// lets tests inject a fake backend and exercise the whole [SmbVfs] without a
/// live share.
abstract class SmbBackend {
  Future<List<SmbBackendEntry>> list(String path);
  Future<SmbBackendStat> stat(String path);
  Future<bool> exists(String path);
  Future<Uint8List> read(String path);
  Future<void> write(String path, Uint8List bytes);
  Future<void> rename(String from, String to);
  Future<void> deleteFile(String path);
  Future<void> mkdir(String path);
  Future<void> rmdir(String path);
  Future<void> disconnect();
}
