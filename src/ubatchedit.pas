unit ubatchedit;

{$mode ObjFPC}{$H+}

{
  Batch page edit: applies one uniform edit (percent resize, colour
  adjustments and/or parallel split lines) to a set of pages of the open
  CBZ.  Pure pipeline, no GUI: main.pas snapshots page descriptors, runs
  the worker, and stages the results into the page-editing model.

  Pipeline per page (entirely in RAM):
    decode current state (the page's Data stream when it was already
    edited, otherwise the archive entry) -> optional percent resize ->
    optional colour adjust -> optional split into N+1 pieces -> encode
    every piece in the page's original format (EncodeExtFor).  A thumbnail
    per piece is produced for the preview cache.

  The worker is sequential (one full-resolution image in RAM at a time,
  like TSaveChangesThread) and reports progress to the main thread via
  TThread.Queue.
}

interface

uses
  Classes, SysUtils, IntfGraphics, Math,
  uimageedit, uimgutil, uzipeditor, upageeditmodel, uservicebase;

type
  { Uniform edit parameters for a batch run.  Neutral = no change. }
  TMultiEditParams = record
    Resize: boolean;        { apply Percent }
    Percent: integer;       { 50..200, 100 = unchanged }
    Adj: TColorAdjust;      { NeutralColorAdjust = no colour change }
    Split: boolean;         { apply Lines }
    Horizontal: boolean;    { True = horizontal cut lines (top/bottom) }
    Lines: array of double; { normalized 0..1, sorted ascending }
  end;

  { One encoded piece of one page.  Stream + Thumb are owned by the worker
    result and transferred to the caller. }
  TMultiEditPiece = record
    Stream: TMemoryStream;
    Ext: string;
    Thumb: TLazIntfImage;
  end;

  { Result for one source page: one piece when no split, N+1 when split. }
  TMultiEditPageResult = record
    Idx: integer;                       { model index of the source page }
    Pieces: array of TMultiEditPiece;
  end;

  { Input descriptor for one page: decode from Data when present, else from
    the archive entry OrigName of APageFile. }
  TMultiEditPageInput = record
    Idx: integer;
    OrigName: string;   { archive entry name (may be '' when Data is set) }
    Data: TMemoryStream; { current edited bytes (may be nil) }
    Ext: string;        { current extension, decides the output format }
  end;

  TMultiEditPageInputs = array of TMultiEditPageInput;
  TMultiEditPageResults = array of TMultiEditPageResult;
  TMultiEditPieces = array of TMultiEditPiece;

{ True when AParams changes nothing (no resize, neutral colours, no split
  lines). }
function ParamsAreNeutral(const AParams: TMultiEditParams): boolean;

{ True when AAdj leaves the pixels unchanged. }
function ColorAdjustIsNeutral(const AAdj: TColorAdjust): boolean;

{ Frees every piece (stream + thumb) of AResults and resets the arrays. }
procedure FreeMultiEditResults(var AResults: TMultiEditPageResults);

{ Applies the whole pipeline to one decoded image and produces the encoded
  piece(s) in reading order.  APieces is filled with owned results; the
  caller frees them via FreeMultiEditResults (or transfers them out).
  Returns False when the input could not be transformed — APieces is then
  left empty (partial results are freed).  Callable from any thread. }
function ApplyMultiEditToImage(Src: TLazIntfImage;
  const AParams: TMultiEditParams; const AExt: string;
  AThumbW, AThumbH: integer; out APieces: TMultiEditPieces): boolean;

