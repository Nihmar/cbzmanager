{ ============================================================================
  uservicecbr – CBR-to-CBZ conversion service.

  Batch-converts RAR comic archives (.cbr) into CBZ files, entirely in RAM:
  the RAR entries are decompressed into memory via libarchive (uarchive.pas),
  filtered and renumbered by ConvertCbrToCbz (uzipeditor.pas), and written
  with WriteZipFromEntriesDeflated.  The source .cbr is never modified
  unless DeleteSource is set (and even then only after a successful write).

  Defaults: files whose .cbz target already exists are skipped (no silent
  overwrite); renumbering to page_NNNN.* is always applied (house policy).
  ============================================================================ }
unit uservicecbr;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uzipcore, uZipEditor, uservicebase, userviceconvert;

type
  { ------------------------------------------------------------------------
    TCbrConvertOptions – Settings controlling the CBR→CBZ conversion.

    @field SkipExisting  When True, files whose .cbz target already exists
                         are left alone (default, avoids silent overwrites).
    @field DeleteSource  When True, the .cbr source is deleted after a
                         successful conversion (default: kept).
    ------------------------------------------------------------------------ }
  TCbrConvertOptions = record
    SkipExisting: boolean;
    DeleteSource: boolean;
  end;

  { ------------------------------------------------------------------------
    TConvertCbrService – Stateless service for batch CBR→CBZ conversion.

    Results reuse TConvertResults: PagesConverted carries the number of
    pages written to the new CBZ, OriginalSize/NewSize the source/target
    file sizes (so the shared results dialog works unchanged).
    ------------------------------------------------------------------------ }
  TConvertCbrService = class
  public
    { Batch-convert every file in AFiles (bare .cbr names) inside ADir.
      Per-file results: Success True when the CBZ was written (or the file
      was skipped because its target exists); failures carry ErrorMsg. }
    class function Convert(const AFiles: TStringArray; const ADir: string;
      const Options: TCbrConvertOptions;
      AOnProgress: TServiceProgressEvent = nil): TConvertResults;
  end;

implementation

function GetFileSize(const APath: string): int64;
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

class function TConvertCbrService.Convert(const AFiles: TStringArray;
  const ADir: string; const Options: TCbrConvertOptions;
  AOnProgress: TServiceProgressEvent = nil): TConvertResults;
var
  i, Total: integer;
  FullPath, TargetPath: string;
  Entries: TZipEntries;
  Translator: TFileProgress;
begin
  Total := Length(AFiles);
  Result := nil;
  SetLength(Result, Total);
  ReportServiceStart(AOnProgress, 'Converting CBR', Total);
  for i := 0 to High(AFiles) do
  begin
    ReportServiceProgress(AOnProgress, 'Converting CBR', AFiles[i], i, Total);
    Result[i].FileName := AFiles[i];
    FullPath := CBZFullPath(ADir, AFiles[i]);
    TargetPath := ChangeFileExt(FullPath, CBZ_EXT);
    Result[i].OriginalSize := GetFileSize(FullPath);
    try
      if Options.SkipExisting and FileExists(TargetPath) then
      begin
        Result[i].Success := True;
        Result[i].PagesConverted := 0;
        Result[i].NewSize := Result[i].OriginalSize;
        Result[i].ErrorMsg := 'Target exists — skipped';
        Continue;
      end;

      { Folds CollectCbrEntries' within-file percentages into a smooth
        global 0–100 sweep across the whole batch. }
      Translator := TFileProgress.Create(i, Total, AOnProgress);
      try
        Entries := ConvertCbrToCbz(FullPath, @Translator.Translate);
      finally
        Translator.Free;
      end;
      try
        if Length(Entries) = 0 then
          raise Exception.Create('No images found');
        WriteZipFromEntriesDeflated(TargetPath, Entries);
        Result[i].Success := True;
        Result[i].PagesConverted := Length(Entries);
        Result[i].NewSize := GetFileSize(TargetPath);
        { Delete the source only after the target has been written. }
        if Options.DeleteSource and not DeleteFile(FullPath) then
          raise Exception.CreateFmt('Converted, but failed to delete %s',
            [AFiles[i]]);
      finally
        FreeZipEntries(Entries);
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
  if Assigned(AOnProgress) then
    AOnProgress(100, 'Complete');
end;

end.
