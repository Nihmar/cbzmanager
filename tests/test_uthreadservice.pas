unit test_uthreadservice;
{$mode objfpc}{$h+}
{ Regression tests for the TServiceThread progress callback plumbing.

  History: Progress() used TThread.Queue(nil, @SyncProgress).  With
  FreeOnTerminate=True the queued method could run after the thread object
  was freed (SIGSEGV in SyncProgress), and FPC's CheckSynchronize re-raises
  exceptions from queued methods on the MAIN thread, escaping the event
  loop and killing the app ("Range check error" + crash).  The fix uses a
  blocking Synchronize instead: the thread object stays alive during the
  call and exceptions are passed back to the worker's Execute. }
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils,
  uthreadservice;

type
  TServiceThreadTest = class(TTestCase)
  published
    { The callback receives every Progress() value, in order, via the
      main thread (the runner pumps CheckSynchronize through WaitFor). }
    procedure Progress_DeliversValuesToMainThread;
    { A raising progress callback must surface inside the worker's Execute
      (per-file try/except can record it), not escape on the main thread. }
    procedure Progress_RaisingCallbackStaysInWorker;
  end;

  TDeletePagesThreadTest = class(TTestCase)
  private
    FTempDir: string;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure MakeBook(const ADir, AName: string);
  published
    { Threads 1 vs 4 over three archives must rewrite the same bytes and
      report the same outcome (per-file failures never abort the batch). }
    procedure DeletePages_ThreadsDeterministic;
  end;

  { Probe: reports Progress values through an object-owned callback. }
  TProgressProbeThread = class(TServiceThread)
  protected
    procedure Execute; override;
  end;

  { Probe: its progress callback raises; Execute catches and records. }
  TRaisingProbeThread = class(TServiceThread)
  private
    FWorkerError: string;
  protected
    procedure Execute; override;
  public
    property WorkerError: string read FWorkerError;
  end;

  { Owns the progress callback (must exist before the thread is created:
    method-pointer self-references are nil until the object is assigned). }
  TCallbackRecorder = class
    Calls: integer;
    LastPct: integer;
    LastMsg: string;
    WorkerError: string;
    procedure OnProgress(APercent: integer; const AMsg: string);
    procedure OnProgressRaise(APercent: integer; const AMsg: string);
  end;

implementation

uses
  FileUtil,
  test_helpers;

procedure TDeletePagesThreadTest.SetUp;
begin
  FTempDir := CreateTempDir('cbzdel_');
end;

procedure TDeletePagesThreadTest.TearDown;
begin
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
end;

procedure TDeletePagesThreadTest.MakeBook(const ADir, AName: string);
var
  Png: TMemoryStream;
begin
  Png := CreateMinimalPNGStream;
  try
    CreateCBZ(ADir + AName, [Png, Png, Png], ['p1.png', 'p2.png', 'p3.png']);
  finally
    Png.Free;
  end;
end;

procedure TDeletePagesThreadTest.DeletePages_ThreadsDeterministic;
var
  Dir1, Msg: string;
  Files: TStringArray;
  Mask: array of boolean;
  T1, T4: TDeletePagesThread;
  R1, R4: TDeletePagesResult;
  i: integer;
begin
  Dir1 := CreateTempDir('cbzdel_t1_');
  try
    for i := 1 to 3 do
    begin
      MakeBook(FTempDir, Format('book%d.cbz', [i]));
      MakeBook(Dir1, Format('book%d.cbz', [i]));
    end;
    SetLength(Files, 3);
    for i := 1 to 3 do
      Files[i - 1] := Format('book%d.cbz', [i]);

    { Delete the middle page of three, renumber survivors, keep backups. }
    SetLength(Mask, 3);
    Mask[0] := False;
    Mask[1] := True;
    Mask[2] := False;

    T1 := TDeletePagesThread.Create(Files, FTempDir, Mask, True, False, nil, 1);
    T1.FreeOnTerminate := False;
    try
      T1.Start;
      T1.WaitFor;
      R1 := T1.Result;
    finally
      T1.Free;
    end;
    AssertTrue('sequential succeeded', R1.Success);
    AssertEquals('sequential processed 3', 3, R1.Processed);

    T4 := TDeletePagesThread.Create(Files, Dir1, Mask, True, False, nil, 4);
    T4.FreeOnTerminate := False;
    try
      T4.Start;
      T4.WaitFor;
      R4 := T4.Result;
    finally
      T4.Free;
    end;
    AssertTrue('pooled succeeded', R4.Success);
    AssertEquals('pooled processed 3', 3, R4.Processed);

    Msg := '';
    for i := 1 to 3 do
      AssertTrue(Format('book%d identical (threads 1 vs 4): %s', [i, Msg]),
        ZipFilesEqual(FTempDir + Format('book%d.cbz', [i]),
          Dir1 + Format('book%d.cbz', [i]), Msg));
  finally
    if DirectoryExists(Dir1) then
      DeleteDirectory(Dir1, False);
  end;
end;

procedure TProgressProbeThread.Execute;
begin
  Progress(10, 'first');
  Progress(50, 'second');
  Progress(100, 'last');
end;

procedure TRaisingProbeThread.Execute;
begin
  try
    Progress(10, 'boom');
  except
    on E: Exception do
      FWorkerError := E.Message;
  end;
end;

procedure TCallbackRecorder.OnProgress(APercent: integer; const AMsg: string);
begin
  Inc(Calls);
  LastPct := APercent;
  LastMsg := AMsg;
end;

procedure TCallbackRecorder.OnProgressRaise(APercent: integer; const AMsg: string);
begin
  raise Exception.Create('callback boom');
end;

procedure TServiceThreadTest.Progress_DeliversValuesToMainThread;
var
  T: TProgressProbeThread;
  R: TCallbackRecorder;
begin
  R := TCallbackRecorder.Create;
  try
    T := TProgressProbeThread.Create(@R.OnProgress);
    T.FreeOnTerminate := False;
    try
      T.Start;
      { WaitFor pumps CheckSynchronize on the main thread, which is what the
        GUI event loop does while the job runs. }
      T.WaitFor;
      AssertEquals('three progress calls delivered', 3, R.Calls);
      AssertEquals('last percentage', 100, R.LastPct);
      AssertEquals('last message', 'last', R.LastMsg);
    finally
      T.Free;
    end;
  finally
    R.Free;
  end;
end;

procedure TServiceThreadTest.Progress_RaisingCallbackStaysInWorker;
var
  T: TRaisingProbeThread;
  R: TCallbackRecorder;
begin
  R := TCallbackRecorder.Create;
  try
    T := TRaisingProbeThread.Create(@R.OnProgressRaise);
    T.FreeOnTerminate := False;
    try
      T.Start;
      { If Progress used Queue, the callback's exception would be re-raised
        here on the main thread (test failure).  With Synchronize it is
        passed back to the worker and caught in Execute. }
      T.WaitFor;
      AssertEquals('exception recorded in worker', 'callback boom',
        T.WorkerError);
    finally
      T.Free;
    end;
  finally
    R.Free;
  end;
end;

initialization
  RegisterTest(TServiceThreadTest);
  RegisterTest(TDeletePagesThreadTest);
end.
