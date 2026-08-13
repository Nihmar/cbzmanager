unit test_ubatchedit;

{$mode objfpc}{$H+}

{ Tests for the batch page-edit pipeline (ubatchedit.pas): parameter
  neutrality, the pure ApplyMultiEditToImage steps (percent resize, colour
  pipeline, split into N+1 pieces, extension mapping) and the background
  worker (archive decode, Data-stream precedence, per-page piece results). }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils, IntfGraphics,
  ubatchedit;

type
  TBatchEditTest = class(TTestCase)
  private
    FTempDir: string;
    function MakePNG(AW, AH: integer): TMemoryStream;
    function DecodeResult(const AStream: TMemoryStream): TLazIntfImage;
    procedure FreePieces(const APieces: array of ubatchedit.TMultiEditPiece);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Params_NeutralChecks;
    procedure Pipeline_PercentResize;
    procedure Pipeline_ColorGrayscale;
    procedure Pipeline_SplitOneLine;
    procedure Pipeline_Combined;
    procedure Pipeline_ExtMapping;
    procedure Worker_EditsAllPages;
    procedure Worker_DecodesDataOverArchive;
    procedure Worker_SplitsAllPages;
    procedure Staging_SingleSplit;
    procedure Staging_MultiPageDescending;
    procedure Staging_ReplaceOnly;
  end;

implementation

uses
  fpimage,
  fpreadpng,
  fpwritePNG,
  uimageedit,
  upageeditmodel,
  uzipeditor,
  FileUtil,
  test_helpers;

function TBatchEditTest.MakePNG(AW, AH: integer): TMemoryStream;
var
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  x, y: integer;
begin
  Img := TFPMemoryImage.Create(AW, AH);
  try
    for y := 0 to AH - 1 do
      for x := 0 to AW - 1 do
        Img.Colors[x, y] := FPColor(x * 100, y * 100, (x + y) * 50);
    Result := TMemoryStream.Create;
    Writer := TFPWriterPNG.Create;
    try
      Writer.ImageWrite(Result, Img);
    finally
      Writer.Free;
    end;
    Result.Position := 0;
  finally
    Img.Free;
  end;
end;

function TBatchEditTest.DecodeResult(const AStream: TMemoryStream): TLazIntfImage;
begin
  AStream.Position := 0;
  Result := DecodeImage(AStream, '.png');
end;

procedure TBatchEditTest.FreePieces(
  const APieces: array of ubatchedit.TMultiEditPiece);
var
  i: integer;
begin
  for i := 0 to High(APieces) do
  begin
    APieces[i].Stream.Free;
    APieces[i].Thumb.Free;
  end;
end;

procedure TBatchEditTest.SetUp;
begin
  FTempDir := CreateTempDir('cbzbe_');
end;

procedure TBatchEditTest.TearDown;
begin
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
end;

procedure TBatchEditTest.Params_NeutralChecks;
var
  P: TMultiEditParams;
  N: TColorAdjust;
begin
  P.Resize := False;
  P.Percent := 100;
  P.Adj := NeutralColorAdjust;
  P.Split := False;
  P.Horizontal := True;
  P.Lines := nil;
  AssertTrue('defaults are neutral', ParamsAreNeutral(P));

  P.Resize := True;
  P.Percent := 150;
  AssertFalse('resize active', ParamsAreNeutral(P));
  P.Resize := False;
  P.Percent := 100;

  P.Percent := 50;
  { Resize unchecked: a stray percent is ignored. }
  AssertTrue('percent alone stays neutral', ParamsAreNeutral(P));
  P.Resize := True;
  AssertFalse('resize + percent active', ParamsAreNeutral(P));
  P.Resize := False;
  P.Percent := 100;

  SetLength(P.Lines, 1);
  P.Lines[0] := 0.5;
  { Split unchecked: stray lines are ignored. }
  AssertTrue('lines alone stay neutral', ParamsAreNeutral(P));
  P.Split := True;
  AssertFalse('split active', ParamsAreNeutral(P));
  P.Split := False;
  P.Lines := nil;

  N := NeutralColorAdjust;
  AssertTrue('neutral adjust is neutral', ColorAdjustIsNeutral(N));
  N.Grayscale := True;
  AssertFalse('grayscale is not neutral', ColorAdjustIsNeutral(N));
  N := NeutralColorAdjust;
  N.Brightness := 5;
  AssertFalse('brightness is not neutral', ColorAdjustIsNeutral(N));
