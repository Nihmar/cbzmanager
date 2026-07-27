{ ============================================================================
  userviceconvert – Image-to-WebP conversion service for CBZ archives.

  This unit provides TConvertService, a stateless class that batch-converts
  image pages inside CBZ files to the WebP format.  Each input file is
  processed independently; the actual conversion work is delegated to
  ConvertCBZToWebP (defined in uZipEditor).

  Conversion options (TConvertOptions) control quality, conditional
  replacement, ComicInfo.xml removal, page renumbering, and backup
  behaviour.  Results are reported per-file through TConvertResults.
  ============================================================================ }
unit userviceconvert;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uZipEditor, uservicebase;

type
  { ------------------------------------------------------------------------
    TConvertOptions – Settings controlling the WebP conversion.

    @field Quality              WebP quality setting (0–100).  Higher values
                                produce larger files with better fidelity.
    @field ReplaceOnlyIfSmaller When True, a converted image replaces the
                                original only if the WebP version is smaller.
    @field SkipExistingWebP     When True, images already in WebP format are
                                left untouched.
    @field RemoveComicInfo      When True, ComicInfo.xml is stripped from the
                                output archive.
    @field RenumberPages        When True, pages are renamed sequentially
                                (e.g. "001.webp", "002.webp", …).
    @field BackupOld            When True, the original CBZ is renamed to
                                *_OLD.cbz before writing the converted version.
    ------------------------------------------------------------------------ }
  TConvertOptions = record
    Quality: integer;
    ReplaceOnlyIfSmaller: boolean;
    SkipExistingWebP: boolean;
    RemoveComicInfo: boolean;
    RenumberPages: boolean;
    BackupOld: boolean;
  end;

  { ------------------------------------------------------------------------
    TConvertEntry – Per-file result of a conversion operation.

    @field FileName        Name of the CBZ file processed.
    @field Success         True if the operation completed without error.
    @field PagesConverted  Number of image pages that were converted to WebP.
    @field ErrorMsg        Error description if Success is False, or an
                           informational message (e.g. "No convertible images
                           found") when no pages were converted.
    ------------------------------------------------------------------------ }
  TConvertEntry = record
    FileName: string;
    Success: boolean;
    PagesConverted: integer;
    ErrorMsg: string;
    OriginalSize: Int64;
    NewSize: Int64;
  end;

  { ------------------------------------------------------------------------
    TConvertResults – Dynamic array of per-file conversion results.
    ------------------------------------------------------------------------ }
  TConvertResults = array of TConvertEntry;

  { ------------------------------------------------------------------------
    TConvertService – Stateless service for batch WebP conversion.

    The single class method Convert processes a list of CBZ files from a
    common directory, applying the supplied TConvertOptions to each.
    Progress is reported via an optional TProgressEvent callback.
    ------------------------------------------------------------------------ }
  TConvertService = class
  public
    { ------------------------------------------------------------------------
      Convert – Batch-convert images inside CBZ archives to WebP.

      Calls ConvertCBZToWebP (from uZipEditor) for each input file.  When
      at least one page was converted, the archive is rebuilt and (if
      Options.BackupOld is True) the original is backed up first.  If no
      pages were converted (NewCount = 0) the file is left untouched and
      the result carries an informational message rather than an error.

      @param  AFiles      Array of CBZ filenames to process (bare names).
      @param  ADir        Directory containing the files.
      @param  Options     Conversion settings (quality, renumbering, etc.).
      @param  AOnProgress Optional progress callback (percentage + message).
      @return An array of TConvertEntry, one per input file, with Success,
              PagesConverted, and ErrorMsg populated.
      ------------------------------------------------------------------------ }
    class function Convert(const AFiles: TStringArray; const ADir: string;
      const Options: TConvertOptions;
      AOnProgress: TProgressEvent = nil): TConvertResults;
  end;

implementation

function GetFileSize(const APath: string): Int64;
var
  SR: TSearchRec;
begin
  if FindFirst(APath, faAnyFile, SR) = 0 then
  begin
    Result := SR.Size;
    FindClose(SR);
  end
  else
    Result := 0;
end;

class function TConvertService.Convert(const AFiles: TStringArray;
  const ADir: string; const Options: TConvertOptions;
  AOnProgress: TProgressEvent = nil): TConvertResults;
var
  i, NewCount, ConvertedCount, Total: integer;
  FullPath: string;
  NewEntries: TZipEntries;
  Modified: boolean;
begin
  Total := Length(AFiles);
  Result := nil;
  SetLength(Result, Total);
  if Assigned(AOnProgress) and (Total > 0) then
    AOnProgress(0, Format('Converting 0/%d files', [Total]));
  for i := 0 to High(AFiles) do
  begin
    if Assigned(AOnProgress) then
      AOnProgress((i * 100) div Total,
        Format('Converting %s (%d/%d)', [AFiles[i], i + 1, Total]));
    Result[i].FileName := AFiles[i];
    FullPath := IncludeTrailingPathDelimiter(ADir) + AFiles[i];
    try
      Result[i].OriginalSize := GetFileSize(FullPath);
      NewEntries := ConvertCBZToWebP(FullPath, Options.Quality,
        Options.ReplaceOnlyIfSmaller, Options.SkipExistingWebP,
        Options.RemoveComicInfo, Options.RenumberPages,
        NewCount, ConvertedCount, Modified);
      try
        if Modified then
        begin
          if Options.BackupOld then
            if not BackupFile(FullPath) then
              raise Exception.CreateFmt('Failed to create backup of %s', [FullPath]);
          WriteZipFromEntriesDeflated(FullPath, NewEntries);
          Result[i].Success := True;
          Result[i].PagesConverted := ConvertedCount;
          Result[i].NewSize := GetFileSize(FullPath);
        end
        else
        begin
          Result[i].Success := True;
          Result[i].PagesConverted := 0;
          Result[i].NewSize := Result[i].OriginalSize;
          Result[i].ErrorMsg := 'Already up to date';
        end;
      finally
        FreeZipEntries(NewEntries);
      end;
    except
      on E: Exception do
      begin
        Result[i].Success := False;
        Result[i].PagesConverted := 0;
        Result[i].NewSize := Result[i].OriginalSize;
        Result[i].ErrorMsg := E.Message;
      end;
    end;
  end;
end;

end.
