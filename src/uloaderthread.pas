unit uloaderthread;

{
  Decodifica in background con pubblicazione a lotti sul thread principale.

  TThumbThread e' la base comune: i discendenti implementano Produce e per
  ogni immagine pronta chiamano Emit; la base accumula, pubblica tramite Queue
  e riempie ListView + ImageList. Tutte le immagini vengono ridotte a CacheW x
  CacheH prima di essere conservate, cosi' lo zoom non deve rileggere gli
  archivi e l'occupazione di memoria resta limitata anche con centinaia di
  pagine.

  Pubblicazione lotti
  -------------------
  A differenza di Synchronize, Queue non blocca il thread secondario:
  il worker produce al massimo della velocita' mentre il main thread consuma
  i lotti quando ha tempo.  La proprieta' delle immagini viene trasferita
  dal worker al main thread tramite il campo FPendingBatch: il worker scrive
  FPendingBatch + FPendingCount e subito dopo chiama Queue(@SyncAddThumbs);
  SyncAddThumbs (eseguito sul main thread) consuma il lotto e azzera i campi.
  Il worker non libera mai FPendingBatch nel finally di Execute perche'
  SyncAddThumbs viene sempre processato prima di OnTerminate (stessa coda
  FIFO gestita da CheckSynchronize).

  Se il thread viene terminato mentre un lotto e' ancora in coda,
  SyncAddThumbs controlla Terminated e chiama FreePendingBatch per
  evitare memory leak.

  Se per qualche motivo il worker producesse piu' velocemente di quanto
  il main thread riesca a consumare, Flush attende brevemente con Sleep(1)
  prima di sovrascrivere FPendingBatch.  In pratica questo non accade mai
  perche' la decodifica delle immagini (I/O disco + decompressione) e'
  lenta rispetto all'aggiunta di poche voci alla ListView.
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
    { Eseguita nel thread secondario: produce le immagini chiamando Emit e
      deve rientrare non appena Terminated diventa True. }
    procedure Produce; virtual; abstract;
    { Accoda un'immagine (anche nil) al lotto corrente; ne cede la proprieta'. }
    procedure Emit(const AName: string; AImage: TLazIntfImage;
      AHasComicInfo: boolean = False);
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
  end;

  { TLoadThread: prime pagine di tutti i .cbz di una cartella }

  TLoadThread = class(TThumbThread)
  private
    FDir: string;
  protected
    procedure Produce; override;
  public
    { Constructs the thread in a suspended state; the caller must set
      ListView, Pages, and Images before calling Start. }
    constructor Create(const ADir: string);
  end;

  { TPagesThread: tutte le pagine di un singolo .cbz }

  TPagesThread = class(TThumbThread)
  private
    FFile: string;
    procedure HandlePage(const AName: string; AImage: TLazIntfImage;
      var ACancel: boolean);
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
  uservicemerge;

const
  BatchSize = 4;

  { ComicInfo badge painted in the top-right corner of a thumbnail:
    a filled circle BADGE_SIZE pixels across, inset BADGE_MARGIN from
    the top and right edges. }
  BADGE_SIZE   = 12;
  BADGE_MARGIN = 2;

  { TThumbThread }

constructor TThumbThread.Create;
begin
  inherited Create(True);
  FBatchCount := 0;
  SetLength(FBatch, 0);
  FPendingCount := 0;
  SetLength(FPendingBatch, 0);
end;

procedure TThumbThread.Execute;
begin
  try
    try
      Produce;
      if not Terminated then
        Flush;
      Log('Thread: terminato regolarmente');
    except
      on E: Exception do
        Log('Thread: ECCEZIONE NON GESTITA %s: %s', [E.ClassName, E.Message]);
    end;
  finally
    { Lotto corrente mai pubblicato (interruzione o eccezione): evita il leak.
      FPendingBatch NON va liberato qui: e' di proprieta' del main thread e
      SyncAddThumbs lo processera' prima che il thread venga distrutto. }
    FreeBatch;
  end;
end;

procedure TThumbThread.Emit(const AName: string; AImage: TLazIntfImage;
  AHasComicInfo: boolean);
begin
  Inc(FBatchCount);
  SetLength(FBatch, FBatchCount);
  FBatch[FBatchCount - 1].Name := AName;
  FBatch[FBatchCount - 1].Image := AImage;
  FBatch[FBatchCount - 1].HasComicInfo := AHasComicInfo;
  if FBatchCount >= BatchSize then
    Flush;
end;

procedure TThumbThread.Flush;
begin
  if FBatchCount = 0 then Exit;
  { Attende che il main thread abbia consumato il lotto precedente
    (in pratica non serve mai perche' la decodifica e' lenta). }
  while FPendingCount > 0 do
    Sleep(1);
  { Trasferisce la proprieta' al main thread. }
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
  i, ILIdx: integer;
  Thumb: TBitmap;
  It: TListItem;
begin
  if Terminated then
  begin
    { nessuno prendera' in carico le immagini del lotto }
    FreePendingBatch;
    Exit;
  end;

  FListView.BeginUpdate;
  try
    for i := 0 to FPendingCount - 1 do
    begin
      FPages.Add(FPendingBatch[i].Image);
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
      It := FListView.Items.Add;
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
  Log('Sync: %d voci, ImageList=%d', [FListView.Items.Count, FImages.Count]);
end;

{ TLoadThread }

{ Constructs the thread in a suspended state; the caller must set
  ListView, Pages, and Images before calling Start. }
constructor TLoadThread.Create(const ADir: string);
begin
  inherited Create;
  FDir := ADir;
end;

{ Iterates over every .cbz file in FDir in sorted order, extracts the
  first image of each via GetFirstImageAsIntfImage, scales it to
  CacheW×CacheH, and emits the thumbnail.  Respects Terminated. }
procedure TLoadThread.Produce;
var
  Dir, FilePath: string;
  FileList: TStringArray;
  Names: TStringList;
  i: integer;
  Img, Small: TLazIntfImage;
begin
  Dir := IncludeTrailingPathDelimiter(FDir);
  FileList := CollectCBZFiles(FDir);
  Names := TStringList.Create;
  try
    for i := 0 to High(FileList) do
      Names.Add(FileList[i]);
    Names.Sort;
    Log('Thread: %d file .cbz trovati in %s', [Names.Count, Dir]);

    for i := 0 to Names.Count - 1 do
    begin
      if Terminated then Exit;

      FilePath := Dir + Names[i];
      Img := nil;
      try
        Img := GetFirstImageAsIntfImage(FilePath);
      except
        on E: Exception do
        begin
          Log('Thread: eccezione su %s: %s: %s',
            [Names[i], E.ClassName, E.Message]);
          Img := nil;
        end;
      end;

      Small := ScaleIntfImage(Img, CacheW, CacheH);
      Img.Free;
      Emit(Names[i], Small, HasComicInfoFast(FilePath));
    end;
  finally
    Names.Free;
  end;
end;

{ TPagesThread }

{ Stores the single CBZ file whose pages should be loaded. }
constructor TPagesThread.Create(const AFile: string);
begin
  inherited Create;
  FFile := AFile;
end;

{ Opens the single CBZ file and iterates over every page via
  ForEachImage.  HandlePage receives each decoded page. }
procedure TPagesThread.Produce;
begin
  Log('Pages: apertura %s', [ExtractFileName(FFile)]);
  ForEachImage(FFile, @HandlePage);
end;

{ ForEachImage callback: scales the decoded full-size image to the
  thumbnail cache dimensions (CacheW×CacheH), emits the result, and
  respects Terminated to abort early. }
procedure TPagesThread.HandlePage(const AName: string; AImage: TLazIntfImage;
  var ACancel: boolean);
var
  Small: TLazIntfImage;
begin
  Small := ScaleIntfImage(AImage, CacheW, CacheH);
  AImage.Free;
  Emit(AName, Small);
  ACancel := Terminated;
end;

end.
