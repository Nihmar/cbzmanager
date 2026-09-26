unit uservicepool;

{
  uservicepool – shared worker-pool machinery for the batch services.

  Five services (validate, convert, cbr-to-cbz, merge, delete-pages) used to
  carry their own copy of the same shape: a pool state class with a critical
  section, a lock-guarded claim counter and a slot array; a TThread subclass
  that claimed indices and wrote results into per-index slots; and an
  identical spawn/join/free block that also honoured cooperative
  cancellation.  TIndexPool/TIndexPoolWorker keep that machinery in one
  place; a service only owns its data and overrides ProcessIndex (and
  optionally CreateWorker / Cancelled).

  Ownership: workers are created suspended and are NOT FreeOnTerminate; Run
  spawns them, waits for them (propagating cancellation) and frees them.
  The pool lock is exposed to subclasses so their progress callback can be
  serialized with the same critical section.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uservicebase;

type
  TIndexPool = class;

  { Base worker: claims indices from its pool until exhausted/stopped and
    runs ProcessIndex on each. }
  TIndexPoolWorker = class(TThread)
  private
    FPool: TIndexPool;
  protected
    { Processes one claimed index.  Runs on the worker thread; exceptions
      abort the worker (the service records them per slot). }
    procedure ProcessIndex(AIndex: integer); virtual; abstract;
    procedure Execute; override;
  public
    constructor Create(APool: TIndexPool);
  end;

  TIndexPool = class
  private
    FLock: TRTLCriticalSection;
    FLockPtr: PRTLCriticalSection;
    FNext: integer;
    FStop: boolean;
    FTotal: integer;
    FWorkers: array of TIndexPoolWorker;
  protected
    { Creates one worker of the service's type.  Created suspended; the base
      Start()s it. }
    function CreateWorker: TIndexPoolWorker; virtual; abstract;
    { Claims the next index; False when exhausted or stopped.  Thread-safe. }
    function Claim(out AIndex: integer): boolean;
    { Stops every worker from claiming new work (e.g. abort on error). }
    procedure RequestStop;
    { True when the owning service thread was asked to terminate.  Override
      with the owner's state so Run can propagate cancellation; the default
      (never cancelled) keeps the pool usable without an owner. }
    function Cancelled: boolean; virtual;
    property Total: integer read FTotal;
  public
    constructor Create(ATotal: integer);
    destructor Destroy; override;
    { Spawns AThreads workers (must be > 0), waits for all of them and frees
      them.  When Cancelled becomes true the workers are terminated and
      joined; items already being processed still complete. }
    procedure Run(AThreads: integer);
    { The pool critical section: subclasses serialize their progress
      callback through it so a blocking Synchronize is never entered twice
      at once. }
    procedure LockPool;
    procedure UnlockPool;
    { Address of the critical section, for TLockedProgress. }
    property Lock: PRTLCriticalSection read FLockPtr;
  end;

implementation

{ TIndexPoolWorker }

constructor TIndexPoolWorker.Create(APool: TIndexPool);
begin
  { Created suspended: the pool Start()s every worker before joining. }
  inherited Create(True);
  FPool := APool;
end;

procedure TIndexPoolWorker.Execute;
var
  Idx: integer;
begin
  while not Terminated do
  begin
    if not FPool.Claim(Idx) then Exit;
    ProcessIndex(Idx);
  end;
end;

{ TIndexPool }

constructor TIndexPool.Create(ATotal: integer);
begin
  inherited Create;
  FTotal := ATotal;
  FNext := 0;
  FStop := False;
  InitCriticalSection(FLock);
  FLockPtr := @FLock;
end;

destructor TIndexPool.Destroy;
begin
  { Workers are freed by Run; anything left is a programming error. }
  SetLength(FWorkers, 0);
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

function TIndexPool.Claim(out AIndex: integer): boolean;
begin
  EnterCriticalSection(FLock);
  try
    if FStop or (FNext >= FTotal) then
      Exit(False);
    AIndex := FNext;
    Inc(FNext);
    Result := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TIndexPool.RequestStop;
begin
  EnterCriticalSection(FLock);
  try
    FStop := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TIndexPool.LockPool;
begin
  EnterCriticalSection(FLock);
end;

procedure TIndexPool.UnlockPool;
begin
  LeaveCriticalSection(FLock);
end;

function TIndexPool.Cancelled: boolean;
begin
  Result := False;
end;

procedure TIndexPool.Run(AThreads: integer);
var
  i: integer;
  AllDone: boolean;
begin
  if AThreads < 1 then Exit;
  SetLength(FWorkers, AThreads);
  try
    for i := 0 to AThreads - 1 do
      FWorkers[i] := CreateWorker;
    for i := 0 to AThreads - 1 do
      FWorkers[i].Start;

    { Join with cancel propagation: terminating the pool terminates its
      workers so they exit at the next claim/loop check. }
    repeat
      if Cancelled then
      begin
        for i := 0 to High(FWorkers) do
          FWorkers[i].Terminate;
        Break;
      end;
      AllDone := True;
      for i := 0 to High(FWorkers) do
        if not FWorkers[i].Finished then
        begin
          AllDone := False;
          Break;
        end;
      if AllDone then Break;
      Sleep(5);
    until False;

    for i := 0 to High(FWorkers) do
      FWorkers[i].WaitFor;
  finally
    for i := 0 to High(FWorkers) do
      FWorkers[i].Free;
    SetLength(FWorkers, 0);
  end;
end;

end.
