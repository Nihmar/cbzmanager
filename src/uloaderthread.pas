unit uloaderthread;

{
  Decodifica in background con pubblicazione a lotti sul thread principale.

  TThumbThread e' la base comune: i discendenti implementano Produce e per
  ogni immagine pronta chiamano Emit; la base accumula, sincronizza e riempie
  ListView + ImageList. Tutte le immagini vengono ridotte a CacheW x CacheH
  prima di essere conservate, cosi' lo zoom non deve rileggere gli archivi e
  l'occupazione di memoria resta limitata anche con centinaia di pagine.
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
  TLazIntfImageList = specialize TObjectList<TLazIntfImage>;

  TLoadedItem = record
    Name: string;
    Image: TLazIntfImage;
  end;
  TLoadedItems = array of TLoadedItem;

  { TThumbThread }

  TThumbThread = class(TThread)
  private
    FBatch: TLoadedItems;
    FBatchCount: integer;
    FImages: TImageList;
    FListView: TListView;
    FPages: TLazIntfImageList;
    procedure FreeBatch;
    procedure SyncAddThumbs;
  protected
    { Eseguita nel thread secondario: produce le immagini chiamando Emit e
      deve rientrare non appena Terminated diventa True. }
    procedure Produce; virtual; abstract;
    { Accoda un'immagine (anche nil) al lotto corrente; ne cede la proprieta'. }
    procedure Emit(const AName: string; AImage: TLazIntfImage);
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
  uzipeditor;

const
  BatchSize = 4;

  { TThumbThread }

constructor TThumbThread.Create;
begin
  inherited Create(True);
  FBatchCount := 0;
  SetLength(FBatch, 0);
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
    { lotto mai pubblicato (interruzione o eccezione): evita il leak }
    FreeBatch;
  end;
end;

procedure TThumbThread.Emit(const AName: string; AImage: TLazIntfImage);
begin
  Inc(FBatchCount);
  SetLength(FBatch, FBatchCount);
  FBatch[FBatchCount - 1].Name := AName;
  FBatch[FBatchCount - 1].Image := AImage;
  if FBatchCount >= BatchSize then
    Flush;
end;

procedure TThumbThread.Flush;
begin
  if FBatchCount = 0 then Exit;
  { SyncAddThumbs consuma il lotto oppure lo libera se siamo Terminated }
  TThread.Synchronize(nil, @SyncAddThumbs);
  FBatchCount := 0;
  SetLength(FBatch, 0);
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

procedure TThumbThread.SyncAddThumbs;
var
  i, ILIdx: integer;
  Thumb: TBitmap;
  It: TListItem;
begin
  if Terminated then
  begin
    { nessuno prendera' in carico le immagini del lotto }
    FreeBatch;
    Exit;
  end;

  FListView.BeginUpdate;
  try
    for i := 0 to FBatchCount - 1 do
    begin
      FPages.Add(FBatch[i].Image);
      Thumb := MakeThumb(FBatch[i].Image, FImages.Width, FImages.Height);
      try
        ILIdx := FImages.Add(Thumb, nil);
      finally
        Thumb.Free;
      end;
      It := FListView.Items.Add;
      It.Caption := FBatch[i].Name;
      It.ImageIndex := ILIdx;
    end;
  finally
    FListView.EndUpdate;
  end;
  Log('Sync: %d voci, ImageList=%d', [FListView.Items.Count, FImages.Count]);
end;

{ TLoadThread }

constructor TLoadThread.Create(const ADir: string);
begin
  inherited Create;
  FDir := ADir;
end;

procedure TLoadThread.Produce;
var
  Dir, FilePath: string;
  SearchRec: TSearchRec;
  Names: TStringList;
  i: integer;
  Img, Small: TLazIntfImage;
begin
  Dir := IncludeTrailingPathDelimiter(FDir);
  Names := TStringList.Create;
  try
    if FindFirst(Dir + '*.cbz', faAnyFile, SearchRec) = 0 then
    begin
      repeat
        Names.Add(SearchRec.Name);
      until FindNext(SearchRec) <> 0;
      FindClose(SearchRec);
    end;
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
      Emit(Names[i], Small);
    end;
  finally
    Names.Free;
  end;
end;

{ TPagesThread }

constructor TPagesThread.Create(const AFile: string);
begin
  inherited Create;
  FFile := AFile;
end;

procedure TPagesThread.Produce;
begin
  Log('Pages: apertura %s', [ExtractFileName(FFile)]);
  ForEachImage(FFile, @HandlePage);
end;

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
