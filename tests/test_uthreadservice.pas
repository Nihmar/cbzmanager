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
end.
