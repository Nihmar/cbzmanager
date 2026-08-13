unit uloaderthread;

{
  Background decoding with batched publication on the main thread.

  TThumbThread is the common base: descendants implement Produce and call
  Emit for every ready image; the base accumulates, publishes via Queue
  and fills ListView + ImageList. All images are reduced to CacheW x
  CacheH before being stored, so the zoom never re-reads the archives and
  memory usage stays bounded even with hundreds of pages.

  Batch publication
  -----------------
  Unlike Synchronize, Queue does not block the worker thread: the worker
  produces at full speed while the main thread consumes the batches when
  it has time. Image ownership is transferred from the worker to the main
  thread through the FPendingBatch field: the worker writes
  FPendingBatch + FPendingCount and immediately calls Queue(@SyncAddThumbs);
  SyncAddThumbs (run on the main thread) consumes the batch and clears the
  fields. The worker never frees FPendingBatch in the finally of Execute,
  because SyncAddThumbs is always processed before OnTerminate (same FIFO
  queue managed by CheckSynchronize).

  If the thread is terminated while a batch is still queued,
  SyncAddThumbs checks Terminated and calls FreePendingBatch to avoid a
  memory leak.

  If for any reason the worker produced faster than the main thread can
  consume, Flush briefly waits with Sleep(1) before overwriting
  FPendingBatch. In practice this never happens, because image decoding
  (disk I/O + decompression) is slow compared to adding a few entries to
  the ListView.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Forms,
  IntfGraphics,
  Graphics,
  ExtCtrls,
  ComCtrls,
  Controls,
  Generics.Collections;

const
  { Dimensione massima delle immagini tenute in RAM: coincide con il massimo
    ingrandimento consentito dallo zoom. }
  CacheW = 320;
  CacheH = 400;

type
  { A managed list of TLazIntfImage that owns its elements.
    Freeing the list also frees every contained image automatically. }
  TLazIntfImageList = specialize TObjectList<TLazIntfImage>;

  { One decoded image together with its archive entry name.
    The Image pointer may be nil when decoding failed; the consumer
    must check before using it. }
  TLoadedItem = record
    Name: string;
    Image: TLazIntfImage;
    HasComicInfo: boolean;
    { Sort position of this item in the destination list.  With multiple
      concurrent workers items arrive out of order; SyncAddThumbs inserts
      each item at this sorted position so the grid stays in order.
      -1 = append at the end (sequential producers). }
    Index: integer;
  end;
  TLoadedItems = array of TLoadedItem;

  { TThumbThread }

  TThumbThread = class(TThread)
  private
    FBatch: TLoadedItems;
    FBatchCount: integer;
    { Batch handed off to the main thread via Queue.  The worker swaps
      FBatch into these fields before Queue so it can continue producing
      without waiting; SyncAddThumbs consumes them on the main thread. }
    FPendingBatch: TLoadedItems;
    FPendingCount: integer;
    FImages: TImageList;
    FListView: TListView;
    FPages: TLazIntfImageList;
    FOnBatchAdded: TNotifyEvent;
    { Session guard: OwnerEpoch points at a caller-owned counter that is
      bumped whenever the destination lists are cleared (a new preview or
      directory load).  The worker captures the current value at Create;
      SyncAddThumbs discards any batch whose epoch no longer matches, so
      a stale batch from a previous session can never land in the freshly
      cleared lists (Terminated alone cannot catch this: a normally
      finished thread has Terminated = False while its last queued batch
      may still be pending). }
    FOwnerEpoch: PInteger;
    FEpoch: integer;
    { Frees every image remaining in FBatch (the current accumulation
      buffer that hasn't been handed off yet).  Called from the
      finally block of Execute on abnormal termination. }
    procedure FreeBatch;
    { Frees images in FPendingBatch.  Called from SyncAddThumbs when
      Terminated is True (the main thread discards an already-queued
      batch).  Never called from the worker thread. }
    procedure FreePendingBatch;
    { Publishes FPendingBatch to the ListView + ImageList.
      Runs on the main thread via TThread.Queue. }
    procedure SyncAddThumbs;
  protected
    { Runs on the worker thread: produces the images by calling Emit and
      must return as soon as Terminated becomes True. }
    procedure Produce; virtual; abstract;
    { Queues an image (possibly nil) to the current batch; ownership is
      transferred. AIndex is the item's sorted position in the destination
      list (-1 = append at the end, for sequential producers). }
    procedure Emit(const AName: string; AImage: TLazIntfImage;
      AHasComicInfo: boolean = False; AIndex: integer = -1);
    { Flushes the accumulated batch to the main thread immediately.
      Normally called automatically once BatchSize images have been
      emitted; also called at the end of Produce to flush any
      remainder. }
    procedure Flush;
    procedure Execute; override;
  public
    constructor Create;
    property ListView: TListView read FListView write FListView;
    property Pages: TLazIntfImageList read FPages write FPages;
    property Images: TImageList read FImages write FImages;
    { Session epoch as described above; leave nil to disable the check
      (e.g. unit tests without a session counter). }
    property OwnerEpoch: PInteger read FOwnerEpoch write FOwnerEpoch;
    { Fired on the main thread after each batch has been appended to the
      ListView.  Used for load-progress status updates. }
    property OnBatchAdded: TNotifyEvent read FOnBatchAdded write FOnBatchAdded;
  end;

  { TLoadThread: coordinator that loads the first pages of every .cbz in
    a folder using N concurrent workers (N = min(4, CPU)). The workers
    publish the thumbnails directly (batches via Queue); the coordinator
    stays alive until the last worker has finished, then OnTerminate
    notifies the UI. The coordinator's termination is propagated to the
    workers. }

  TLoadThread = class;  { forward — referenced by TLoadWorker }

  { TLoadWorker: single worker of the TLoadThread pool.  Pulls file names
    from the shared job cursor until the pool is exhausted or the pool is
    terminated.  Each worker keeps its own batch machinery, so multiple
    workers can queue batches to the main thread concurrently. }

  TLoadWorker = class(TThumbThread)
  private
    FPool: TLoadThread;
  protected
    procedure Produce; override;
    procedure Execute; override;
  public
    constructor Create(APool: TLoadThread);
    { No-op drained on the main thread to flush the worker's queued batches
      before it frees itself (see Execute). }
    procedure Drained;
  end;

  TLoadThread = class(TThumbThread)
  private
    FDir: string;
    FNames: TStringList;
    FTotal: integer;
    FJobCursor: integer;
    FFinished: integer;
    FWorkers: array of TLoadWorker;
    procedure WorkerTerminated(Sender: TObject);
    { Next file index to process, or -1 when the job list is exhausted.
      Thread-safe: workers compete on an atomic cursor. }
    function NextJob: integer;
  protected
    procedure Produce; override;
  public
    { Constructs the thread in a suspended state; the caller must set
      ListView, Pages, and Images before calling Start. }
    constructor Create(const ADir: string);
    { Number of .cbz files found (valid after Start). }
    property TotalFiles: integer read FTotal;
    { Session epoch forwarded to every worker (see TThumbThread.OwnerEpoch). }
    property OwnerEpoch: PInteger read FOwnerEpoch write FOwnerEpoch;
  end;

  { TPagesThread: all pages of a single .cbz }

  TPagesThread = class(TThumbThread)
  private
    FFile: string;
    procedure HandlePage(const AName: string; AImage: TLazIntfImage;
      AIndex: integer; var ACancel: boolean);
  protected
    procedure Produce; override;
  public
    constructor Create(const AFile: string);
  end;

implementation

uses
  uLog,
  uimgutil,
  uzipeditor,
  uservicebase,
  uservicemerge,
  Math;

const
  BatchSize = 12;

  { ComicInfo badge painted in the top-right corner of a thumbnail:
    a filled circle BADGE_SIZE pixels across, inset BADGE_MARGIN from
    the top and right edges. }
  BADGE_SIZE   = 12;
  BADGE_MARGIN = 2;

{ Number of concurrent thumbnail workers for the directory load: at most
  four, regardless of core count — decode + ZIP I/O parallelise well, but
  the main thread must keep up with the batch publication. }
function WorkerCount: integer;
begin
  Result := Min(4, Max(1, OnlineCpuCount));
end;

{ TThumbThread }

constructor TThumbThread.Create;
begin
  inherited Create(True);
  FBatchCount := 0;
  SetLength(FBatch, 0);
  FPendingCount := 0;
  SetLength(FPendingBatch, 0);
  FOwnerEpoch := nil;
  FEpoch := 0;
end;

procedure TThumbThread.Execute;
begin
  try
    try
      { OwnerEpoch is assigned after Create: capture the session epoch
        here, right before producing starts. }
      if FOwnerEpoch <> nil then
        FEpoch := FOwnerEpoch^;
      Produce;
      if not Terminated then
        Flush;
      Log('Thread: terminated normally');
    except
      on E: Exception do
        Log('Thread: UNHANDLED EXCEPTION %s: %s', [E.ClassName, E.Message]);
    end;
  finally
    { Current batch never published (interruption or exception): avoid the
      leak. FPendingBatch must NOT be freed here: it belongs to the main
      thread and SyncAddThumbs will process it before the thread is
      destroyed. }
    FreeBatch;  end;
end;

procedure TThumbThread.Emit(const AName: string; AImage: TLazIntfImage;
  AHasComicInfo: boolean; AIndex: integer);
begin
  Inc(FBatchCount);
  SetLength(FBatch, FBatchCount);
  FBatch[FBatchCount - 1].Name := AName;
  FBatch[FBatchCount - 1].Image := AImage;
  FBatch[FBatchCount - 1].HasComicInfo := AHasComicInfo;
  FBatch[FBatchCount - 1].Index := AIndex;
  if FBatchCount >= BatchSize then
    Flush;
end;

procedure TThumbThread.Flush;
begin
  if FBatchCount = 0 then Exit;
  { Waits until the main thread has consumed the previous batch
    (in practice never needed because decoding is slow). }
  while FPendingCount > 0 do
    Sleep(1);
  { Transfers ownership to the main thread. }
  FPendingBatch := FBatch;
  FPendingCount := FBatchCount;
  FBatch := nil;
  FBatchCount := 0;
  SetLength(FBatch, 0);
  TThread.Queue(nil, @SyncAddThumbs);
end;

procedure TThumbThread.FreeBatch;
var
  i: integer;
begin
  for i := 0 to FBatchCount - 1 do
    FBatch[i].Image.Free;
  FBatchCount := 0;
  SetLength(FBatch, 0);
end;

procedure TThumbThread.FreePendingBatch;
var
  i: integer;
begin
  for i := 0 to FPendingCount - 1 do
    FPendingBatch[i].Image.Free;
  FPendingCount := 0;
  SetLength(FPendingBatch, 0);
end;

procedure TThumbThread.SyncAddThumbs;
var
  i, j, k, ILIdx, pos: integer;
  Thumb: TBitmap;
  It: TListItem;
  Key: TLoadedItem;
begin
  if Terminated then
  begin
    { nobody will take over the images of the batch }
    FreePendingBatch;
    Exit;
  end;

  { Stale session: the destination lists were cleared and reused by a new
    preview/directory load after this batch was queued.  Discard it the
    same way (Terminated cannot catch a normally finished thread). }
  if (FOwnerEpoch <> nil) and (FEpoch <> FOwnerEpoch^) then
  begin
    Log('ThumbThread: discarding stale batch (epoch %d -> %d, %d item(s))',
      [FEpoch, FOwnerEpoch^, FPendingCount]);
    FreePendingBatch;
    Exit;
  end;

  { Sort the batch by sort position so out-of-order arrivals from parallel
    workers insert cleanly; entries with Index = -1 (append) are left in
    place.  A batch is small (BatchSize), so insertion sort is fine. }
  for j := 1 to FPendingCount - 1 do
  begin
    Key := FPendingBatch[j];
    if Key.Index < 0 then Continue;
    k := j - 1;
    while (k >= 0) and (FPendingBatch[k].Index >= 0) and
      (FPendingBatch[k].Index > Key.Index) do
    begin
      FPendingBatch[k + 1] := FPendingBatch[k];
      Dec(k);
    end;
    FPendingBatch[k + 1] := Key;
  end;

  FListView.BeginUpdate;
  try
    for i := 0 to FPendingCount - 1 do
    begin
      if FPendingBatch[i].Index < 0 then
        pos := FListView.Items.Count
      else
      begin
        { Sorted insertion: pos = count of already-inserted items whose sort
          key (stored in Data) is smaller.  Items then always appear in the
          same order as the jobs, regardless of arrival order. }
        pos := 0;
        while (pos < FListView.Items.Count) and
          (PtrInt(FListView.Items[pos].Data) < FPendingBatch[i].Index) do
          Inc(pos);
      end;

      FPages.Insert(pos, FPendingBatch[i].Image);
      Thumb := MakeThumb(FPendingBatch[i].Image, FImages.Width, FImages.Height);
      { Bake ComicInfo badge into the thumbnail bitmap }
      if FPendingBatch[i].HasComicInfo then
      begin
        Thumb.Canvas.Brush.Color := clLime;
        Thumb.Canvas.Pen.Color := clGreen;
        Thumb.Canvas.Ellipse(Thumb.Width - BADGE_MARGIN - BADGE_SIZE, BADGE_MARGIN,
          Thumb.Width - BADGE_MARGIN, BADGE_MARGIN + BADGE_SIZE);
      end;
      try
        ILIdx := FImages.Add(Thumb, nil);
      finally
        Thumb.Free;
      end;
      It := FListView.Items.Insert(pos);
      It.Data := Pointer(PtrInt(FPendingBatch[i].Index));
      It.Caption := ExtractChapterNumStr(FPendingBatch[i].Name);
      if It.Caption = '' then
        It.Caption := FPendingBatch[i].Name;
      It.SubItems.Add(FPendingBatch[i].Name);  // hidden — full filename for file ops
      It.ImageIndex := ILIdx;
    end;
  finally
    FListView.EndUpdate;
  end;
  { Images are now owned by FPages; clear the pending batch without
    freeing them. }
  FPendingCount := 0;
  SetLength(FPendingBatch, 0);
  if Assigned(FOnBatchAdded) then
    FOnBatchAdded(Self);
end;

{ TLoadThread }

{ Constructs the thread in a suspended state; the caller must set
  ListView, Pages, and Images before calling Start. }
constructor TLoadThread.Create(const ADir: string);
begin
  inherited Create;
  FDir := ADir;
end;

{ TLoadWorker }

constructor TLoadWorker.Create(APool: TLoadThread);
begin
  inherited Create;
  FPool := APool;
end;

{ No-op method used by Execute to flush the main thread's queue before the
  worker frees itself. }
procedure TLoadWorker.Drained;
begin
end;

{ Runs the shared thumbnail logic, then — on a normal exit — synchronously
  drains the main thread's queue.  CheckSynchronize processes queued
  methods FIFO, so by the time Drained runs on the main thread every
  previously queued SyncAddThumbs for this worker has been consumed: the
  subsequent FreeOnTerminate self-free can no longer discard a pending
  batch (which would leak its images) nor leave a queued method pointing
  at a freed object. }
procedure TLoadWorker.Execute;
begin
  inherited Execute;
  if not Terminated then
    Synchronize(@Drained);
end;

{ Pulls file names from the pool's job list, decoding the first page of
  each (at CacheW×CacheH via JPEG DCT scaling when possible) and emitting
  the scaled thumbnail.  Stops when the list is exhausted or the pool is
  terminated. }
procedure TLoadWorker.Produce;
var
  i: integer;
  FilePath: string;
  Img, Small: TLazIntfImage;
  HasComicInfo: boolean;
begin
  while not Terminated do
  begin
    i := FPool.NextJob;
    if i < 0 then Exit;
    FilePath := IncludeTrailingPathDelimiter(FPool.FDir) + FPool.FNames[i];
    Img := nil;
    HasComicInfo := False;
    try
      { Single pass: first image + ComicInfo presence, decoded at
        thumbnail size.  CBR archives (RAR) go through libarchive. }
      if SameText(ExtractFileExt(FilePath), CBR_EXT) then
        GetCbrFirstImageInfo(FilePath, Img, HasComicInfo, CacheW, CacheH)
      else
        GetFirstImageInfo(FilePath, Img, HasComicInfo, CacheW, CacheH);
    except
      on E: Exception do
      begin
        Log('Thread: exception on %s: %s: %s',
          [FPool.FNames[i], E.ClassName, E.Message]);
        Img := nil;
      end;
    end;

    Small := ScaleIntfImage(Img, CacheW, CacheH);
    Img.Free;
    Emit(FPool.FNames[i], Small, HasComicInfo, i);
  end;
end;

function TLoadThread.NextJob: integer;
begin
  Result := InterlockedIncrement(FJobCursor) - 1;
  if Result >= FTotal then
    Result := -1;
end;

{ Runs on the worker thread at its end; counts it as finished.  The worker
  has already drained the main thread's queue by this point (see
  TLoadWorker.Execute), so the coordinator can finish as soon as every
  worker is counted. }
procedure TLoadThread.WorkerTerminated(Sender: TObject);
begin
  InterlockedIncrement(FFinished);
end;

{ Iterates over every .cbz and .cbr file in FDir in sorted order,
  distributing the work across WorkerCount concurrent TLoadWorkers, and
  waits until all of them finish (or this pool is terminated).  CBR (RAR)
  archives are collected alongside CBZ so they appear in the file list;
  the per-file workers decode them via libarchive. }
procedure TLoadThread.Produce;
var
  Dir: string;
  FileList: TStringArray;
  CbrList: TStringArray;
  i: integer;
begin
  Dir := IncludeTrailingPathDelimiter(FDir);
  FileList := CollectCBZFiles(FDir);
  CbrList := CollectCBRFiles(FDir);
  FNames := TStringList.Create;
  try
    for i := 0 to High(FileList) do
      FNames.Add(FileList[i]);
    for i := 0 to High(CbrList) do
      FNames.Add(CbrList[i]);
    FNames.Sort;
    FTotal := FNames.Count;
    Log('Thread: %d comic archives found in %s (%d .cbr)', [FTotal, Dir,
      Length(CbrList)]);
    if FTotal = 0 then Exit;

    FJobCursor := 0;
    FFinished := 0;
    SetLength(FWorkers, WorkerCount);
    for i := 0 to High(FWorkers) do
    begin
      FWorkers[i] := TLoadWorker.Create(Self);
      FWorkers[i].OnTerminate := @WorkerTerminated;
      FWorkers[i].ListView := FListView;
      FWorkers[i].Pages := FPages;
      FWorkers[i].Images := FImages;
      FWorkers[i].OnBatchAdded := FOnBatchAdded;
      FWorkers[i].OwnerEpoch := FOwnerEpoch;
      FWorkers[i].FreeOnTerminate := True;
    end;
    for i := 0 to High(FWorkers) do
      FWorkers[i].Start;

    { Wait for every worker; on cancellation terminate them so their
      pending batches are discarded and they exit promptly.  Workers read
      the shared job list (FPool.FNames) at the end of each iteration,
      after the decode, so Produce must not return — and the coordinator
      must not free FNames or free itself — until every worker has really
      finished: otherwise a worker that was mid-iteration would read
      freed memory (access violation). }
    while FFinished < Length(FWorkers) do
    begin
      if Terminated then
      begin
        for i := 0 to High(FWorkers) do
          FWorkers[i].Terminate;
        { Join the workers before touching the shared state below.  Each
          worker exits at its next loop check once its current decode
          finishes, then increments FFinished. }
        while FFinished < Length(FWorkers) do
          Sleep(5);
        Break;
      end;
      Sleep(5);
    end;
  finally
    FNames.Free;
    FNames := nil;
    FWorkers := nil;
  end;
end;

{ TPagesThread }

{ Stores the single CBZ file whose pages should be loaded. }
constructor TPagesThread.Create(const AFile: string);
begin
  inherited Create;
  FFile := AFile;
end;

{ Opens the single archive and iterates over every page via ForEachImage
  (or ForEachCbrImage for RAR/CBR archives).  HandlePage receives each
  decoded page.  Pages are decoded at CacheW×CacheH (JPEG DCT scaling) so
  large archives load quickly. }
procedure TPagesThread.Produce;
begin
  Log('Pages: opening %s', [ExtractFileName(FFile)]);
  if SameText(ExtractFileExt(FFile), CBR_EXT) then
    ForEachCbrImage(FFile, @HandlePage, CacheW, CacheH)
  else
    ForEachImage(FFile, @HandlePage, CacheW, CacheH);
end;

{ ForEachImage callback: scales the decoded full-size image to the
  thumbnail cache dimensions (CacheW×CacheH), emits the result, and
  respects Terminated to abort early.  AIndex is the page's position in
  alphabetical name order (0 = first page), so the sorted insertion in
  SyncAddThumbs displays pages in reading order even when the archive
  stores them scrambled. }
procedure TPagesThread.HandlePage(const AName: string; AImage: TLazIntfImage;
  AIndex: integer; var ACancel: boolean);
var
  Small: TLazIntfImage;
begin
  Small := ScaleIntfImage(AImage, CacheW, CacheH);
  AImage.Free;
  Emit(AName, Small, False, AIndex);
  ACancel := Terminated;
end;

end.
