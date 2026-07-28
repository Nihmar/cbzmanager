unit ufrmjobmonitor;

{ ============================================================================
  ufrmjobmonitor – Non-modal floating window showing real-time job progress.

  Displays:
    - Operation title and progress bar.
    - Current task description and elapsed time.
    - Scrolling log with timestamped messages (captures both service progress
      messages and Log() output via the TLogObserver mechanism).

  Usage:
    1. Create with TfrmJobMonitor.Create(Application).
    2. Call StartJob('Converting to WebP') — shows the form, starts the timer.
    3. Call UpdateProgress(percent, message) from the progress callback.
    4. Call FinishJob — enables the Close button, stops the timer.
    5. The user closes the form manually.

  The form registers itself as a log observer on create and unregisters on
  destroy.  Log messages are marshalled to the main thread via TThread.Queue.
  ============================================================================ }

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ComCtrls,
  ExtCtrls, LCLType, uLog;

type
  TfrmJobMonitor = class(TForm)
    PanelTop: TPanel;
    LblTitle: TLabel;
    ProgressBar: TProgressBar;
    LblTask: TLabel;
    LblElapsed: TLabel;
    MemoLog: TMemo;
    PanelBottom: TPanel;
    BtnClose: TButton;
    TimerElapsed: TTimer;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure BtnCloseClick(Sender: TObject);
    procedure TimerElapsedTimer(Sender: TObject);
  private
    FStartTime: TDateTime;
    FJobRunning: boolean;
    FLogPending: TStringList;   // thread-safe buffer for log lines
    FLogLock: TRTLCriticalSection;
    procedure FlushLog;          // called by TimerElapsed to drain FLogPending into MemoLog
    procedure OnLogLine(const AMsg: string);  // TLogObserver callback
  public
    constructor Create(AOwner: TComponent); override;
    { Start monitoring a job.  Shows the form non-modally. }
    procedure StartJob(const ATitle: string);
    { Update progress bar and current task label.  Also appends AMsg to log. }
    procedure UpdateProgress(APercent: integer; const AMsg: string);
    { Mark the job as finished.  Enables Close, stops the timer. }
    procedure FinishJob;
  end;

implementation

{$R *.lfm}

{ TfrmJobMonitor }

constructor TfrmJobMonitor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  InitCriticalSection(FLogLock);
  FLogPending := TStringList.Create;
  FJobRunning := False;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  RegisterLogObserver(@OnLogLine);
end;

procedure TfrmJobMonitor.FormDestroy(Sender: TObject);
begin
  UnregisterLogObserver;
  TimerElapsed.Enabled := False;
  FLogPending.Free;
  DoneCriticalSection(FLogLock);
end;

procedure TfrmJobMonitor.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if FJobRunning then
  begin
    // Prevent closing while a job is running — the Close button is disabled
    // anyway, but Alt+F4 could bypass that.
    CloseAction := caNone;
  end;
end;

procedure TfrmJobMonitor.FormKeyDown(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  // Escape closes the monitor only when the job is finished
  if (Key = VK_ESCAPE) and not FJobRunning then
  begin
    Close;
    Key := 0;
  end;
end;

procedure TfrmJobMonitor.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmJobMonitor.TimerElapsedTimer(Sender: TObject);
begin
  // Update elapsed time display
  LblElapsed.Caption := FormatDateTime('nn:ss', Now - FStartTime);
  // Drain any pending log lines into the memo
  FlushLog;
end;

{ Called from the log observer (any thread).  Pushes the message into a
  thread-safe buffer; the timer drains it on the main thread. }
procedure TfrmJobMonitor.OnLogLine(const AMsg: string);
begin
  EnterCriticalSection(FLogLock);
  try
    FLogPending.Add(AMsg);
  finally
    LeaveCriticalSection(FLogLock);
  end;
end;

{ Called on the main thread by TimerElapsed.  Drains FLogPending into MemoLog. }
procedure TfrmJobMonitor.FlushLog;
var
  i: integer;
begin
  if FLogPending.Count = 0 then Exit;
  EnterCriticalSection(FLogLock);
  try
    MemoLog.Lines.BeginUpdate;
    try
      for i := 0 to FLogPending.Count - 1 do
        MemoLog.Lines.Add(FLogPending[i]);
      // Auto-scroll to the bottom in constant time
      MemoLog.SelStart := MaxInt;
    finally
      MemoLog.Lines.EndUpdate;
    end;
    FLogPending.Clear;
  finally
    LeaveCriticalSection(FLogLock);
  end;
end;

procedure TfrmJobMonitor.StartJob(const ATitle: string);
begin
  LblTitle.Caption := ATitle;
  ProgressBar.Position := 0;
  LblTask.Caption := '';
  LblElapsed.Caption := '00:00';
  MemoLog.Clear;
  FStartTime := Now;
  FJobRunning := True;
  BtnClose.Enabled := False;
  TimerElapsed.Enabled := True;
  Show;
end;

procedure TfrmJobMonitor.UpdateProgress(APercent: integer; const AMsg: string);
begin
  // Called from the main thread via TThread.Queue / SyncProgress chain
  ProgressBar.Position := APercent;
  LblTask.Caption := AMsg;
  // Also append as a log entry (the progress messages are also useful history)
  MemoLog.Lines.BeginUpdate;
  try
    MemoLog.Lines.Add(AMsg);
  finally
    MemoLog.Lines.EndUpdate;
  end;
  // Auto-scroll to bottom in constant time (avoid O(n^2) Lines.Text concat)
  MemoLog.SelStart := MaxInt;
end;

procedure TfrmJobMonitor.FinishJob;
begin
  FJobRunning := False;
  TimerElapsed.Enabled := False;
  // Final drain of any remaining log lines
  FlushLog;
  LblTask.Caption := 'Done';
  BtnClose.Enabled := True;
end;

end.
