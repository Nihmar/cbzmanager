{
  uclimode.pas — Headless (CLI) mode for the cbzmanager application.

  When the program is launched with a known command as its first argument
  (validate, convert-webp, merge, --help, --version), it runs without any
  GUI: the service layer is invoked directly and results are printed to
  stdout.  The widgetset is never initialized — the service layer
  (validate/convert/merge) works purely in memory via TLazIntfImage and
  needs no display, exactly like the FPCUnit testrunner.

  Argument order mirrors Python's argparse: flags may appear before or
  after the positional directory.

  Exit codes (mirroring the Python reference CLI):
    0  success, or a benign no-op ("no chapters", "no space savings")
    1  runtime error (invalid directory, failed operation, ...)
    2  usage error (bad or missing arguments)

  Commands not ported (out of scope, see AGENTS.md): delete-pages,
  find-similar, delete-pages-by-id.
}
unit uclimode;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils;

{ Version reported by --version; mirrors the Python reference CLI. }
const
  CLI_VERSION = '0.1.0';

  EXIT_OK = 0;
  EXIT_ERROR = 1;
  EXIT_USAGE = 2;

{ True when AFirstArg names a headless command or --help/--version.  The
  program then runs as a CLI instead of starting the GUI. }
function IsHeadlessCommand(const AFirstArg: string): boolean;

{ Run the headless CLI, reading arguments from ParamStr.  Never raises.
  Returns the process exit code (EXIT_OK / EXIT_ERROR / EXIT_USAGE). }
function RunHeadlessFromParams: integer;

{ Testable core: same semantics as RunHeadlessFromParams but with an
  explicit argument array (AArgs[0] is the command). }
function RunHeadless(const AArgs: TStringArray): integer;

implementation

uses
  StrUtils,
  uservicebase, uservicevalidate, userviceconvert, uservicemerge, uservicecbr,
  uarchive, uZipEditor;

type
  { Forwards service progress callbacks to stdout. }
  TCliProgress = class
    procedure Progress(APercent: integer; const AMsg: string);
  end;

  { Parsed command-line flags.  Chapters is empty when --chapters was not
    given; ChaptersPerVolume is 0 when --chapters-per-volume was not given;
    Threads is 0 when --threads was not given (0 = automatic). }
  THeadlessFlags = record
    Delete: boolean;
    Force: boolean;
    Chapters: TIntArray;
    ChaptersPerVolume: integer;
    Threads: integer;
  end;

procedure TCliProgress.Progress(APercent: integer; const AMsg: string);
begin
  WriteLn(AMsg);
end;

procedure PrintUsage;
begin
  WriteLn('cbzmanager — CBZ comic archive manager (headless mode)');
  WriteLn;
  WriteLn('Usage:');
  WriteLn('  cbzmanager <command> [options]');
  WriteLn;
  WriteLn('Commands:');
  WriteLn('  validate <dir>                 Verify CBZ files are valid and images readable');
  WriteLn('  convert-webp <dir> [options]   Convert images to WebP (quality 75%, only if smaller)');
  WriteLn('  merge <dir> [options]          Merge chapter CBZ files into volumes');
  WriteLn('  cbr-to-cbz <dir> [--delete]    Convert CBR (RAR) archives to CBZ');
  WriteLn;
  WriteLn('convert-webp options:');
  WriteLn('  --delete                     Delete originals after conversion (default: rename to _OLD.cbz)');
  WriteLn('  --threads N                  Decode/encode pages on N worker threads (default: one per CPU core)');
  WriteLn;
  WriteLn('Merge options:');
  WriteLn('  --delete                     Delete originals after processing (default: rename to _OLD.cbz)');
  WriteLn('  --force                      Append remaining chapters to the last volume');
  WriteLn('  --chapters N1,N2,N3,...      Exact chapter counts per volume');
  WriteLn('  --chapters-per-volume N      Fixed chapters per volume');
  WriteLn;
  WriteLn('cbr-to-cbz options:');
  WriteLn('  --delete                     Delete the .cbr source after conversion (default: keep)');
  WriteLn;
  WriteLn('Other:');
  WriteLn('  --version                    Print version and exit');
  WriteLn('  --help                       Show this help');
  WriteLn;
  WriteLn('Flags may appear before or after the directory.  Without any');
  WriteLn('argument the GUI starts.  Not ported (out of scope):');
  WriteLn('delete-pages, find-similar, delete-pages-by-id.');
