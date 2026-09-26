unit test_uloaderthread;

{$mode objfpc}{$H+}

{ Tests for the thumbnail-loader session guard (uloaderthread): a queued
  batch whose epoch no longer matches the owner's counter must be
  discarded instead of landing in freshly cleared lists — the race behind
  the rapid-file-switching listview crash. }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TLoaderThreadTest = class(TTestCase)
  private
    FAppInitialized: boolean;
    FEpoch: integer;
    procedure EnsureApp;
  published
    procedure Epoch_MatchingBatchLands;
    procedure Epoch_StaleBatchDiscarded;
    { A worker that terminates while Flush is waiting for the main thread
      must give up the batch and exit, not spin forever. }
    procedure Flush_TerminatedWorker_Exits;
  end;

implementation

uses
  Forms, Controls, ComCtrls, IntfGraphics,
  uloaderthread,
  uzipeditor,
  test_helpers;

type
  { Minimal TThumbThread: decodes one image, emits it, and flushes. }
  TProbeThumbThread = class(TThumbThread)
  private
    FStream: TMemoryStream;
  protected
    procedure Produce; override;
  public
    constructor Create(ASourceStream: TMemoryStream);
    destructor Destroy; override;
  end;

  { Two flushes without the main thread consuming the first one: the second
    Flush has to wait (FPendingCount > 0), which is exactly the state the
    cancellation check must break out of. }
  TDoubleFlushThumbThread = class(TThumbThread)
  protected
    procedure Produce; override;
  end;

procedure TDoubleFlushThumbThread.Produce;
begin
  Emit('a.png', nil, False, 0);
  Flush;
  Emit('b.png', nil, False, 1);
  Flush;
end;

constructor TProbeThumbThread.Create(ASourceStream: TMemoryStream);
begin
  inherited Create;
  FStream := ASourceStream;
end;

destructor TProbeThumbThread.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;

procedure TProbeThumbThread.Produce;
var
  Img: TLazIntfImage;
begin
  FStream.Position := 0;
  Img := DecodeImage(FStream, '.png');
  Emit('page_0001.png', Img, False, 0);
  Flush;
end;

procedure TLoaderThreadTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

{ Builds a probe thread wired to fresh destination lists and the test's
  epoch counter.  Caller frees everything. }
function MakeProbe(const AOwningTest: TLoaderThreadTest;
  out ALV: TListView; out APages: TLazIntfImageList;
  out AImages: TImageList): TProbeThumbThread;
begin
  ALV := TListView.Create(nil);
  APages := TLazIntfImageList.Create(True);
  AImages := TImageList.Create(nil);
  AImages.Width := 96;
  AImages.Height := 128;
  Result := TProbeThumbThread.Create(CreateMinimalPNGStream);
  Result.ListView := ALV;
  Result.Pages := APages;
  Result.Images := AImages;
  Result.OwnerEpoch := @AOwningTest.FEpoch;
end;

procedure TLoaderThreadTest.Epoch_MatchingBatchLands;
var
  LV: TListView;
  Pages: TLazIntfImageList;
  Imgs: TImageList;
  T: TProbeThumbThread;
begin
  EnsureApp;
  FEpoch := 1;
  T := MakeProbe(Self, LV, Pages, Imgs);
  T.FreeOnTerminate := False;
  try
    T.Start;
    while not T.Finished do Sleep(1);
    CheckSynchronize;
    AssertEquals('item landed', 1, LV.Items.Count);
    AssertEquals('thumbnail cached', 1, Pages.Count);
    AssertEquals('image list entry', 1, Imgs.Count);
  finally
    T.Free;
    Imgs.Free;
    Pages.Free;
    LV.Free;
  end;
end;

procedure TLoaderThreadTest.Epoch_StaleBatchDiscarded;
var
  LV: TListView;
  Pages: TLazIntfImageList;
  Imgs: TImageList;
  T: TProbeThumbThread;
begin
  EnsureApp;
  FEpoch := 7;
  T := MakeProbe(Self, LV, Pages, Imgs);
  T.FreeOnTerminate := False;
  try
    T.Start;
    { The worker captures the epoch at the start of Execute; bump the
      counter only after the thread has finished, exactly like
      ClearPreview/ClearThumbnails do when a new session clears the
      lists while the old batch is still queued. }
    while not T.Finished do Sleep(1);
    FEpoch := 8;
    CheckSynchronize;
    AssertEquals('stale batch discarded', 0, LV.Items.Count);
    AssertEquals('no thumbnail cached', 0, Pages.Count);
    AssertEquals('no image list entry', 0, Imgs.Count);
  finally
    T.Free;
    Imgs.Free;
    Pages.Free;
    LV.Free;
  end;
end;

procedure TLoaderThreadTest.Flush_TerminatedWorker_Exits;
var
  LV: TListView;
  Pages: TLazIntfImageList;
  Imgs: TImageList;
  T: TDoubleFlushThumbThread;
  Deadline: QWord;
begin
  EnsureApp;
  LV := TListView.Create(nil);
  Pages := TLazIntfImageList.Create(True);
  Imgs := TImageList.Create(nil);
  T := TDoubleFlushThumbThread.Create;
  T.ListView := LV;
  T.Pages := Pages;
  T.Images := Imgs;
  T.FreeOnTerminate := False;
  try
    T.Start;
    { Give the worker time to queue the first batch and block in the second
      Flush.  The main thread never consumes the queue here. }
    Sleep(50);
    T.Terminate;

    Deadline := GetTickCount64 + 3000;
    while (not T.Finished) and (GetTickCount64 < Deadline) do
      Sleep(5);
    AssertTrue('terminating worker must not spin in Flush', T.Finished);

    { Consume the queued batch (discarded because the worker is terminated)
      while the thread object is still alive. }
    CheckSynchronize;
  finally
    if not T.Finished then
    begin
      { Backstop for a regression in Flush: consume the pending batch so the
        worker can leave its wait and be freed, instead of hanging the whole
        suite in T.Free. }
      CheckSynchronize;
      Deadline := GetTickCount64 + 3000;
      while (not T.Finished) and (GetTickCount64 < Deadline) do
        Sleep(5);
    end;
    T.Free;
    Imgs.Free;
    Pages.Free;
    LV.Free;
  end;
end;

initialization
  RegisterTest(TLoaderThreadTest);
end.