end;

procedure TBatchEditTest.Pipeline_PercentResize;
var
  Src: TMemoryStream;
  Img, OutImg: TLazIntfImage;
  P: TMultiEditParams;
  Pieces: TMultiEditPieces;
begin
  Src := MakePNG(100, 50);
  try
    Img := DecodeImage(Src, '.png');
    try
      P.Resize := True;
      P.Percent := 50;
      P.Adj := NeutralColorAdjust;
      P.Split := False;
      AssertTrue('apply ok', ApplyMultiEditToImage(Img, P, '.png', 96, 128,
        Pieces));
      AssertEquals('one piece', 1, Length(Pieces));
      try
        AssertEquals('ext kept', '.png', Pieces[0].Ext);
        AssertNotNull('thumbnail produced', Pieces[0].Thumb);
        OutImg := DecodeResult(Pieces[0].Stream);
        try
          AssertEquals('width halved', 50, OutImg.Width);
          AssertEquals('height halved', 25, OutImg.Height);
        finally
          OutImg.Free;
        end;
      finally
        FreePieces(Pieces);
      end;
    finally
      Img.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TBatchEditTest.Pipeline_ColorGrayscale;
var
  Src: TMemoryStream;
  Img, OutImg: TLazIntfImage;
  P: TMultiEditParams;
  Pieces: TMultiEditPieces;
  C: TFPColor;
begin
  Src := MakePNG(64, 64);
  try
    Img := DecodeImage(Src, '.png');
    try
      P.Resize := False;
      P.Percent := 100;
      P.Adj := NeutralColorAdjust;
      P.Adj.Grayscale := True;
      P.Split := False;
      AssertTrue('apply ok', ApplyMultiEditToImage(Img, P, '.png', 96, 128,
        Pieces));
      AssertEquals('one piece', 1, Length(Pieces));
      try
        OutImg := DecodeResult(Pieces[0].Stream);
        try
          C := OutImg.Colors[10, 10];
          AssertTrue('gray pixel R=G', C.Red = C.Green);
          AssertTrue('gray pixel G=B', C.Green = C.Blue);
        finally
          OutImg.Free;
        end;
      finally
        FreePieces(Pieces);
      end;
    finally
      Img.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TBatchEditTest.Pipeline_SplitOneLine;
var
  Src: TMemoryStream;
  Img, OutImg: TLazIntfImage;
  P: TMultiEditParams;
  Pieces: TMultiEditPieces;
begin
  Src := MakePNG(100, 50);
  try
    Img := DecodeImage(Src, '.png');
    try
      P.Resize := False;
      P.Percent := 100;
      P.Adj := NeutralColorAdjust;
      P.Split := True;
      P.Horizontal := True;
      SetLength(P.Lines, 1);
      P.Lines[0] := 0.5;
      AssertTrue('apply ok', ApplyMultiEditToImage(Img, P, '.png', 96, 128,
        Pieces));
      AssertEquals('two pieces', 2, Length(Pieces));
      try
        OutImg := DecodeResult(Pieces[0].Stream);
        try
          AssertEquals('top piece width', 100, OutImg.Width);
          AssertEquals('top piece height', 25, OutImg.Height);
        finally
          OutImg.Free;
        end;
        OutImg := DecodeResult(Pieces[1].Stream);
        try
          AssertEquals('bottom piece width', 100, OutImg.Width);
          AssertEquals('bottom piece height', 25, OutImg.Height);
        finally
          OutImg.Free;
        end;
      finally
        FreePieces(Pieces);
      end;
    finally
      Img.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TBatchEditTest.Pipeline_Combined;
var
  Src: TMemoryStream;
  Img, OutImg: TLazIntfImage;
  P: TMultiEditParams;
  Pieces: TMultiEditPieces;
begin
  { 100x50 -> resize 50% (50x25) -> grayscale -> vertical split at 50%
    (2 pieces of 25x25, side by side). }
  Src := MakePNG(100, 50);
  try
    Img := DecodeImage(Src, '.png');
    try
      P.Resize := True;
      P.Percent := 50;
      P.Adj := NeutralColorAdjust;
      P.Adj.Grayscale := True;
      P.Split := True;
      P.Horizontal := False;
      SetLength(P.Lines, 1);
      P.Lines[0] := 0.5;
      AssertTrue('apply ok', ApplyMultiEditToImage(Img, P, '.png', 96, 128,
        Pieces));
      AssertEquals('two pieces', 2, Length(Pieces));
      try
        OutImg := DecodeResult(Pieces[0].Stream);
        try
          AssertEquals('left piece width', 25, OutImg.Width);
          AssertEquals('left piece height', 25, OutImg.Height);
        finally
          OutImg.Free;
        end;
      finally
        FreePieces(Pieces);
      end;
    finally
      Img.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TBatchEditTest.Pipeline_ExtMapping;