{ Stages the worker results into the page-editing model: piece 0 replaces
  the source page in place (ckEdited), extra split pieces are inserted
  right after it (PageInsertAt) with OrigName = '' so they can never match
  an archive entry.  Iterates in descending source-index order so the
  insertions never shift pending indices.  Ownership: the streams become
  the pages' Data and are cleared from AResults; every new thumbnail is
  handed back through ANewThumbs (the caller's preview cache owns them).
  Returns the number of pieces staged (skips pages without results). }
function StageMultiEditResults(var APages: TPageStates;
  var AChanges: TChanges; const AResults: TMultiEditPageResults;
  out AHadSplit: boolean; out ANewThumbs: TIntfImageArray): integer;

{ Background worker: processes the page list entirely in RAM and reports
  progress (0..100) through AOnProgress on the main thread.  Created
  suspended; FreeOnTerminate = True (mirrors TServiceThread).  Read
  Results after termination.

  AThreads selects the pool size: 0 = automatic (CPU count, capped at
  MAX_MULTIEDIT_THREADS — every worker holds a full-resolution image
  plus its split pieces in RAM); 1 = sequential (the historical
  behaviour, one full-resolution image at a time).  Results are
  deterministic regardless of the thread count: each input index is
  claimed exactly once and written into its own result slot. }
type
  TMultiEditWorker = class(TThread)
  private
    FPageFile: string;
    FInputs: TMultiEditPageInputs;
    FParams: TMultiEditParams;
    FThumbW, FThumbH: integer;
    FOnProgress: TServiceProgressEvent;
    FThreads: integer;
    FPendingPct: integer;
    FPendingMsg: string;
    FResults: TMultiEditPageResults;
    procedure DoProgress(APercent: integer; const AMsg: string);
    procedure SyncProgress;
  protected
    procedure Execute; override;
  public
    constructor Create(const APageFile: string;
      const AInputs: TMultiEditPageInputs; const AParams: TMultiEditParams;
      AThumbW, AThumbH: integer; AOnProgress: TServiceProgressEvent;
      AThreads: integer = 0);
    destructor Destroy; override;
    { Owned results, indexed like AInputs (pages that could not be decoded
      keep an empty Pieces array).  Read after termination. }
    property Results: TMultiEditPageResults read FResults;
  end;

implementation

uses
  uLog;

{ ---------------------------------------------------------------------------
  Neutrality checks
  --------------------------------------------------------------------------- }

function ColorAdjustIsNeutral(const AAdj: TColorAdjust): boolean;
begin
  Result := (AAdj.Invert = False) and (AAdj.Grayscale = False) and
    (AAdj.Sepia = False) and (AAdj.RGain = 1.0) and (AAdj.GGain = 1.0) and
    (AAdj.BGain = 1.0) and (AAdj.Saturation = 1.0) and
    (AAdj.Contrast = 1.0) and (AAdj.Brightness = 0.0) and
    (AAdj.Gamma = 1.0);
end;

function ParamsAreNeutral(const AParams: TMultiEditParams): boolean;
begin
  Result := (not AParams.Resize or (AParams.Percent = 100)) and
    (not AParams.Split or (Length(AParams.Lines) = 0)) and
    ColorAdjustIsNeutral(AParams.Adj);
end;

{ ---------------------------------------------------------------------------
  Result helpers
  --------------------------------------------------------------------------- }

procedure FreeMultiEditResults(var AResults: TMultiEditPageResults);
var
  i, j: integer;
begin
  for i := 0 to High(AResults) do
    for j := 0 to High(AResults[i].Pieces) do
    begin
      AResults[i].Pieces[j].Stream.Free;
      AResults[i].Pieces[j].Thumb.Free;
      AResults[i].Pieces[j].Stream := nil;
      AResults[i].Pieces[j].Thumb := nil;
    end;
  AResults := nil;
end;

{ Frees the pieces of a single open-array (used on partial failures). }
procedure FreePieces(APieces: array of TMultiEditPiece);
var
  i: integer;
begin
  for i := 0 to High(APieces) do
  begin
    APieces[i].Stream.Free;
    APieces[i].Thumb.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Pipeline
  --------------------------------------------------------------------------- }

function ApplyMultiEditToImage(Src: TLazIntfImage;
  const AParams: TMultiEditParams; const AExt: string;
  AThumbW, AThumbH: integer; out APieces: TMultiEditPieces): boolean;
var
  Cur, Res: TLazIntfImage;
  Slices: TIntfImageArray;
  i: integer;
  AllOk: boolean;
