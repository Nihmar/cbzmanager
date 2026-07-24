unit uloaderthread;

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

type   
  TLazIntfImageList = specialize TObjectList<TLazIntfImage>;

  TLoadedItem = record
    Name: string;
    Image: TLazIntfImage;
  end;
  TLoadedItems = array of TLoadedItem;

  { TLoadThread }

  TLoadThread = class(TThread)
  private
    FAForm: TForm;
    FDir: string;
    FFileNames: TStringList;
    FImages: TImageList;
    FItems: TLoadedItems;
    FCount: integer;
    FListView: TListView;
    FPages: specialize TObjectList<TLazIntfImage>;
    procedure SetImages(AValue: TImageList);
    procedure SetListView(AValue: TListView);
    procedure SetPages(AValue: TLazIntfImageList);
    procedure SyncAddThumbs;
  protected
    procedure Execute; override;
  public
    constructor Create(const ADir: string);
    destructor Destroy; override;
    property ListView: TListView read FListView write SetListView;
    property Pages: TLazIntfImageList read FPages write SetPages;
    property Images: TImageList read FImages write SetImages;
  end;

implementation

uses
  uLog,
  uimgutil,
  uzipeditor;

  { TLoadThread }

constructor TLoadThread.Create(const ADir: string);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FDir := ADir;
  FFileNames := TStringList.Create;
  FCount := 0;
  SetLength(FItems, 0);
end;

destructor TLoadThread.Destroy;
begin
  FFileNames.Free;
  inherited Destroy;
end;

procedure TLoadThread.Execute;
var
  Dir: string;
  SearchRec: TSearchRec;
  FileNames: TStringList;
  i, j: integer;
  FilePath: string;
  Img: TLazIntfImage;
  Batch: TLoadedItems;
  BatchCount: integer;
begin
  try
    Dir := IncludeTrailingPathDelimiter(FDir);

    FileNames := TStringList.Create;
    try
      if FindFirst(Dir + '*.cbz', faAnyFile, SearchRec) = 0 then
      begin
        repeat
          FileNames.Add(SearchRec.Name);
        until FindNext(SearchRec) <> 0;
        FindClose(SearchRec);
      end;
      FileNames.Sort;
      Log('Thread: %d file .cbz trovati in %s', [FileNames.Count, Dir]);

      BatchCount := 0;
      SetLength(Batch, 0);

      for i := 0 to FileNames.Count - 1 do
      begin
        if Terminated then Exit;

        FilePath := Dir + FileNames[i];
        Img := nil;
        try
          Img := GetFirstImageAsIntfImage(FilePath);
        except
          on E: Exception do
          begin
            Log('Thread: eccezione su %s: %s: %s',
              [FileNames[i], E.ClassName, E.Message]);
            Img := nil;
          end;
        end;

        Inc(BatchCount);
        SetLength(Batch, BatchCount);
        Batch[BatchCount - 1].Name := FileNames[i];
        Batch[BatchCount - 1].Image := Img;
        Log('Thread: %d/%d elaborato, batch=%d',
          [i + 1, FileNames.Count, BatchCount]);

        if BatchCount >= 4 then
        begin
          FItems := Batch;
          FCount := BatchCount;
          FFileNames.Clear;
          for j := 0 to BatchCount - 1 do
            FFileNames.Add(Batch[j].Name);
          Log('Thread: Synchronize batch di %d...', [FCount]);
          TThread.Synchronize(nil, @SyncAddThumbs);
          Log('Thread: Synchronize rientrato');
          BatchCount := 0;
          SetLength(Batch, 0);
        end;
      end;

      if BatchCount > 0 then
      begin
        FItems := Batch;
        FCount := BatchCount;
        FFileNames.Clear;
        for j := 0 to BatchCount - 1 do
          FFileNames.Add(Batch[j].Name);
        TThread.Synchronize(nil, @SyncAddThumbs);
      end;
    finally
      FileNames.Free;
    end;
    Log('Thread: terminato regolarmente');
  except
    on E: Exception do
      Log('Thread: ECCEZIONE NON GESTITA %s: %s', [E.ClassName, E.Message]);
  end;
end;

procedure TLoadThread.SetImages(AValue: TImageList);
begin
  if FImages = AValue then Exit;
  FImages := AValue;
end;

procedure TLoadThread.SetListView(AValue: TListView);
begin
  if FListView = AValue then Exit;
  FListView := AValue;
end;

procedure TLoadThread.SetPages(AValue: TLazIntfImageList);
begin
  if FPages = AValue then Exit;
  FPages := AValue;
end;

procedure TLoadThread.SyncAddThumbs;
var
  i, Idx, ILIdx: integer;
  Thumb: TBitmap;
  It: TListItem;
begin
  if Terminated then
  begin
    { nessuno prendera' in carico le immagini del batch: evita il leak }
    for i := 0 to FCount - 1 do
      FItems[i].Image.Free;
    Exit;
  end;
  ListView.BeginUpdate;
  try
    for i := 0 to FCount - 1 do
    begin
      Idx := Pages.Add(FItems[i].Image);   // originale, anche se nil
      Thumb := MakeThumb(FItems[i].Image, Images.Width, Images.Height);
      try
        ILIdx := Images.Add(Thumb, nil);
      finally
        Thumb.Free;
      end;
      It := ListView.Items.Add;
      It.Caption := FFileNames[i];
      It.ImageIndex := ILIdx;
      Log('Sync: %s img=%s listIdx=%d ilIdx=%d',
        [FFileNames[i], BoolToStr(FItems[i].Image <> nil, 'si', 'NO'),
        Idx, ILIdx]);
    end;
  finally
    ListView.EndUpdate;
  end;
  Log('Sync: ListView.Items.Count=%d ImageList.Count=%d',
    [ListView.Items.Count, Images.Count]);
end;

end.