end;

{ Parse "N1,N2,N3" into a positive-int array.  Returns False on any
  non-positive or non-numeric element. }
function ParseChaptersList(const S: string; out ChList: TIntArray): boolean;
var
  Parts: TStringArray;
  i, V, Err: integer;
begin
  ChList := nil;
  Result := False;
  Parts := S.Split([',']);
  for i := 0 to High(Parts) do
  begin
    Val(Trim(Parts[i]), V, Err);
    if (Err <> 0) or (V <= 0) then Exit;
    SetLength(ChList, Length(ChList) + 1);
    ChList[High(ChList)] := V;
  end;
  Result := Length(ChList) > 0;
end;

{ ---------------------------------------------------------------------------
  ParseHeadlessArgs

  Splits AArgs (AArgs[0] = command) into a directory and flags.  Flags may
  appear before or after the directory; --chapters and
  --chapters-per-volume consume the following argument as their value.

  Returns 0 on success (Dir set; unknown or malformed flags reported on
  stderr with EXIT_USAGE).  A second positional argument is an error
  (argparse parity: "unrecognized arguments").
  --------------------------------------------------------------------------- }
function ParseHeadlessArgs(const AArgs: TStringArray; out Dir: string;
  out Flags: THeadlessFlags): integer;
var
  i, ErrPos: integer;
  S: string;
begin
  Result := EXIT_USAGE;
  Dir := '';
  Flags.Delete := False;
  Flags.Force := False;
  Flags.Chapters := nil;
  Flags.ChaptersPerVolume := 0;
  Flags.Threads := 0;

  i := 1;
  while i < Length(AArgs) do
  begin
    S := AArgs[i];
    if S = '--delete' then
      Flags.Delete := True
    else if S = '--force' then
      Flags.Force := True
    else if S = '--threads' then
    begin
      if i + 1 >= Length(AArgs) then
      begin
        WriteLn(ErrOutput, 'Error: --threads expects a value');
        WriteLn(ErrOutput, 'Try ''cbzmanager --help'' for usage.');
        Exit;
      end;
      Val(AArgs[i + 1], Flags.Threads, ErrPos);
      if (ErrPos <> 0) or (Flags.Threads <= 0) then
      begin
        WriteLn(ErrOutput,
          'Error: --threads expects a positive integer');
        Exit;
      end;
      Inc(i);
    end
    else if (S = '--chapters') or (S = '--chapters-per-volume') then
    begin
      if i + 1 >= Length(AArgs) then
      begin
        WriteLn(ErrOutput, Format('Error: %s expects a value', [S]));
        WriteLn(ErrOutput, 'Try ''cbzmanager --help'' for usage.');
        Exit;
      end;
      if S = '--chapters' then
      begin
        if not ParseChaptersList(AArgs[i + 1], Flags.Chapters) then
        begin
          WriteLn(ErrOutput,
            'Error: --chapters expects a comma-separated list of positive integers');
          Exit;
        end;
      end
      else
      begin
        Val(AArgs[i + 1], Flags.ChaptersPerVolume, ErrPos);
        if (ErrPos <> 0) or (Flags.ChaptersPerVolume <= 0) then
        begin
          WriteLn(ErrOutput,
            'Error: --chapters-per-volume expects a positive integer');
          Exit;
        end;
      end;
      Inc(i);
    end
    else if StartsStr('--', S) then
    begin
      WriteLn(ErrOutput, Format('Error: unknown option ''%s''', [S]));
      WriteLn(ErrOutput, 'Try ''cbzmanager --help'' for usage.');
      Exit;
    end
    else if Dir = '' then
      Dir := S
    else
    begin
      WriteLn(ErrOutput, Format('Error: unexpected argument ''%s''', [S]));
      WriteLn(ErrOutput, 'Try ''cbzmanager --help'' for usage.');
      Exit;
    end;
    Inc(i);
  end;

  if Dir = '' then
  begin
    WriteLn(ErrOutput, Format('Error: missing directory for ''%s''',
      [AArgs[0]]));
    WriteLn(ErrOutput, 'Try ''cbzmanager --help'' for usage.');
    Exit;
  end;
  Result := 0;
