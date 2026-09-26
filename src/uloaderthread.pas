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
  consume, Flush waits with Sleep(1) before overwriting FPendingBatch.  In
  practice this never happens, because image decoding (disk I/O +
  decompression) is slow compared to adding a few entries to the ListView;
  the wait is bounded by Terminated so a shutting-down worker drops its
  batch and exits instead of spinning.
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
  Generics.Collections,
  uzipcore;

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

  TPagesThread = class;  { forward — referenced by TPagesWorker }

  { TPagesWorker: single worker of the TPagesThread pool.  Pulls entry
    indices from the shared job cursor until the pool is exhausted or the
    pool is terminated.  Each worker keeps its own batch machinery, so
    multiple workers can queue batches to the main thread concurrently
    (same shape as TLoadWorker). }

  TPagesWorker = class(TThumbThread)
  private
    FPool: TPagesThread;
  protected
    procedure Produce; override;
    procedure Execute; override;
  public
    constructor Create(APool: TPagesThread);
    { No-op drained on the main thread to flush the worker's queued batches
      before it frees itself (see Execute). }
    procedure Drained;
  end;

  TPagesThread = class(TThumbThread)
  private
    FFile: string;
    FThreads: integer;
    { Pool state: the collected entries (read-only source), the job list
      (entry indices of image pages), the alphabetical rank per entry
      index, and the shared cursors.  Freed after every worker finished. }
    FEntries: TZipEntries;
    FJobs: array of integer;
    FRanks: array of integer;
    FJobCursor: integer;
    FFinished: integer;
    FWorkers: array of TPagesWorker;
    procedure HandlePage(const AName: string; AImage: TLazIntfImage;
      AIndex: integer; var ACancel: boolean);
    { Next job position in FJobs, or -1 when exhausted.  Thread-safe:
      workers compete on an atomic cursor. }
    function NextJob: integer;
    { Sequential path: the historical streaming walk (one page in RAM at
      a time). }
    procedure ProduceSequential;
    { Parallel path: collect the archive once, then decode + scale pages
      on a worker pool.  Every worker holds only its current page in RAM,
      but the collected entries stay alive until the last worker finished. }
    procedure ProduceParallel(AThreadCount: integer);
  protected
    procedure Produce; override;
  public
    { Constructs the thread in a suspended state; the caller must set
      ListView, Pages, and Images before calling Start.
      AThreads selects the page-decode pool size: 0 = automatic
      (WorkerCount), 1 = sequential streaming. }
    constructor Create(const AFile: string; AThreads: integer = 0);
  end;

implementation

uses
  Math,
  uLog,
  uimgutil,
  uzipeditor,
  uservicebase,
  uservicemerge;

{ Orders by the sort position SyncAddThumbs stashed in each item's Data.
  The list is already in this order — the point is not the comparison but
  what CustomSort does with it; see ResyncOrder. }
function CompareBySortIndex(Item1, Item2: TListItem;
  AOptionalParam: PtrInt): Integer; stdcall;
begin
  Result := CompareValue(PtrInt(Item1.Data), PtrInt(Item2.Data));
end;

{ The LCL item list is always in the right order, but a native Win32 list
  view in icon mode does not re-flow the icons already on screen when an item
  is inserted ahead of them, so a parallel load looks unsorted until the user
  happens to resize the window.  Neither LVM_ARRANGE nor LVM_UPDATE moves it:
  with LVS_AUTOARRANGE set the control considers itself already arranged.

  CustomSort is the supported way through.  It sorts the LCL list, then hands
  the widgetset a SetSort, which on Win32 issues LVM_SORTITEMS with a
  comparator that orders native items by their LCL item Index — so the
  control is re-ordered to match the LCL list and re-flows for real.

  The comparator agrees with the order the list is already in, so this never
  moves an item and never disturbs the alignment between the list view and
  the image cache.  On Qt and GTK the views lay out from the model anyway,
  which makes this redundant but harmless.

  Only call this for batches that carried real sort positions: the append
  path stamps every item with -1, and TFPList.Sort is a quicksort, so sorting
  on an all-equal key could permute them. }
procedure ResyncOrder(ALV: TListView);
begin
  if Assigned(ALV) and ALV.HandleAllocated and (ALV.Items.Count > 1) then
    ALV.CustomSort(@CompareBySortIndex, 0);
