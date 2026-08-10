unit uarchive;

{
  uarchive — libarchive FFI for reading RAR/CBR archives.

  libarchive is loaded dynamically at runtime (same pattern as uwebp.pas):
  when the shared library is missing, CbrSupported returns False and CBR
  files degrade gracefully (no thumbnails, read-only previews report the
  missing dependency).  Library names tried in order:

    Linux:    libarchive.so.13, libarchive.so
    macOS:    libarchive.13.dylib, libarchive.dylib
    Windows:  archive.dll (vcpkg builds), libarchive.dll

  TCbrReader is a streaming reader: the source file is opened read-only
  from disk (like TUnZipper) and every decompressed entry lands in a
  TMemoryStream — no temporary files, no disk extraction.  One instance is
  bound to one thread at a time; concurrent readers are safe because each
  libarchive handle is independent.

  Entry names are read with archive_entry_pathname_utf8 (falling back to
  the raw bytes) so names arrive as UTF-8 — which is exactly what LCL
  strings are on both Linux and Windows.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

const
  ARCHIVE_EOF = 1;   { Found end of archive (archive_read_next_header) }
  ARCHIVE_OK  = 0;
  ARCHIVE_RETRY = -10;  { transient failure: retry the read (per libarchive) }

  { Entry file-type masks (archive_entry_filetype). }
  AE_IFMT  = $F000;
  AE_IFDIR = $4000;

type
  { Metadata for the entry the reader is currently positioned on. }
  TCbrEntryInfo = record
    Name: string;
    Size: Int64;
    IsDirectory: boolean;
    IsEncrypted: boolean;
  end;

  { Streaming reader over a RAR/CBR archive via libarchive.  Call NextEntry
    to advance, then either ReadData (into a memory stream) or SkipData.
    Error is non-empty after any failure (including a missing library). }
  TCbrReader = class
  private
    FHandle: Pointer;
    FError: string;
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    { Advances to the next entry.  False at the clean end of the archive
      (Error stays empty) or after a failure (Error set). }
    function NextEntry(out AInfo: TCbrEntryInfo): boolean;
    { Reads the current entry's decompressed data into AStream, appended
      from its current position.  False on failure (Error set). }
    function ReadData(AStream: TStream): boolean;
    { Skips the current entry's data without decompressing it.  False on
      failure (Error set). }
    function SkipData: boolean;
    property Error: string read FError;
  end;

{ True when a usable libarchive was found and loaded. }
function CbrSupported: boolean;

{ Name of the library file actually loaded ('' when unavailable). }
function CbrLibraryName: string;

implementation

uses
  DynLibs, uLog;

const
  {$IFDEF WINDOWS}
  ARCHIVE_LIB_NAMES: array[0..1] of string = ('archive.dll', 'libarchive.dll');
  {$ELSE}
    {$IFDEF DARWIN}
  ARCHIVE_LIB_NAMES: array[0..1] of string =
    ('libarchive.13.dylib', 'libarchive.dylib');
    {$ELSE}
  ARCHIVE_LIB_NAMES: array[0..1] of string =
    ('libarchive.so.13', 'libarchive.so');
    {$ENDIF}
  {$ENDIF}

  { Size of the buffer used by archive_read_data. }
  READ_BUF_SIZE = 65536;

type
  TArchiveReadNew = function: Pointer; cdecl;
  TArchiveReadSupport = function(AR: Pointer): integer; cdecl;
  TArchiveReadOpenFilename = function(AR: Pointer; FName: PAnsiChar;
    BlockSize: SizeUInt): integer; cdecl;
  TArchiveReadOpenFilenameW = function(AR: Pointer; FName: PWideChar;
    BlockSize: SizeUInt): integer; cdecl;
  TArchiveReadNextHeader = function(AR: Pointer; var AEntry: Pointer): integer;
    cdecl;
  TArchiveReadData = function(AR: Pointer; Buff: Pointer;
    Len: SizeUInt): Int64; cdecl;
  TArchiveReadDataSkip = function(AR: Pointer): integer; cdecl;
  TArchiveReadFree = function(AR: Pointer): integer; cdecl;
  TArchiveEntryPathname = function(AEntry: Pointer): PAnsiChar; cdecl;
  TArchiveEntryFiletype = function(AEntry: Pointer): integer; cdecl;
  TArchiveEntryIsEncrypted = function(AEntry: Pointer): integer; cdecl;
  TArchiveEntrySize = function(AEntry: Pointer): Int64; cdecl;
  TArchiveErrorString = function(AR: Pointer): PAnsiChar; cdecl;

var
  { Serializes the lazy initialization of the library. }
  LibLock: TRTLCriticalSection;
  { Handle of the dynamic library; NilHandle if not loaded. }
  hLib: TLibHandle = NilHandle;
  { True after the first load attempt (avoids repeated retries). }
  LibTried: boolean = False;
  { Name of the library file actually loaded. }
  LibName: string = '';
  { Pointers to the functions exported by libarchive, resolved dynamically. }
  _ArchiveReadNew: TArchiveReadNew = nil;
  _ArchiveReadSupportFormatAll: TArchiveReadSupport = nil;
  _ArchiveReadSupportFilterAll: TArchiveReadSupport = nil;
  _ArchiveReadOpenFilename: TArchiveReadOpenFilename = nil;
  _ArchiveReadOpenFilenameW: TArchiveReadOpenFilenameW = nil;
  _ArchiveReadNextHeader: TArchiveReadNextHeader = nil;
  _ArchiveReadData: TArchiveReadData = nil;
  _ArchiveReadDataSkip: TArchiveReadDataSkip = nil;
  _ArchiveReadFree: TArchiveReadFree = nil;
  _ArchiveEntryPathname: TArchiveEntryPathname = nil;
  _ArchiveEntryPathnameUtf8: TArchiveEntryPathname = nil;
  _ArchiveEntryFiletype: TArchiveEntryFiletype = nil;
  _ArchiveEntryIsEncrypted: TArchiveEntryIsEncrypted = nil;
  _ArchiveEntrySize: TArchiveEntrySize = nil;
  _ArchiveErrorString: TArchiveErrorString = nil;

{
  Lazy, thread-safe initialization: searches libarchive among the known
  names, loads the first one found and resolves the needed symbols.  If the
  library exists but lacks the core read functions, it is discarded.  Logs
  the outcome via uLog. }
procedure InitLib;
var
  i: integer;
begin
  EnterCriticalSection(LibLock);
  try
    if LibTried then Exit;
    LibTried := True;

    for i := Low(ARCHIVE_LIB_NAMES) to High(ARCHIVE_LIB_NAMES) do
    begin
      hLib := LoadLibrary(ARCHIVE_LIB_NAMES[i]);
      if hLib <> NilHandle then
      begin
        LibName := ARCHIVE_LIB_NAMES[i];
        Break;
      end;
    end;
    if hLib = NilHandle then
    begin
      Log('Archive: libarchive NOT found: CBR files will not be readable');
      Exit;
    end;

    Pointer(_ArchiveReadNew) := GetProcedureAddress(hLib, 'archive_read_new');
    Pointer(_ArchiveReadSupportFormatAll) :=
      GetProcedureAddress(hLib, 'archive_read_support_format_all');
    Pointer(_ArchiveReadSupportFilterAll) :=
      GetProcedureAddress(hLib, 'archive_read_support_filter_all');
    Pointer(_ArchiveReadOpenFilename) :=
      GetProcedureAddress(hLib, 'archive_read_open_filename');
    Pointer(_ArchiveReadOpenFilenameW) :=
      GetProcedureAddress(hLib, 'archive_read_open_filename_w');
    Pointer(_ArchiveReadNextHeader) :=
      GetProcedureAddress(hLib, 'archive_read_next_header');
    Pointer(_ArchiveReadData) := GetProcedureAddress(hLib, 'archive_read_data');
    Pointer(_ArchiveReadDataSkip) :=
      GetProcedureAddress(hLib, 'archive_read_data_skip');
    Pointer(_ArchiveReadFree) := GetProcedureAddress(hLib, 'archive_read_free');
    Pointer(_ArchiveEntryPathname) :=
      GetProcedureAddress(hLib, 'archive_entry_pathname');
    Pointer(_ArchiveEntryPathnameUtf8) :=
      GetProcedureAddress(hLib, 'archive_entry_pathname_utf8');
    Pointer(_ArchiveEntryFiletype) :=
      GetProcedureAddress(hLib, 'archive_entry_filetype');
    Pointer(_ArchiveEntryIsEncrypted) :=
      GetProcedureAddress(hLib, 'archive_entry_is_encrypted');
    Pointer(_ArchiveEntrySize) := GetProcedureAddress(hLib, 'archive_entry_size');
    Pointer(_ArchiveErrorString) :=
      GetProcedureAddress(hLib, 'archive_error_string');

    if not (Assigned(_ArchiveReadNew) and Assigned(_ArchiveReadNextHeader) and
            Assigned(_ArchiveReadData) and Assigned(_ArchiveReadFree)) then
    begin
      Log('Archive: %s loaded but missing the core read functions', [LibName]);
      UnloadLibrary(hLib);
      hLib := NilHandle;
      LibName := '';
      _ArchiveReadNew := nil;
      _ArchiveReadSupportFormatAll := nil;
      _ArchiveReadSupportFilterAll := nil;
      _ArchiveReadOpenFilename := nil;
      _ArchiveReadOpenFilenameW := nil;
      _ArchiveReadNextHeader := nil;
      _ArchiveReadData := nil;
      _ArchiveReadDataSkip := nil;
      _ArchiveReadFree := nil;
      _ArchiveEntryPathname := nil;
      _ArchiveEntryPathnameUtf8 := nil;
      _ArchiveEntryFiletype := nil;
      _ArchiveEntryIsEncrypted := nil;
      _ArchiveEntrySize := nil;
      _ArchiveErrorString := nil;
      Exit;
    end;

    Log('Archive: loaded %s', [LibName]);
  finally
    LeaveCriticalSection(LibLock);
  end;
end;

function CbrSupported: boolean;
begin
  InitLib;
  Result := hLib <> NilHandle;
end;

function CbrLibraryName: string;
begin
  InitLib;
  Result := LibName;
end;

{ Last error message from the archive handle ('' when none). }
function LibErrorString(AR: Pointer): string;
var
  P: PAnsiChar;
begin
  Result := '';
  if AR = nil then Exit;
  P := _ArchiveErrorString(AR);
  if P <> nil then Result := P;
end;

{ TCbrReader }

constructor TCbrReader.Create(const AFileName: string);
var
  R: integer;
  WS: WideString;
begin
  inherited Create;
  FHandle := nil;
  FError := '';
  if not CbrSupported then
  begin
    FError := 'libarchive not available';
    Exit;
  end;
  FHandle := _ArchiveReadNew();
  if FHandle = nil then
  begin
    FError := 'archive_read_new failed';
    Exit;
  end;
  _ArchiveReadSupportFormatAll(FHandle);
  _ArchiveReadSupportFilterAll(FHandle);
  {$IFDEF WINDOWS}
  { Wide-character open: correct paths on Windows (UTF-16 filenames). }
  if Assigned(_ArchiveReadOpenFilenameW) then
  begin
    WS := UTF8Decode(AFileName);
    R := _ArchiveReadOpenFilenameW(FHandle, PWideChar(WS), 10240);
  end
  else
    R := _ArchiveReadOpenFilename(FHandle, PAnsiChar(AFileName), 10240);
  {$ELSE}
  R := _ArchiveReadOpenFilename(FHandle, PAnsiChar(AFileName), 10240);
  {$ENDIF}
  if R <> ARCHIVE_OK then
  begin
    FError := LibErrorString(FHandle);
    Exit;
  end;
end;

destructor TCbrReader.Destroy;
begin
  if FHandle <> nil then
  begin
    _ArchiveReadFree(FHandle);
    FHandle := nil;
  end;
  inherited Destroy;
end;

function TCbrReader.NextEntry(out AInfo: TCbrEntryInfo): boolean;
var
  Entry: Pointer;
  R: integer;
  P: PAnsiChar;
begin
  AInfo.Name := '';
  AInfo.Size := 0;
  AInfo.IsDirectory := False;
  AInfo.IsEncrypted := False;
  Result := False;
  if FHandle = nil then Exit;

  repeat
    R := _ArchiveReadNextHeader(FHandle, Entry);
    if R <> ARCHIVE_RETRY then Break;   { ARCHIVE_RETRY: try again }
  until False;

  if R = ARCHIVE_EOF then Exit;   { clean end of archive }
  if R < 0 then
  begin
    FError := LibErrorString(FHandle);
    Exit;
  end;

  P := _ArchiveEntryPathnameUtf8(Entry);
  if P = nil then P := _ArchiveEntryPathname(Entry);
  if P <> nil then AInfo.Name := P;
  AInfo.Size := _ArchiveEntrySize(Entry);
  AInfo.IsDirectory := (_ArchiveEntryFiletype(Entry) and AE_IFMT) = AE_IFDIR;
  AInfo.IsEncrypted := _ArchiveEntryIsEncrypted(Entry) <> 0;
  Result := True;
end;

function TCbrReader.ReadData(AStream: TStream): boolean;
var
  Buf: array[0..READ_BUF_SIZE - 1] of byte;
  N: Int64;
begin
  Result := False;
  if (FHandle = nil) or (AStream = nil) then Exit;
  repeat
    N := _ArchiveReadData(FHandle, @Buf[0], SizeOf(Buf));
    if N < 0 then
    begin
      FError := LibErrorString(FHandle);
      Exit;
    end;
    if N = 0 then Break;
    AStream.Write(Buf[0], N);
  until False;
  Result := True;
end;

function TCbrReader.SkipData: boolean;
begin
  Result := False;
  if FHandle = nil then Exit;
  if _ArchiveReadDataSkip(FHandle) <> ARCHIVE_OK then
  begin
    FError := LibErrorString(FHandle);
    Exit;
  end;
  Result := True;
end;

initialization
  InitCriticalSection(LibLock);

finalization
  if hLib <> NilHandle then
  begin
    UnloadLibrary(hLib);
    hLib := NilHandle;
  end;
  DoneCriticalSection(LibLock);

end.