var
  Src: TMemoryStream;
  Img: TLazIntfImage;
  P: TMultiEditParams;
  Pieces: TMultiEditPieces;
begin
  { Formats without an FPC writer (GIF/TIFF) map to .png. }
  Src := MakePNG(20, 20);
  try
    Img := DecodeImage(Src, '.png');
    try
      P.Resize := False;
      P.Percent := 100;
      P.Adj := NeutralColorAdjust;
      P.Split := False;
      AssertTrue('apply ok', ApplyMultiEditToImage(Img, P, '.gif', 96, 128,
        Pieces));
      AssertEquals('one piece', 1, Length(Pieces));
      try
        AssertEquals('gif maps to png', '.png', Pieces[0].Ext);
      finally
        FreePieces(Pieces);
      end;
    finally
      Img.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TBatchEditTest.Worker_EditsAllPages;
var
  Path: string;
  Png1, Png2: TMemoryStream;
  Inputs: TMultiEditPageInputs;
  P: TMultiEditParams;
  W: TMultiEditWorker;
  OutImg: TLazIntfImage;
  i: integer;
begin
  Png1 := MakePNG(80, 60);
  Png2 := MakePNG(40, 40);
  try
    Path := FTempDir + 'book.cbz';
    CreateCBZ(Path, [Png1, Png2], ['page_0001.png', 'page_0002.png']);

    SetLength(Inputs, 2);
    Inputs[0].Idx := 0;
    Inputs[0].OrigName := 'page_0001.png';
    Inputs[0].Data := nil;
    Inputs[0].Ext := '.png';
    Inputs[1].Idx := 1;
    Inputs[1].OrigName := 'page_0002.png';
    Inputs[1].Data := nil;
    Inputs[1].Ext := '.png';

    P.Resize := True;
    P.Percent := 50;
    P.Adj := NeutralColorAdjust;
    P.Split := False;
    P.Horizontal := True;
    P.Lines := nil;

    W := TMultiEditWorker.Create(Path, Inputs, P, 96, 128, nil);
    W.FreeOnTerminate := False;
    try
      W.Start;
      W.WaitFor;
      AssertEquals('two results', 2, Length(W.Results));
      for i := 0 to 1 do
      begin
        AssertEquals('result index', i, W.Results[i].Idx);
        AssertEquals('one piece per page', 1, Length(W.Results[i].Pieces));
        OutImg := DecodeResult(W.Results[i].Pieces[0].Stream);
        try
          if i = 0 then
          begin
            AssertEquals('page 1 width halved', 40, OutImg.Width);
            AssertEquals('page 1 height halved', 30, OutImg.Height);
          end
          else
          begin
            AssertEquals('page 2 width halved', 20, OutImg.Width);
            AssertEquals('page 2 height halved', 20, OutImg.Height);
          end;
        finally
          OutImg.Free;
        end;
      end;
    finally
      W.Free;
    end;
  finally
    Png1.Free;
    Png2.Free;
  end;
end;

procedure TBatchEditTest.Worker_DecodesDataOverArchive;
var
  Path: string;
  Png1, Png2, DataPng: TMemoryStream;
  Inputs: TMultiEditPageInputs;
  P: TMultiEditParams;
  W: TMultiEditWorker;
  OutImg: TLazIntfImage;