begin
  Result := False;
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  Cur := Src;
  try
    if AParams.Resize and (AParams.Percent <> 100) then
    begin
      Res := ResampleIntfImage(Cur,
        Max(1, Round(Cur.Width * AParams.Percent / 100)),
        Max(1, Round(Cur.Height * AParams.Percent / 100)));
      if Res = nil then Exit;
      if Cur <> Src then Cur.Free;
      Cur := Res;
    end;

    if not ColorAdjustIsNeutral(AParams.Adj) then
    begin
      Res := AdjustColors(Cur, AParams.Adj);
      if Res = nil then Exit;
      if Cur <> Src then Cur.Free;
      Cur := Res;
    end;

    if AParams.Split and (Length(AParams.Lines) > 0) then
    begin
      Slices := SplitIntfImage(Cur, AParams.Horizontal, AParams.Lines);
      if Length(Slices) = 0 then Exit;
      if Cur <> Src then Cur.Free;
      Cur := nil;  { the pieces replace it }
      SetLength(APieces, Length(Slices));
      AllOk := True;
      for i := 0 to High(Slices) do
      begin
        APieces[i].Ext := EncodeExtFor(AExt);
        APieces[i].Stream := EncodeIntfImage(Slices[i], APieces[i].Ext);
        if APieces[i].Stream = nil then
        begin
          AllOk := False;
          Break;
        end;
        APieces[i].Thumb := ScaleIntfImage(Slices[i], AThumbW, AThumbH);
      end;
      FreeImageArray(Slices);
      if not AllOk then
      begin
        FreePieces(APieces);
        SetLength(APieces, 0);
        Exit;
      end;
      Result := True;
      Exit;
    end;

    { No split: a single piece. }
    SetLength(APieces, 1);
    APieces[0].Ext := EncodeExtFor(AExt);
    APieces[0].Stream := EncodeIntfImage(Cur, APieces[0].Ext);
    if APieces[0].Stream = nil then
    begin
      SetLength(APieces, 0);
      Exit;
    end;
    APieces[0].Thumb := ScaleIntfImage(Cur, AThumbW, AThumbH);
    Result := True;
  finally
    if Cur <> Src then
      Cur.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Staging into the page-editing model
  --------------------------------------------------------------------------- }

function StageMultiEditResults(var APages: TPageStates;
  var AChanges: TChanges; const AResults: TMultiEditPageResults;
  out AHadSplit: boolean; out ANewThumbs: TIntfImageArray): integer;
var
  i, j, n: integer;
  NewPage: TPageState;
  PageName: string;
  Piece: TMultiEditPiece;
begin
  Result := 0;
  AHadSplit := False;
  ANewThumbs := nil;
  n := 0;
  for i := High(AResults) downto 0 do
  begin
    if Length(AResults[i].Pieces) = 0 then Continue;  { undecodable page }
    if Length(AResults[i].Pieces) > 1 then AHadSplit := True;
    for j := 0 to High(AResults[i].Pieces) do
    begin
      Piece := AResults[i].Pieces[j];
      if j = 0 then
      begin
        { Replace the page in place. }
        FreeAndNil(APages[AResults[i].Idx].Data);
        APages[AResults[i].Idx].Data := Piece.Stream;
        AResults[i].Pieces[j].Stream := nil;
        if not SameText(ExtractFileExt(APages[AResults[i].Idx].Name),
          Piece.Ext) then
          APages[AResults[i].Idx].Name :=
            ChangeFileExt(APages[AResults[i].Idx].Name, Piece.Ext);
        if Piece.Thumb <> nil then
        begin
          APages[AResults[i].Idx].Image := Piece.Thumb;
          AResults[i].Pieces[j].Thumb := nil;
          SetLength(ANewThumbs, n + 1);
          ANewThumbs[n] := Piece.Thumb;
          Inc(n);
        end;
        AppendChange(AChanges, ckEdited, APages[AResults[i].Idx].Name);
      end
      else
      begin
        { Extra split piece: a new page inserted after the source. }
        PageName := Format('split%d%s', [j, Piece.Ext]);
        NewPage.Name := PageName;
        NewPage.OrigName := PageName;
        NewPage.OrigIndex := -1;
        NewPage.Gone := False;
        NewPage.Data := Piece.Stream;
        AResults[i].Pieces[j].Stream := nil;
        NewPage.Image := Piece.Thumb;
        if NewPage.Image <> nil then
        begin
          AResults[i].Pieces[j].Thumb := nil;
          SetLength(ANewThumbs, n + 1);
          ANewThumbs[n] := NewPage.Image;
          Inc(n);
        end;
        PageInsertAt(APages, AChanges, AResults[i].Idx + j, NewPage);
        AppendChange(AChanges, ckEdited, NewPage.Name);
      end;
      Inc(Result);
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  Worker
  --------------------------------------------------------------------------- }