end;

{ ---------------------------------------------------------------------------
  Command implementations
  --------------------------------------------------------------------------- }

function CmdValidate(const ADir: string; const Flags: THeadlessFlags): integer;
var
  Files: TStringArray;
  Results: TValidationResults;
  Progress: TCliProgress;
  i, FailCount: integer;
begin
  { --delete is accepted for validate (argparse parity) but unused. }
  if Flags.Force or (Length(Flags.Chapters) > 0) or
     (Flags.ChaptersPerVolume > 0) or (Flags.Threads > 0) then
  begin
    WriteLn(ErrOutput, 'Error: option not valid for ''validate''');
    WriteLn(ErrOutput, 'Try ''cbzmanager --help'' for usage.');
    Exit(EXIT_USAGE);
  end;

  Files := CollectCBZFiles(ADir);
  if Length(Files) = 0 then
  begin
    WriteLn(Format('No .cbz files found in %s', [ADir]));
    Exit(EXIT_OK);                       // Python reference returns 0 here
  end;
  WriteLn(Format('Checking %d CBZ file(s)...', [Length(Files)]));
  Progress := TCliProgress.Create;
  try
    Results := TValidateService.ValidateDeep(Files, ADir, @Progress.Progress);
  finally
    Progress.Free;
  end;
  FailCount := 0;
  for i := 0 to High(Results) do
    if Results[i].Valid then
      WriteLn(Format('  OK   %s (%d image(s))', [Results[i].FileName,
        Results[i].ImageCount]))
    else
    begin
      Inc(FailCount);
      WriteLn(Format('  FAIL %s: %s', [Results[i].FileName,
        Results[i].ErrorMsg]));
    end;
  WriteLn(Format('Valid: %d  Invalid: %d  Total: %d',
    [Length(Results) - FailCount, FailCount, Length(Results)]));
  if FailCount > 0 then
    Result := EXIT_ERROR
  else
    Result := EXIT_OK;
end;

function CmdConvert(const ADir: string; const Flags: THeadlessFlags): integer;
var
  Files: TStringArray;
  Options: TConvertOptions;
  Results: TConvertResults;
  Progress: TCliProgress;
  i, Converted, Skipped: integer;
begin
  Files := CollectCBZFiles(ADir);
  if Length(Files) = 0 then
  begin
    WriteLn(Format('No .cbz files found in %s', [ADir]));
    Exit(EXIT_OK);                       // Python reference returns 0 here
  end;
  WriteLn(Format('Found %d CBZ file(s)', [Length(Files)]));

  { Python reference defaults: quality 75, replace only if smaller, leave
    existing .webp pages alone, strip ComicInfo.xml, renumber pages, and
    back up the original unless --delete. }
  Options.Quality := 75;
  Options.ReplaceOnlyIfSmaller := True;
  Options.SkipExistingWebP := True;
  Options.RemoveComicInfo := True;
  Options.RenumberPages := True;
  Options.BackupOld := not Flags.Delete;
  Options.Threads := Flags.Threads;   { 0 = automatic (CPU count, capped) }

  Progress := TCliProgress.Create;
  try
    Results := TConvertService.Convert(Files, ADir, Options, @Progress.Progress);
  finally
    Progress.Free;
  end;
  Converted := 0;
  Skipped := 0;
  for i := 0 to High(Results) do
    if Results[i].Success and (Results[i].PagesConverted > 0) then
    begin
      Inc(Converted);
      WriteLn(Format('  %s: %d page(s) converted', [Results[i].FileName,
        Results[i].PagesConverted]));
    end
    else
    begin
      Inc(Skipped);
      WriteLn(Format('  - %s: %s', [Results[i].FileName, Results[i].ErrorMsg]));
    end;
  WriteLn(Format('Summary: Converted: %d  Skipped: %d', [Converted, Skipped]));
  Result := EXIT_OK;                     // Python reference returns 0 always
end;

