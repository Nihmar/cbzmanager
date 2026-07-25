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
  uZipEditor, uservicebase, userviceconvert, uservicemerge;

type

  { Base class: wraps TProgressEvent with TThread.Queue for safe UI updates.
    Descendants set FResult in Execute; the OnTerminate handler reads it. }
  TServiceThread = class(TThread)
  private
    FOnProgress: TProgressEvent;
    FCancelled: boolean;
    FPendingPct: integer;
    FPendingMsg: string;
    procedure SyncProgress;
  protected
    { Call from Execute to report progress safely to the main thread. }
    procedure Progress(APercent: integer; const AMsg: string);
    { Check periodically in Execute to support cancellation. }
    property Cancelled: boolean read FCancelled;
  public
    constructor Create(AOnProgress: TProgressEvent);
    procedure Cancel;
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

implementation

{ TServiceThread }

constructor TServiceThread.Create(AOnProgress: TProgressEvent);
begin
  inherited Create(True);  { Start suspended }
  FreeOnTerminate := True;
  FOnProgress := AOnProgress;
  FCancelled := False;
end;

procedure TServiceThread.Cancel;
begin
  FCancelled := True;
  Terminate;
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

end.