type
  { Shared state of a batch-edit pool: the input list, the per-input
    result slots and the claim counter.  Mutable fields are guarded by
    Lock; each worker writes only Results[Idx] with the Idx it claimed,
    so slot writes need no lock.  The first worker exception is recorded
    in Error and stops further claiming, so a failure aborts the batch
    exactly like the sequential path's exception propagation. }
  TMultiEditPoolState = class
    Lock: TRTLCriticalSection;
    PageFile: string;
    Inputs: TMultiEditPageInputs;
    Params: TMultiEditParams;
    ThumbW, ThumbH: integer;
    Results: TMultiEditPageResults;
    Next: integer;             { next input index (under Lock) }
    Completed: integer;        { finished inputs (under Lock) }
    Total: integer;
    OnProgress: TServiceProgressEvent;
    Error: string;             { first worker exception (under Lock) }
    constructor Create;
    destructor Destroy; override;
  end;

  { Pool worker: claims the next input index under the lock, runs the
    decode → transform → encode pipeline for that page into its own
    result slot, then reports progress — serialized and monotonic via
    the completed counter (the Queue call happens while holding the
    lock so delivery order matches completion order). }
  TMultiEditPageWorker = class(TThread)
  private
    FPool: TMultiEditPoolState;
    FPendingPct: integer;
    FPendingMsg: string;
    procedure SyncProgress;
    { No-op drained on the main thread: the coordinator calls it via a
      blocking Synchronize after the join, which — the global sync queue
      being FIFO — guarantees every SyncProgress queued by this worker
      has already run.  Only then may the worker be freed; otherwise a
      still-queued SyncProgress would run on a freed object (the same
      use-after-free the TServiceThread header comment describes). }
    procedure Drained;
  protected
    procedure Execute; override;
  public
    constructor Create(APool: TMultiEditPoolState);
  end;

constructor TMultiEditPoolState.Create;
begin
  inherited Create;
  InitCriticalSection(Lock);
end;

destructor TMultiEditPoolState.Destroy;
begin
  DoneCriticalSection(Lock);
  inherited Destroy;
end;

constructor TMultiEditPageWorker.Create(APool: TMultiEditPoolState);
begin
  { Created suspended: the coordinator Start()s every worker before joining.
    FreeOnTerminate stays False — the coordinator frees the workers after
    the join. }
  inherited Create(True);
  FPool := APool;
end;

procedure TMultiEditPageWorker.SyncProgress;
begin
  if Assigned(FPool.OnProgress) then
    FPool.OnProgress(FPendingPct, FPendingMsg);
end;

procedure TMultiEditPageWorker.Drained;
begin
end;

procedure TMultiEditPageWorker.Execute;
var
  Idx, Pct: integer;
  Img: TLazIntfImage;
begin
  while True do
  begin
    if Terminated then Exit;
    EnterCriticalSection(FPool.Lock);
    try
      if (FPool.Error <> '') or (FPool.Next >= Length(FPool.Inputs)) then Exit;
      Idx := FPool.Next;
      Inc(FPool.Next);
    finally
      LeaveCriticalSection(FPool.Lock);
    end;

    try
      FPool.Results[Idx].Idx := FPool.Inputs[Idx].Idx;
      Img := nil;
      if FPool.Inputs[Idx].Data <> nil then
        Img := DecodeImage(FPool.Inputs[Idx].Data, FPool.Inputs[Idx].Ext)
      else if FPool.Inputs[Idx].OrigName <> '' then
        Img := GetImageAsIntfImage(FPool.PageFile, FPool.Inputs[Idx].OrigName);
      if Img = nil then
        Log('BatchEdit: cannot decode page "%s" (%s) — skipped',
          [FPool.Inputs[Idx].OrigName, FPool.Inputs[Idx].Ext])
      else
      try
        ApplyMultiEditToImage(Img, FPool.Params, FPool.Inputs[Idx].Ext,
          FPool.ThumbW, FPool.ThumbH, FPool.Results[Idx].Pieces);
      finally
        Img.Free;
      end;
      Log('BatchEdit: page %d -> %d piece(s)',
        [FPool.Inputs[Idx].Idx, Length(FPool.Results[Idx].Pieces)]);
    except
      on E: Exception do
      begin
        EnterCriticalSection(FPool.Lock);
        try
          if FPool.Error = '' then
            FPool.Error := E.Message;
        finally
          LeaveCriticalSection(FPool.Lock);
        end;
        Exit;
      end;
    end;

    EnterCriticalSection(FPool.Lock);
    try
      Inc(FPool.Completed);
      Pct := (FPool.Completed * 100) div FPool.Total;
      FPendingPct := Pct;
      FPendingMsg := Format('Editing page %d of %d',
        [FPool.Completed, FPool.Total]);
      if Assigned(FPool.OnProgress) then
        TThread.Queue(nil, @SyncProgress);
    finally
      LeaveCriticalSection(FPool.Lock);
    end;
  end;
end;

constructor TMultiEditWorker.Create(const APageFile: string;
  const AInputs: TMultiEditPageInputs; const AParams: TMultiEditParams;
  AThumbW, AThumbH: integer; AOnProgress: TServiceProgressEvent;
  AThreads: integer);
begin
  inherited Create(True);  { Start suspended — caller must call Start }
  FreeOnTerminate := True; { auto-free after Execute finishes }
  FPageFile := APageFile;
  FInputs := AInputs;
  FParams := AParams;
  FThumbW := AThumbW;
  FThumbH := AThumbH;
  FOnProgress := AOnProgress;
  FThreads := AThreads;
end;

{ Frees any pieces that were never transferred to the caller (the staging
  pass nils the streams/thumbs it takes over). }
destructor TMultiEditWorker.Destroy;
var
  i, j: integer;
begin
  for i := 0 to High(FResults) do
    for j := 0 to High(FResults[i].Pieces) do
    begin
      FResults[i].Pieces[j].Stream.Free;
      FResults[i].Pieces[j].Thumb.Free;
    end;
  inherited Destroy;
end;

procedure TMultiEditWorker.DoProgress(APercent: integer; const AMsg: string);
begin
  FPendingPct := APercent;
  FPendingMsg := AMsg;
  if Assigned(FOnProgress) then
    TThread.Queue(nil, @SyncProgress);
end;

procedure TMultiEditWorker.SyncProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(FPendingPct, FPendingMsg);
end;

procedure TMultiEditWorker.Execute;
var
  i, ThreadCount, Total, W: integer;
  Img: TLazIntfImage;
  Pool: TMultiEditPoolState;
  Workers: array of TMultiEditPageWorker;
  AllDone: boolean;
begin
  { Exceptions propagate to TThread.Run, which stores them in FatalException
    for the OnTerminate handler (ServiceThreadFailed). }
  SetLength(FResults, Length(FInputs));
  DoProgress(0, Format('Batch editing %d page(s)...', [Length(FInputs)]));
  if Length(FInputs) = 0 then
  begin
    DoProgress(100, 'Batch edit complete');
    Exit;
  end;

  ThreadCount := FThreads;
  if ThreadCount <= 0 then
    ThreadCount := Min(OnlineCpuCount, MAX_MULTIEDIT_THREADS);
  ThreadCount := Min(ThreadCount, Length(FInputs));

  if ThreadCount <= 1 then
  begin
    { Sequential: exactly the historical behaviour (one full-resolution
      image in RAM at a time). }
    Total := 0;
    for i := 0 to High(FInputs) do
    begin
      if Terminated then Break;
      DoProgress((i * 100) div Length(FInputs),
        Format('Editing page %d of %d', [i + 1, Length(FInputs)]));
      FResults[i].Idx := FInputs[i].Idx;

      Img := nil;
      if FInputs[i].Data <> nil then
        Img := DecodeImage(FInputs[i].Data, FInputs[i].Ext)
      else if FInputs[i].OrigName <> '' then
        Img := GetImageAsIntfImage(FPageFile, FInputs[i].OrigName);
      if Img = nil then
      begin
        Log('BatchEdit: cannot decode page "%s" (%s) — skipped',
          [FInputs[i].OrigName, FInputs[i].Ext]);
        Continue;
      end;
      try
        ApplyMultiEditToImage(Img, FParams, FInputs[i].Ext,
          FThumbW, FThumbH, FResults[i].Pieces);
      finally
        Img.Free;
      end;
      Inc(Total, Length(FResults[i].Pieces));
      Log('BatchEdit: page %d -> %d piece(s)',
        [FInputs[i].Idx, Length(FResults[i].Pieces)]);
    end;
  end
  else
  begin
    { Parallel: a pool of page workers claims input indices and writes
      each result into its own slot, so the output is identical for any
      thread count. }
    Pool := TMultiEditPoolState.Create;
    Workers := nil;
    try
      Pool.PageFile := FPageFile;
      Pool.Inputs := FInputs;
      Pool.Params := FParams;
      Pool.ThumbW := FThumbW;
      Pool.ThumbH := FThumbH;
      Pool.Results := FResults;
      Pool.Total := Length(FInputs);
      Pool.OnProgress := FOnProgress;
      SetLength(Workers, ThreadCount);
      for i := 0 to ThreadCount - 1 do
        Workers[i] := nil;
      try
        for i := 0 to ThreadCount - 1 do
          Workers[i] := TMultiEditPageWorker.Create(Pool);
        for i := 0 to ThreadCount - 1 do
          Workers[i].Start;
        { Join with cancel propagation: terminating the coordinator
          terminates the page workers so they exit at the next claim. }
        while True do
        begin
          AllDone := True;
          for W := 0 to High(Workers) do
            if (Workers[W] <> nil) and not Workers[W].Finished then
            begin
              AllDone := False;
              Break;
            end;
          if AllDone then Break;
          if Terminated then
            for W := 0 to High(Workers) do
              if Workers[W] <> nil then
                Workers[W].Terminate;
          Sleep(5);
        end;
        for i := 0 to High(Workers) do
          if Workers[i] <> nil then
            Workers[i].WaitFor;
        { Barrier before freeing: a blocking Synchronize queued behind a
          worker's SyncProgress calls only returns once they have all run
          on the main thread, so no queued method can outlive its worker.
          Skipped when no progress callback exists (nothing was queued —
          this also keeps callback-less callers, like the unit tests
          driving the worker from the main thread, deadlock-free). }
        if Assigned(Pool.OnProgress) then
          for i := 0 to High(Workers) do
            if Workers[i] <> nil then
              Workers[i].Synchronize(@Workers[i].Drained);
      finally
        for i := 0 to High(Workers) do
          Workers[i].Free;
      end;
      { A worker failure fails the whole batch, exactly like the
        sequential path's exception propagation. }
      if Pool.Error <> '' then
        raise Exception.Create(Pool.Error);
    finally
      Pool.Free;
    end;
    Total := 0;
    for i := 0 to High(FResults) do
      Inc(Total, Length(FResults[i].Pieces));
  end;
  if Terminated then
    DoProgress(0, 'Batch edit cancelled')
  else
    DoProgress(100, 'Batch edit complete');
  Log('BatchEdit: finished — %d page(s) processed, %d piece(s) produced',
    [Length(FInputs), Total]);
end;

end.