end;

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
  { The main thread consumes one batch at a time, so wait until it took the
    previous one.  The wait is cancellation-aware: a terminating worker drops
    the accumulated batch (Execute's finally frees it) instead of spinning
    forever while the main thread is busy or shutting down. }
  while (FPendingCount > 0) and not Terminated do
    Sleep(1);
  if FPendingCount > 0 then Exit;
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
  { True once this batch has inserted an item carrying a real sort position. }
  Sorted: boolean;
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

  Sorted := False;
  FListView.BeginUpdate;
  try
    for i := 0 to FPendingCount - 1 do
    begin
      if FPendingBatch[i].Index < 0 then
        pos := FListView.Items.Count
      else
      begin
        Sorted := True;
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
  { The batch may have inserted items ahead of ones already on screen; push
    the order into the widget.  See ResyncOrder. }
  if Sorted then
    ResyncOrder(FListView);
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

{ Runs the shared thumbnail logic, counts the worker as finished and — on a
  normal exit — synchronously drains the main thread's queue.  The count
  happens BEFORE the drain: the coordinator waits on FFinished, which must
  not depend on the main thread pumping its message queue (a modal dialog
  used to stall the pool join).  CheckSynchronize processes queued methods
  FIFO, so by the time Drained runs every previously queued SyncAddThumbs
  for this worker has been consumed: the subsequent FreeOnTerminate
  self-free can no longer discard a pending batch (which would leak its
  images) nor leave a queued method pointing at a freed object. }
procedure TLoadWorker.Execute;
begin
  inherited Execute;
  InterlockedIncrement(FPool.FFinished);
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

{ TPagesWorker }

constructor TPagesWorker.Create(APool: TPagesThread);
begin
  inherited Create;
  FPool := APool;
end;

{ No-op method used by Execute to flush the main thread's queue before the
  worker frees itself (same rationale as TLoadWorker.Execute). }
procedure TPagesWorker.Drained;
begin
end;

procedure TPagesWorker.Execute;
begin
  inherited Execute;
  InterlockedIncrement(FPool.FFinished);
  if not Terminated then
    Synchronize(@Drained);
end;

{ Claims entry indices from the pool's job list, decoding each page at
  CacheW×CacheH (JPEG DCT scaling when possible) and emitting the scaled
  thumbnail with its alphabetical rank — the same two steps as the
  sequential HandlePage.  Stops when the list is exhausted or the pool is
  terminated. }
procedure TPagesWorker.Produce;
var
  JobPos, EntryIdx: integer;
  Img, Small: TLazIntfImage;
begin
  while not Terminated do
  begin
    JobPos := FPool.NextJob;
    if JobPos < 0 then Exit;
    EntryIdx := FPool.FJobs[JobPos];
    { DecodeImage never raises (failures become nil); ScaleIntfImage is
      nil-safe.  A nil Small is emitted like the sequential path does for
      undecodable pages — the consumer must check before using it. }
    Img := DecodeImage(FPool.FEntries[EntryIdx].Data,
      ExtractFileExt(FPool.FEntries[EntryIdx].Name), CacheW, CacheH);
    Small := ScaleIntfImage(Img, CacheW, CacheH);
    Img.Free;
    Emit(FPool.FEntries[EntryIdx].Name, Small, False,
      FPool.FRanks[EntryIdx]);
  end;
end;

{ TPagesThread }

{ Stores the single CBZ file whose pages should be loaded. }
constructor TPagesThread.Create(const AFile: string; AThreads: integer);
begin
  inherited Create;
  FFile := AFile;
  FThreads := AThreads;
end;

{ Opens the single archive and iterates over every page via ForEachImage
  (or ForEachCbrImage for RAR/CBR archives).  HandlePage receives each
  decoded page.  Pages are decoded at CacheW×CacheH (JPEG DCT scaling) so
  large archives load quickly. }
procedure TPagesThread.ProduceSequential;
begin
  if SameText(ExtractFileExt(FFile), CBR_EXT) then
    ForEachCbrImage(FFile, @HandlePage, CacheW, CacheH)
  else
    ForEachImage(FFile, @HandlePage, CacheW, CacheH);
end;

{ Byte-wise name comparison (Python sorted() order), independent of the
  locale collation used by TStringList.Sort.  (Local copy of the uzipeditor
  helper, which is not exported.) }
function ComparePageNames(List: TStringList; Index1, Index2: integer): integer;
begin
  Result := CompareStr(List[Index1], List[Index2]);
end;

{ Binary search for S in a CompareStr-sorted list.  Returns the rank or -1.
  (Local copy of the uzipeditor helper, which is not exported.) }
function PagesRank(List: TStringList; const S: string): integer;
var
  L, R, M, C: integer;
begin
  L := 0;
  R := List.Count - 1;
  while L <= R do
  begin
    M := (L + R) div 2;
    C := CompareStr(S, List[M]);
    if C = 0 then Exit(M);
    if C > 0 then
      L := M + 1
    else
      R := M - 1;
  end;
  Result := -1;
end;

function TPagesThread.NextJob: integer;
begin
  Result := InterlockedIncrement(FJobCursor) - 1;
  if Result >= Length(FJobs) then
    Result := -1;
end;

procedure TPagesThread.ProduceParallel(AThreadCount: integer);
var
  i: integer;
  Names: TStringList;
begin
  { RAR archives (no central directory) are collected through libarchive;
    like the streaming path this raises when libarchive is missing or the
    archive is unreadable — TThumbThread.Execute logs it, so no pages load. }
  if SameText(ExtractFileExt(FFile), CBR_EXT) then
    FEntries := CollectCbrEntries(FFile)
  else
    FEntries := CollectZipEntries(FFile);
  try
    FJobs := nil;
    for i := 0 to High(FEntries) do
      if IsImageExt(ExtractFileExt(FEntries[i].Name)) then
      begin
        SetLength(FJobs, Length(FJobs) + 1);
        FJobs[High(FJobs)] := i;
      end;
    if Length(FJobs) = 0 then Exit;

    { Alphabetical ranks (CompareStr order, like the streaming walker's
      SortedRank): the sorted insertion in SyncAddThumbs displays pages in
      reading order even when the archive stores them scrambled. }
    Names := TStringList.Create;
    try
      for i := 0 to High(FJobs) do
        Names.Add(FEntries[FJobs[i]].Name);
      Names.CustomSort(@ComparePageNames);
      SetLength(FRanks, Length(FEntries));
      for i := 0 to High(FRanks) do
        FRanks[i] := -1;
      for i := 0 to High(FJobs) do
        FRanks[FJobs[i]] := PagesRank(Names, FEntries[FJobs[i]].Name);
    finally
      Names.Free;
    end;

    FJobCursor := 0;
    FFinished := 0;
    SetLength(FWorkers, Min(AThreadCount, Length(FJobs)));
    for i := 0 to High(FWorkers) do
    begin
      FWorkers[i] := TPagesWorker.Create(Self);
      FWorkers[i].ListView := FListView;
      FWorkers[i].Pages := FPages;
      FWorkers[i].Images := FImages;
      FWorkers[i].OnBatchAdded := FOnBatchAdded;
      FWorkers[i].OwnerEpoch := FOwnerEpoch;
      FWorkers[i].FreeOnTerminate := True;
    end;
    for i := 0 to High(FWorkers) do
      if FWorkers[i] <> nil then
        FWorkers[i].Start;

    { Wait for every worker; on cancellation terminate them so their
      pending batches are discarded and they exit promptly.  Workers read
      the shared entries at the end of each iteration, after the decode,
      so Produce must not return — and the coordinator must not free
      FEntries — until every worker has really finished. }
    while FFinished < Length(FWorkers) do
    begin
      if Terminated then
      begin
        for i := 0 to High(FWorkers) do
          if FWorkers[i] <> nil then
            FWorkers[i].Terminate;
        while FFinished < Length(FWorkers) do
          Sleep(5);
        Break;
      end;
      Sleep(5);
    end;
  finally
    { The entries stay alive until every worker finished (see above). }
    FreeZipEntries(FEntries);
    FEntries := nil;
    FWorkers := nil;
  end;
end;

procedure TPagesThread.Produce;
var
  ThreadCount: integer;
begin
  Log('Pages: opening %s', [ExtractFileName(FFile)]);
  ThreadCount := FThreads;
  if ThreadCount <= 0 then
    ThreadCount := WorkerCount;
  if ThreadCount <= 1 then
    ProduceSequential
  else
    ProduceParallel(ThreadCount);
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
