unit usettings;

{ ============================================================================
  usettings – Persistent storage for operation-dialog preferences.

  Each operation dialog (WebP conversion, merge, delete-rows, remove
  ComicInfo) reads its last-used control values when it opens and writes
  them back when the user confirms the operation, so settings survive
  between runs.  Backed by a single INI file in the application config
  directory (e.g. %APPDATA%\cbzmanager\settings.ini).

  The ComicInfo *editor* deliberately does not use this: its fields are
  per-file metadata, not reusable preferences.
  ============================================================================ }

{$mode ObjFPC}{$H+}

interface

uses
  IniFiles;

{ Lazily-created shared settings store.  The returned object is owned by
  this unit (freed at finalization) — callers must not free it. }
function AppSettings: TIniFile;

implementation

uses
  SysUtils;

var
  FSettings: TIniFile = nil;

function AppSettings: TIniFile;
var
  Dir: string;
begin
  if FSettings = nil then
  begin
    Dir := GetAppConfigDir(False);
    if (Dir <> '') and not DirectoryExists(Dir) then
      ForceDirectories(Dir);
    FSettings := TIniFile.Create(
      IncludeTrailingPathDelimiter(Dir) + 'settings.ini');
  end;
  Result := FSettings;
end;

finalization
  FreeAndNil(FSettings);
end.