begin
  Png1 := MakePNG(80, 60);
  Png2 := MakePNG(40, 40);
  DataPng := MakePNG(20, 20);
  try
    Path := FTempDir + 'book.cbz';
    CreateCBZ(Path, [Png1, Png2], ['page_0001.png', 'page_0002.png']);

    { Page 0 keeps its archive entry; page 1 supplies a Data stream that
      must win over the archive bytes (an already-edited page). }
    SetLength(Inputs, 2);
    Inputs[0].Idx := 0;
    Inputs[0].OrigName := 'page_0001.png';
    Inputs[0].Data := nil;
    Inputs[0].Ext := '.png';
    Inputs[1].Idx := 1;
    Inputs[1].OrigName := 'page_0002.png';
    Inputs[1].Data := DataPng;
    Inputs[1].Ext := '.png';

    P.Resize := True;
    P.Percent := 50;
    P.Adj := NeutralColorAdjust;
    P.Split := False;
    P.Horizontal := True;
    P.Lines := nil;

    W := TMultiEditWorker.Create(Path, Inputs, P, 96, 128, nil);
    W.FreeOnTerminate := False;
    try
      W.Start;
      W.WaitFor;
      AssertEquals('two results', 2, Length(W.Results));
      OutImg := DecodeResult(W.Results[1].Pieces[0].Stream);
      try
        AssertEquals('data stream used (20x20 -> 10x10)', 10, OutImg.Width);
        AssertEquals('data stream height', 10, OutImg.Height);
      finally
        OutImg.Free;
      end;
    finally
      W.Free;
    end;
  finally
    DataPng.Free;
    Png1.Free;
    Png2.Free;
  end;
end;

procedure TBatchEditTest.Worker_SplitsAllPages;
var
  Path: string;
  Png1, Png2: TMemoryStream;
  Inputs: TMultiEditPageInputs;
  P: TMultiEditParams;
  W: TMultiEditWorker;
  OutImg: TLazIntfImage;
  i, j: integer;
begin
  Png1 := MakePNG(80, 60);
  Png2 := MakePNG(40, 40);
  try
    Path := FTempDir + 'book.cbz';
    CreateCBZ(Path, [Png1, Png2], ['page_0001.png', 'page_0002.png']);

    SetLength(Inputs, 2);
    Inputs[0].Idx := 0;
    Inputs[0].OrigName := 'page_0001.png';
    Inputs[0].Data := nil;
    Inputs[0].Ext := '.png';
    Inputs[1].Idx := 1;
    Inputs[1].OrigName := 'page_0002.png';
    Inputs[1].Data := nil;
    Inputs[1].Ext := '.png';

    P.Resize := False;
    P.Percent := 100;
    P.Adj := NeutralColorAdjust;
    P.Split := True;
    P.Horizontal := True;
    SetLength(P.Lines, 1);
    P.Lines[0] := 0.5;

    W := TMultiEditWorker.Create(Path, Inputs, P, 96, 128, nil);
    W.FreeOnTerminate := False;
    try
      W.Start;
      W.WaitFor;
      AssertEquals('two results', 2, Length(W.Results));
      for i := 0 to 1 do
      begin
        AssertEquals('two pieces per page', 2, Length(W.Results[i].Pieces));
        for j := 0 to 1 do
        begin
          OutImg := DecodeResult(W.Results[i].Pieces[j].Stream);
          try
            if i = 0 then
            begin
              AssertEquals('piece width 80', 80, OutImg.Width);
              AssertEquals('piece height 30', 30, OutImg.Height);
            end
            else
            begin
              AssertEquals('piece width 40', 40, OutImg.Width);
              AssertEquals('piece height 20', 20, OutImg.Height);
            end;
          finally
            OutImg.Free;
          end;
        end;
      end;
    finally
      W.Free;
    end;
  finally
    Png1.Free;
    Png2.Free;
  end;
end;

procedure TBatchEditTest.Staging_SingleSplit;
var
  Pages: TPageStates;
  Changes: TChanges;
  Results: TMultiEditPageResults;
  HadSplit: boolean;
  Thumbs: TIntfImageArray;
  Staged: integer;
  i: integer;
begin
  { Three pages; page index 1 splits into 2 pieces. }
  SetLength(Pages, 3);
  for i := 0 to 2 do
  begin
    Pages[i].Name := Format('page_000%d.png', [i + 1]);
    Pages[i].OrigName := Pages[i].Name;
    Pages[i].OrigIndex := i;
    Pages[i].Gone := False;
  end;
  SetLength(Results, 1);
  Results[0].Idx := 1;
  SetLength(Results[0].Pieces, 2);
  Results[0].Pieces[0].Ext := '.png';
  Results[0].Pieces[0].Stream := MakePNG(10, 20);
  Results[0].Pieces[0].Thumb := nil;
  Results[0].Pieces[1].Ext := '.png';
  Results[0].Pieces[1].Stream := MakePNG(10, 20);
  Results[0].Pieces[1].Thumb := nil;

  Staged := StageMultiEditResults(Pages, Changes, Results, HadSplit, Thumbs);
  AssertEquals('four pages after split', 4, Length(Pages));
  AssertEquals('two pieces staged', 2, Staged);
  AssertTrue('split happened', HadSplit);
  AssertEquals('piece name', 'split1.png', Pages[2].Name);
  AssertNotNull('page 2 has data', Pages[2].Data);
  AssertEquals('page 2 cannot match an archive entry', 'split1.png',
    Pages[2].OrigName);
  AssertNotNull('piece stream still owned by page 2', Pages[2].Data);
  AssertNull('transferred stream cleared from result', Results[0].Pieces[1].Stream);
  AssertNotNull('replaced page has new data', Pages[1].Data);
  AssertNull('replaced result stream cleared', Results[0].Pieces[0].Stream);
  AssertEquals('no new thumbs in this test', 0, Length(Thumbs));

  { Cleanup: free the staged streams. }
  for i := 0 to High(Pages) do
    Pages[i].Data.Free;
