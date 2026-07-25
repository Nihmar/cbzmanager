unit uthreadservice;

{
  Background thread wrappers for service operations.
  Each thread runs the service in Execute(), sends progress updates to the
  main thread via TThread.Queue, and the OnTerminate handler reads results.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,
  uZipEditor, uservicebase, userviceconvert, uservicemerge, uservicevalidate,
  uservicecomicinfo;

type
  { Result record for batch delete operations }
  TDeletePagesResult = record
    Success: boolean;
    Processed: integer;
    ErrorMsg: string;
  end;

  { Base class: wraps TProgressEvent with TThread.Queue for safe UI updates.
    Descendants set FResult in Execute; the OnTerminate handler reads it. }
  TServiceThread = class(TThread)
  private
    FOnProgress: TProgressEvent;
    FPendingPct: integer;
    FPendingMsg: string;
    procedure SyncProgress;
  protected
    { Call from Execute to report progress safely to the main thread. }
    procedure Progress(APercent: integer; const AMsg: string);
  public
    constructor Create(AOnProgress: TProgressEvent);
  end;

  { Background CBZ-to-WebP conversion }
  TConvertThread = class(TServiceThread)
  private
    FFiles: TStringArray;
    FDir: string;
    FOptions: TConvertOptions;
    FResult: TConvertResults;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFiles: TStringArray; const ADir: string;
      const AOptions: TConvertOptions; AOnProgress: TProgressEvent);
    property Result: TConvertResults read FResult;
  end;

  { Background chapter merge into volumes }
  TMergeThread = class(TServiceThread)
  private
    FFiles: TStringArray;
    FDir: string;
    FOptions: TMergeOptions;
    FResult: TMergeResult;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFiles: TStringArray; const ADir: string;
      const AOptions: TMergeOptions; AOnProgress: TProgressEvent);
    property Result: TMergeResult read FResult;
  end;

  { Background CBZ validation }
  TValidateThread = class(TServiceThread)
  private
    FFiles: TStringArray;
    FDir: string;
    FResult: TValidationResults;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFiles: TStringArray; const ADir: string;
      AOnProgress: TProgressEvent);
    property Result: TValidationResults read FResult;
  end;

  { Background ComicInfo.xml removal }
  TComicInfoRemoveThread = class(TServiceThread)
  private
    FFiles: TStringArray;
    FDir: string;
    FBackup: boolean;
    FResult: TComicInfoResults;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFiles: TStringArray; const ADir: string;
      ABackup: boolean; AOnProgress: TProgressEvent);
    property Result: TComicInfoResults read FResult;
  end;

  { Background batch page deletion across multiple CBZ files }
  TDeletePagesThread = class(TServiceThread)
  private
    FFiles: TStringArray;
    FDir: string;
    FPagesToDelete: array of boolean;
    FRenumber: boolean;
    FDeletePerm: boolean;
    FResult: TDeletePagesResult;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFiles: TStringArray; const ADir: string;
      const APagesToDelete: array of boolean;
      ARenumber, ADeletePerm: boolean;
      AOnProgress: TProgressEvent);
    property Result: TDeletePagesResult read FResult;
  end;

implementation

{ TDeletePagesThread }

constructor TDeletePagesThread.Create(const AFiles: TStringArray;
  const ADir: string; const APagesToDelete: array of boolean;
  ARenumber, ADeletePerm: boolean; AOnProgress: TProgressEvent);
var
  i: integer;
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
  SetLength(FPagesToDelete, Length(APagesToDelete));
  for i := 0 to High(APagesToDelete) do
    FPagesToDelete[i] := APagesToDelete[i];
  FRenumber := ARenumber;
  FDeletePerm := ADeletePerm;
end;

procedure TDeletePagesThread.Execute;
var
  i: integer;
  FullPath: string;
  Entries: TZipEntries;
begin
  FResult.Success := True;
  FResult.Processed := 0;
  FResult.ErrorMsg := '';
  for i := 0 to High(FFiles) do
  begin
    if Terminated then
    begin
      FResult.ErrorMsg := 'Cancelled';  
      FResult.Success := False;
      Exit;
    end;
    FullPath := IncludeTrailingPathDelimiter(FDir) + FFiles[i];
    Progress((i * 100) div Length(FFiles),
      Format('Deleting pages from %s (%d/%d)', [FFiles[i], i + 1, Length(FFiles)]));
    Entries := FilterPagesFromCBZ(FullPath, FPagesToDelete, FRenumber);
    try
      if Length(Entries) > 0 then
      begin
        if FDeletePerm then
          WriteZipFromEntriesDeflated(FullPath, Entries)
        else
          ReplaceCBZ(FullPath, Entries);
        Inc(FResult.Processed);
      end;
    finally
      FreeZipEntries(Entries);
    end;
  end;
  Progress(100, Format('Complete: %d files processed', [FResult.Processed]));
end;

{ TServiceThread }

constructor TServiceThread.Create(AOnProgress: TProgressEvent);
begin
  inherited Create(True);  { Start suspended }
  FreeOnTerminate := True;
  FOnProgress := AOnProgress;
end;

procedure TServiceThread.Progress(APercent: integer; const AMsg: string);
begin
  FPendingPct := APercent;
  FPendingMsg := AMsg;
  if Assigned(FOnProgress) then
    TThread.Queue(nil, @SyncProgress);
end;

procedure TServiceThread.SyncProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(FPendingPct, FPendingMsg);
end;

{ TConvertThread }

constructor TConvertThread.Create(const AFiles: TStringArray;
  const ADir: string; const AOptions: TConvertOptions;
  AOnProgress: TProgressEvent);
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
  FOptions := AOptions;
end;

procedure TConvertThread.Execute;
begin
  FResult := TConvertService.Convert(FFiles, FDir, FOptions, @Progress);
end;

{ TMergeThread }

constructor TMergeThread.Create(const AFiles: TStringArray;
  const ADir: string; const AOptions: TMergeOptions;
  AOnProgress: TProgressEvent);
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
  FOptions := AOptions;
end;

procedure TMergeThread.Execute;
begin
  FResult := TMergeService.Merge(FFiles, FDir, FOptions, @Progress);
end;

{ TValidateThread }

constructor TValidateThread.Create(const AFiles: TStringArray;
  const ADir: string; AOnProgress: TProgressEvent);
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
end;

procedure TValidateThread.Execute;
begin
  FResult := TValidateService.ValidateDeep(FFiles, FDir);
end;

{ TComicInfoRemoveThread }

constructor TComicInfoRemoveThread.Create(const AFiles: TStringArray;
  const ADir: string; ABackup: boolean; AOnProgress: TProgressEvent);
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
  FBackup := ABackup;
end;

procedure TComicInfoRemoveThread.Execute;
begin
  FResult := TComicInfoService.Remove(FFiles, FDir, FBackup, @Progress);
end;

end.