function CmdMerge(const ADir: string; const Flags: THeadlessFlags): integer;
var
  Files: TStringArray;
  i, ChNum: integer;
  Series: string;
  IsSpecial: boolean;
  SeriesList: TStringList;
  Opts: TMergeOptions;
  Res: TMergeResult;
  Progress: TCliProgress;
  Failed: boolean;
begin
  if (Length(Flags.Chapters) > 0) and (Flags.ChaptersPerVolume > 0) then
  begin
    WriteLn(ErrOutput,
      'Error: --chapters and --chapters-per-volume are mutually exclusive');
    Exit(EXIT_ERROR);                    // Python reference returns 1 here
  end;
  if Flags.Threads > 0 then
  begin
    WriteLn(ErrOutput, 'Error: option not valid for ''merge''');
    WriteLn(ErrOutput, 'Try ''cbzmanager --help'' for usage.');
    Exit(EXIT_USAGE);
  end;

  Files := CollectCBZFiles(ADir);

  { Group the chapter files by series name (Python reference: one plan per
    series, series processed in sorted order).  Series that only have
    volumes are skipped, like the reference's "No chapters" row. }
  SeriesList := TStringList.Create;
  try
    SeriesList.Sorted := True;
    SeriesList.Duplicates := dupIgnore;
    for i := 0 to High(Files) do
      if IsChapterFile(Files[i], Series, ChNum, IsSpecial) then
        SeriesList.Add(Series);

    if SeriesList.Count = 0 then
    begin
      WriteLn('No chapter files found (pattern: ''Title - NNNN.cbz'' or ' +
        '''Title - SP01.cbz'')');
      Exit(EXIT_OK);
    end;

    Failed := False;
    Progress := TCliProgress.Create;
    try
      for i := 0 to SeriesList.Count - 1 do
      begin
        Opts.SeriesName := SeriesList[i];
        { Chapter 0 files ("Series - 0000.cbz") are regular chapters of
          the Python reference; the default range covers every chapter. }
        Opts.ChapterStart := 0;
        Opts.ChapterEnd := MaxInt;
        Opts.ChaptersPerVolume := Flags.ChaptersPerVolume;
        Opts.ChaptersList := Flags.Chapters;
        Opts.Force := Flags.Force;
        Opts.Delete := Flags.Delete;
        Opts.GenerateComicInfo := False;
        Res := TMergeService.Merge(Files, ADir, Opts, @Progress.Progress);
        if Res.Success then
          WriteLn(Format('%s: %d volume(s) created',
            [SeriesList[i], Res.VolumesCreated]))
        else if Pos('Not enough chapters', Res.ErrorMsg) > 0 then
          WriteLn(Format('%s: %s', [SeriesList[i], Res.ErrorMsg]))
        else if Pos('No matching chapter files', Res.ErrorMsg) > 0 then
          WriteLn(Format('%s: no chapter files in range', [SeriesList[i]]))
        else
        begin
          Failed := True;
          WriteLn(ErrOutput, Format('%s: %s', [SeriesList[i], Res.ErrorMsg]));
        end;
      end;
    finally
      Progress.Free;
    end;

    if Failed then
      Result := EXIT_ERROR
    else
      Result := EXIT_OK;
  finally
    SeriesList.Free;
  end;
end;

function CmdCbrToCbz(const ADir: string; const ADelete: boolean): integer;
var
  Files: TStringArray;
  Options: TCbrConvertOptions;
  Results: TConvertResults;
  Progress: TCliProgress;
  i, Converted, Skipped: integer;
begin
  if not CbrSupported then
  begin
    WriteLn(ErrOutput,
      'Error: CBR support requires libarchive (libarchive.so / archive.dll)');
    Exit(EXIT_ERROR);
  end;

  Files := CollectCBRFiles(ADir);
  if Length(Files) = 0 then
  begin
    WriteLn(Format('No .cbr files found in %s', [ADir]));
    Exit(EXIT_OK);
  end;
  WriteLn(Format('Found %d CBR file(s)', [Length(Files)]));

  { Defaults mirror the GUI dialog: skip files whose .cbz target already
    exists; keep the source unless --delete. }
  Options.SkipExisting := True;
  Options.DeleteSource := ADelete;

  Progress := TCliProgress.Create;
  try
    Results := TConvertCbrService.Convert(Files, ADir, Options,
      @Progress.Progress);
  finally
    Progress.Free;
  end;
  Converted := 0;
  Skipped := 0;
  for i := 0 to High(Results) do
    if Results[i].Success and (Results[i].PagesConverted > 0) then
    begin
      Inc(Converted);
      WriteLn(Format('  %s: %d page(s) -> .cbz', [Results[i].FileName,
        Results[i].PagesConverted]));
    end
    else
    begin
      Inc(Skipped);
      WriteLn(Format('  - %s: %s', [Results[i].FileName, Results[i].ErrorMsg]));
    end;
  WriteLn(Format('Summary: Converted: %d  Skipped: %d', [Converted, Skipped]));
  Result := EXIT_OK;
end;

{ ---------------------------------------------------------------------------
  RunHeadless — dispatch
  --------------------------------------------------------------------------- }
function RunHeadless(const AArgs: TStringArray): integer;
var
  Cmd, Dir: string;
  Flags: THeadlessFlags;
begin
  Result := EXIT_USAGE;
  if Length(AArgs) = 0 then Exit;

  Cmd := AArgs[0];
  if (Cmd = '--help') or (Cmd = '-h') or (Cmd = 'help') then
  begin
    PrintUsage;
    Exit(EXIT_OK);
  end;
  if Cmd = '--version' then
  begin
    WriteLn('cbzmanager ' + CLI_VERSION);
    Exit(EXIT_OK);
  end;

  if (Cmd <> 'validate') and (Cmd <> 'convert-webp') and (Cmd <> 'merge') and
     (Cmd <> 'cbr-to-cbz') then
  begin
    WriteLn(ErrOutput, Format('Error: unknown command ''%s''', [Cmd]));
    WriteLn(ErrOutput, 'Try ''cbzmanager --help'' for usage.');
    Exit(EXIT_USAGE);
  end;

  if ParseHeadlessArgs(AArgs, Dir, Flags) <> 0 then
    Exit(EXIT_USAGE);
  if not DirectoryExists(Dir) then
  begin
    WriteLn(ErrOutput, Format('Error: ''%s'' is not a valid directory', [Dir]));
    Exit(EXIT_ERROR);
  end;

  if Cmd = 'validate' then
    Result := CmdValidate(Dir, Flags)
  else if Cmd = 'convert-webp' then
  begin
    { convert-webp accepts only --delete and --threads; validate the flag
      set. }
    if Flags.Force or (Length(Flags.Chapters) > 0) or
       (Flags.ChaptersPerVolume > 0) then
    begin
      WriteLn(ErrOutput, 'Error: option not valid for ''convert-webp''');
      WriteLn(ErrOutput, 'Try ''cbzmanager --help'' for usage.');
      Exit(EXIT_USAGE);
    end;
    Result := CmdConvert(Dir, Flags);
  end
  else if Cmd = 'cbr-to-cbz' then
  begin
    { cbr-to-cbz accepts only --delete; validate the flag set. }
    if Flags.Force or (Length(Flags.Chapters) > 0) or
       (Flags.ChaptersPerVolume > 0) or (Flags.Threads > 0) then
    begin
      WriteLn(ErrOutput, 'Error: option not valid for ''cbr-to-cbz''');
      WriteLn(ErrOutput, 'Try ''cbzmanager --help'' for usage.');
      Exit(EXIT_USAGE);
    end;
    Result := CmdCbrToCbz(Dir, Flags.Delete);
  end
  else
    Result := CmdMerge(Dir, Flags);
end;

function IsHeadlessCommand(const AFirstArg: string): boolean;
begin
  Result := (AFirstArg = 'validate') or (AFirstArg = 'convert-webp') or
            (AFirstArg = 'merge') or (AFirstArg = 'cbr-to-cbz') or
            (AFirstArg = '--help') or (AFirstArg = '-h') or
            (AFirstArg = 'help') or (AFirstArg = '--version');
end;

function RunHeadlessFromParams: integer;
var
  Args: TStringArray;
  i: integer;
begin
  SetLength(Args, ParamCount);
  for i := 1 to ParamCount do
    Args[i - 1] := ParamStr(i);
  Result := RunHeadless(Args);
end;

end.