end;

procedure TBatchEditTest.Staging_MultiPageDescending;
var
  Pages: TPageStates;
  Changes: TChanges;
  Results: TMultiEditPageResults;
  HadSplit: boolean;
  Thumbs: TIntfImageArray;
  Staged: integer;
  i: integer;
begin
  { Four pages; pages 0 and 2 each split into 2 pieces.  Processing must
    be in descending order so the lower index is unaffected. }
  SetLength(Pages, 4);
  for i := 0 to 3 do
  begin
    Pages[i].Name := Format('page_000%d.png', [i + 1]);
    Pages[i].OrigName := Pages[i].Name;
    Pages[i].OrigIndex := i;
    Pages[i].Gone := False;
  end;
  SetLength(Results, 2);
  Results[0].Idx := 0;
  Results[1].Idx := 2;
  for i := 0 to 1 do
  begin
    SetLength(Results[i].Pieces, 2);
    Results[i].Pieces[0].Ext := '.png';
    Results[i].Pieces[0].Stream := MakePNG(10, 10);
    Results[i].Pieces[1].Ext := '.png';
    Results[i].Pieces[1].Stream := MakePNG(10, 10);
  end;

  Staged := StageMultiEditResults(Pages, Changes, Results, HadSplit, Thumbs);
  AssertEquals('six pages after two splits', 6, Length(Pages));
  AssertEquals('four pieces staged', 4, Staged);
  AssertTrue('split happened', HadSplit);
  { Descending order: page 2's pieces land at 4/5 first, then page 0's
    piece shifts everything after it right by one. }
  AssertEquals('page 0 piece name', 'split1.png', Pages[1].Name);
  AssertEquals('original page 2 untouched', 'page_0002.png', Pages[2].Name);
  AssertEquals('replaced page 3 keeps its name', 'page_0003.png', Pages[3].Name);
  AssertEquals('page 3 piece name', 'split1.png', Pages[4].Name);
  AssertEquals('original page 4 untouched', 'page_0004.png', Pages[5].Name);

  for i := 0 to High(Pages) do
    Pages[i].Data.Free;
end;

procedure TBatchEditTest.Staging_ReplaceOnly;
var
  Pages: TPageStates;
  Changes: TChanges;
  Results: TMultiEditPageResults;
  HadSplit: boolean;
  Thumbs: TIntfImageArray;
  Staged: integer;
  i: integer;
begin
  SetLength(Pages, 2);
  for i := 0 to 1 do
  begin
    Pages[i].Name := Format('page_000%d.png', [i + 1]);
    Pages[i].OrigName := Pages[i].Name;
    Pages[i].OrigIndex := i;
    Pages[i].Gone := False;
  end;
  SetLength(Results, 2);
  for i := 0 to 1 do
  begin
    Results[i].Idx := i;
    SetLength(Results[i].Pieces, 1);
    Results[i].Pieces[0].Ext := '.png';
    Results[i].Pieces[0].Stream := MakePNG(10, 10);
  end;

  Staged := StageMultiEditResults(Pages, Changes, Results, HadSplit, Thumbs);
  AssertEquals('page count unchanged', 2, Length(Pages));
  AssertEquals('two pieces staged', 2, Staged);
  AssertFalse('no split', HadSplit);
  AssertNotNull('page 0 data replaced', Pages[0].Data);
  AssertNotNull('page 1 data replaced', Pages[1].Data);
  AssertEquals('names untouched', 'page_0001.png', Pages[0].Name);

  for i := 0 to High(Pages) do
    Pages[i].Data.Free;
end;

initialization
  RegisterTest(TBatchEditTest);
end.
