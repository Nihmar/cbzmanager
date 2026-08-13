unit test_upageeditmodel;
{$mode objfpc}{$h+}
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils, IntfGraphics, FPImage, GraphType,
  upageeditmodel, uzipcore, uimgutil, uimageedit, uzipeditor, test_helpers;

type
  { Runs TSaveChangesThread.Execute synchronously on the calling thread so a
    test can block until the save completes without a GUI event loop. }
  TSyncSaveChanges = class(TSaveChangesThread)
  public
    procedure RunSync;
  end;

  TSaveChangesTest = class(TTestCase)
  private
    FTempDir: string;
    FCBZ: string;
    procedure MakePages(const AGoneMask: array of boolean;
      out APages: TPageStates);
    function EntryNames(const AFile: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSave_Renumber_KeepsAllPagesAndComicInfo;
    procedure TestSave_DeleteGone_NoRenumber;
    procedure TestSave_CreatesOldBackup;
    procedure TestSave_EditedPage_DataWins;
    procedure TestSave_Split_StagedPiecesWritesNewPages;
    { Insertion sort must handle entries stored in non-alphabetical order. }
    procedure TestSave_ScrambledOrder_RenumbersAllPages;
  end;

  TPageEditModelTest = class(TTestCase)
  published
    { Move operations must skip Gone (staged-deleted) neighbours so they act
      on the VISIBLE order, not raw FPages slots. }
    procedure TestMoveUp_NoGone;
    procedure TestMoveDown_NoGone;
    procedure TestMoveUp_SkipsGoneNeighbour;
    procedure TestMoveDown_SkipsGoneNeighbour;
    procedure TestMoveUp_FirstVisibleIsNoop;
    procedure TestDeleteSelected_MarksGone;
    procedure TestDragDrop_WithGoneEntry;
    procedure TestInsertAt_Middle;
    procedure TestInsertAt_Clamps;
    procedure TestInsertAt_Front;
  end;

implementation

{ Build a page list from names; GoneMask marks staged-deleted entries
  (shorter masks default the remainder to visible). }
function MakePages(const Names: array of string;
  const GoneMask: array of boolean): TPageStates;
var
  i: integer;
begin
  Result := nil;
  SetLength(Result, Length(Names));
  for i := 0 to High(Names) do
  begin
    Result[i].Name := Names[i];
    Result[i].OrigName := Names[i];
    Result[i].Image := nil;
    Result[i].Data := nil;
    Result[i].OrigIndex := i;
    Result[i].Gone := (i <= High(GoneMask)) and GoneMask[i];
  end;
end;

{ Comma-joined names of the visible (non-Gone) pages, in array order. }
function VisibleNames(const P: TPageStates): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(P) do
    if not P[i].Gone then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + P[i].Name;
    end;
end;

procedure TPageEditModelTest.TestMoveUp_NoGone;
var
  P: TPageStates;
  Ch: TChanges;
begin
  P := MakePages(['a', 'b', 'c'], []);
  Ch := nil;
  PageMoveUp(P, Ch, [1]);                 { move 'b' up }
  AssertEquals('b,a,c', VisibleNames(P));
end;

procedure TPageEditModelTest.TestMoveDown_NoGone;
var
  P: TPageStates;
  Ch: TChanges;
begin
  P := MakePages(['a', 'b', 'c'], []);
  Ch := nil;
  PageMoveDown(P, Ch, [1]);               { move 'b' down }
  AssertEquals('a,c,b', VisibleNames(P));
end;

procedure TPageEditModelTest.TestMoveUp_SkipsGoneNeighbour;
var
  P: TPageStates;
  Ch: TChanges;
begin
  { FPages = [a, b(Gone), c]; visible = [a, c].  Moving 'c' (model index 2)
    up must swap with 'a', not the Gone 'b' — otherwise a silent no-op. }
  P := MakePages(['a', 'b', 'c'], [False, True, False]);
  Ch := nil;
  PageMoveUp(P, Ch, [2]);
  AssertEquals('c,a', VisibleNames(P));
end;

procedure TPageEditModelTest.TestMoveDown_SkipsGoneNeighbour;
var
  P: TPageStates;
  Ch: TChanges;
begin
  { FPages = [a, b(Gone), c]; visible = [a, c].  Moving 'a' (model index 0)
    down must swap with 'c', skipping the Gone 'b'. }
  P := MakePages(['a', 'b', 'c'], [False, True, False]);
  Ch := nil;
  PageMoveDown(P, Ch, [0]);
  AssertEquals('c,a', VisibleNames(P));
end;

procedure TPageEditModelTest.TestMoveUp_FirstVisibleIsNoop;
var
  P: TPageStates;
  Ch: TChanges;
begin
  { 'b' is the first visible page (a is Gone); moving it up does nothing. }
  P := MakePages(['a', 'b', 'c'], [True, False, False]);
  Ch := nil;
  PageMoveUp(P, Ch, [1]);
  AssertEquals('b,c', VisibleNames(P));
end;

procedure TPageEditModelTest.TestDeleteSelected_MarksGone;
var
  P: TPageStates;
  Ch: TChanges;
begin
  P := MakePages(['a', 'b', 'c'], []);
  Ch := nil;
  PageDeleteSelected(P, Ch, [1]);         { delete 'b' (model index 1) }
  AssertEquals('a,c', VisibleNames(P));
  AssertTrue('b is Gone', P[1].Gone);
end;

procedure TPageEditModelTest.TestDragDrop_WithGoneEntry;
var
  P: TPageStates;
  Ch: TChanges;
begin
  { FPages = [a(Gone), b, c, d]; visible = [b, c, d].  Drag 'd' (model 3)
    onto 'b' (model 1): visible order becomes [d, b, c]. }
  P := MakePages(['a', 'b', 'c', 'd'], [True, False, False, False]);
  Ch := nil;
  PageDragDrop(P, Ch, 3, 1);
  AssertEquals('d,b,c', VisibleNames(P));
end;

{ A single initialized TPageState for insertion tests. }
function MakePage(const AName: string): TPageState;
begin
  Result.Name := AName;
  Result.OrigName := AName;
  Result.Image := nil;
  Result.Data := nil;
  Result.OrigIndex := 0;
  Result.Gone := False;
end;

procedure TPageEditModelTest.TestInsertAt_Middle;
var
  P: TPageStates;
  Ch: TChanges;
begin
  P := MakePages(['a', 'b', 'c'], []);
  Ch := nil;
  PageInsertAt(P, Ch, 1, MakePage('x'));
  AssertEquals('a,x,b,c', VisibleNames(P));
end;

procedure TPageEditModelTest.TestInsertAt_Clamps;
var
  P: TPageStates;
  Ch: TChanges;
begin
  P := MakePages(['a', 'b'], []);
  Ch := nil;
  PageInsertAt(P, Ch, -5, MakePage('front'));
  AssertEquals('front,a,b', VisibleNames(P));
  PageInsertAt(P, Ch, 99, MakePage('back'));
  AssertEquals('front,a,b,back', VisibleNames(P));
end;

procedure TPageEditModelTest.TestInsertAt_Front;
var
  P: TPageStates;
  Ch: TChanges;
begin
  P := MakePages(['a', 'b'], []);
  Ch := nil;
  PageInsertAt(P, Ch, 0, MakePage('x'));
  AssertEquals('x,a,b', VisibleNames(P));
end;

procedure TSyncSaveChanges.RunSync;
begin
  Execute;
end;

{ TSaveChangesTest }

procedure TSaveChangesTest.SetUp;
var
  Png1, Png2, Png3, CInfo: TMemoryStream;
begin
  FTempDir := CreateTempDir('cbzsave_');
  FCBZ := FTempDir + 'test.cbz';
  Png1 := CreateMinimalPNGStream;
  Png2 := CreateMinimalPNGStream;
  Png3 := CreateMinimalPNGStream;
  CInfo := TStringStream.Create('<ComicInfo><Title>Test</Title></ComicInfo>');
  CreateCBZ(FCBZ, [Png1, Png2, Png3, CInfo],
    ['page_a.png', 'page_b.png', 'page_c.png', 'ComicInfo.xml']);
  Png1.Free;
  Png2.Free;
  Png3.Free;
  CInfo.Free;
end;

procedure TSaveChangesTest.TearDown;
begin
  DeleteFile(FCBZ);
  DeleteFile(ChangeFileExt(FCBZ, '_OLD.cbz'));
  RemoveDir(FTempDir);           // remove the (now empty) temp dir
end;

{ Build a page snapshot for all three images; GoneMask marks deleted entries. }
procedure TSaveChangesTest.MakePages(const AGoneMask: array of boolean;
  out APages: TPageStates);
const
  Names: array[0..2] of string = ('page_a.png', 'page_b.png', 'page_c.png');
var
  i: integer;
begin
  SetLength(APages, 3);
  for i := 0 to 2 do
  begin
    APages[i].Name := Names[i];
    APages[i].OrigName := Names[i];
    APages[i].Image := nil;
    APages[i].Data := nil;
    APages[i].OrigIndex := i;
    APages[i].Gone := (i <= High(AGoneMask)) and AGoneMask[i];
  end;
end;

{ Comma-joined entry names of a saved CBZ, in archive order. }
function TSaveChangesTest.EntryNames(const AFile: string): string;
var
  Entries: TZipEntries;
  i: integer;
begin
  Result := '';
  Entries := CollectZipEntries(AFile);
  try
    for i := 0 to High(Entries) do
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + Entries[i].Name;
    end;
  finally
    FreeZipEntries(Entries);
  end;
end;

procedure TSaveChangesTest.TestSave_Renumber_KeepsAllPagesAndComicInfo;
var
  Save: TSyncSaveChanges;
  Pages: TPageStates;
begin
  MakePages([], Pages);
  Save := TSyncSaveChanges.Create(FCBZ, Pages, True, False, nil);
  try
    Save.RunSync;
    AssertTrue('save succeeds', Save.Result.Success);
  finally
    Save.Free;
  end;
  AssertEquals('all images renamed + ComicInfo kept',
    'page_0001.png,page_0002.png,page_0003.png,ComicInfo.xml', EntryNames(FCBZ));
end;

procedure TSaveChangesTest.TestSave_DeleteGone_NoRenumber;
var
  Save: TSyncSaveChanges;
  Pages: TPageStates;
begin
  MakePages([False, True, False], Pages);   { middle page staged for deletion }
  Save := TSyncSaveChanges.Create(FCBZ, Pages, False, False, nil);
  try
    Save.RunSync;
    AssertTrue('save succeeds', Save.Result.Success);
  finally
    Save.Free;
  end;
  AssertEquals('survivors keep original names, ComicInfo kept',
    'page_a.png,page_c.png,ComicInfo.xml', EntryNames(FCBZ));
end;

procedure TSaveChangesTest.TestSave_CreatesOldBackup;
var
  Save: TSyncSaveChanges;
  Pages: TPageStates;
begin
  MakePages([], Pages);
  Save := TSyncSaveChanges.Create(FCBZ, Pages, True, True, nil);  { backup }
  try
    Save.RunSync;
    AssertTrue('save succeeds', Save.Result.Success);
  finally
    Save.Free;
  end;
  AssertTrue('_OLD.cbz backup exists', FileExists(ChangeFileExt(FCBZ, '_OLD.cbz')));
end;

{ A page whose OrigName still matches an archive entry but carries its own
  Data stream (the page editor's replace mode) must be saved from the Data
  stream — the archive copy must not win.  The original entry is consumed by
  the OrigName lookup so it is not duplicated by the metadata pass. }
procedure TSaveChangesTest.TestSave_EditedPage_DataWins;
var
  Save: TSyncSaveChanges;
  Pages: TPageStates;
  Entries: TZipEntries;
  i: integer;
  S: string;
begin
  MakePages([], Pages);
  Pages[0].Data := TStringStream.Create('EDITED-BYTES-123');
  Save := TSyncSaveChanges.Create(FCBZ, Pages, True, False, nil);
  try
    Save.RunSync;
    AssertTrue('save succeeds', Save.Result.Success);
  finally
    Save.Free;
  end;
  Entries := CollectZipEntries(FCBZ);
  try
    AssertEquals('3 pages + ComicInfo', 4, Length(Entries));
    for i := 0 to High(Entries) do
      if Entries[i].Name = 'page_0001.png' then
      begin
        SetString(S, PChar(Entries[i].Data.Memory), Entries[i].Data.Size);
        AssertEquals('edited bytes win over the archive copy',
          'EDITED-BYTES-123', S);
        Pages[0].Data.Free;
        Exit;
      end;
    Fail('page_0001.png not found in saved CBZ');
  finally
    FreeZipEntries(Entries);
  end;
end;

{ Builds a W x H PNG stream whose rows carry the row index as grey value
  (allows the split pieces to be told apart after a round trip). }
function MakeGradientPNGStream(W, H: integer): TMemoryStream;
var
  Desc: TRawImageDescription;
  Img: TLazIntfImage;
  x, y: integer;
  C: TFPColor;
begin
  Desc.Init_BPP32_B8G8R8A8_BIO_TTB(W, H);
  Img := TLazIntfImage.Create(0, 0);
  try
    Img.DataDescription := Desc;
    C.Alpha := 65535;
    for y := 0 to H - 1 do
    begin
      C.Red := y * 256;
      C.Green := y * 256;
      C.Blue := y * 256;
      for x := 0 to W - 1 do
        Img.Colors[x, y] := C;
    end;
    Result := EncodeIntfImage(Img, '.png');
  finally
    Img.Free;
  end;
end;

{ Decodes the named entry of AFile at full resolution, or nil when missing. }
function DecodeEntry(const AFile, AName: string): TLazIntfImage;
var
  Entries: TZipEntries;
  i: integer;
begin
  Result := nil;
  Entries := CollectZipEntries(AFile);
  try
    for i := 0 to High(Entries) do
      if Entries[i].Name = AName then
      begin
        Entries[i].Data.Position := 0;
        Result := DecodeImage(Entries[i].Data, '.png');
        Break;
      end;
  finally
    FreeZipEntries(Entries);
  end;
end;

{ True when AFile contains an entry named AName. }
function HasEntry(const AFile, AName: string): boolean;
var
  Entries: TZipEntries;
  i: integer;
begin
  Result := False;
  Entries := CollectZipEntries(AFile);
  try
    for i := 0 to High(Entries) do
      if Entries[i].Name = AName then
        Exit(True);
  finally
    FreeZipEntries(Entries);
  end;
end;

{ Grey value of the first pixel of a BGRA32 image (byte 2 = R). }
function FirstPixelGray(Img: TLazIntfImage): integer;
var
  P: pbyte;
begin
  P := Img.GetDataLineStart(0);
  Result := P[2];
end;

{ Full split pipeline, staged exactly like main.pas ApplyPageEdit:
  piece 0 replaces the split page in place, the extra piece becomes a new
  page inserted right after it, and all pages are renumbered; the save
  thread must write the piece bytes at the split positions. }
procedure TSaveChangesTest.TestSave_Split_StagedPiecesWritesNewPages;
var
  CBZ: string;
  S1, S2, S3, CInfo: TMemoryStream;
  Save: TSyncSaveChanges;
  Pages: TPageStates;
  Ch: TChanges;
  Img, Piece: TLazIntfImage;
  Pieces: TIntfImageArray;
  i, Cut, H: integer;
  P: TPageState;
begin
  { Fixture: three 8x10 gradient pages (row y has grey value y). }
  CBZ := FTempDir + 'split.cbz';
  S1 := MakeGradientPNGStream(8, 10);
  S2 := MakeGradientPNGStream(8, 10);
  S3 := MakeGradientPNGStream(8, 10);
  CInfo := TStringStream.Create('<ComicInfo><Title>Test</Title></ComicInfo>');
  CreateCBZ(CBZ, [S1, S2, S3, CInfo],
    ['page_a.png', 'page_b.png', 'page_c.png', 'ComicInfo.xml']);
  S1.Free;
  S2.Free;
  S3.Free;
  CInfo.Free;

  { Decode page_b and cut it at 50%. }
  Img := DecodeEntry(CBZ, 'page_b.png');
  AssertNotNull('page_b decodes', Img);
  H := Img.Height;
  try
    Pieces := SplitIntfImage(Img, True, [0.5]);
  finally
    Img.Free;
  end;
  AssertEquals('two pieces', 2, Length(Pieces));
  Cut := Round(0.5 * H);
  try
    AssertEquals('top piece height', Cut, Pieces[0].Height);
    AssertEquals('bottom piece height', H - Cut, Pieces[1].Height);

    { Stage like main.pas: piece 0 replaces page_b (index 1), piece 1 becomes
      a new page inserted after it; then renumber everything. }
    SetLength(Pages, 3);
    for i := 0 to 2 do
    begin
      Pages[i].Name := 'page_' + Chr(Ord('a') + i) + '.png';
      Pages[i].OrigName := Pages[i].Name;
      Pages[i].OrigIndex := i;
      Pages[i].Gone := False;
      Pages[i].Data := nil;
      Pages[i].Image := nil;
    end;
    Pages[1].Data := EncodeIntfImage(Pieces[0], '.png');
    AssertNotNull('piece 0 encodes', Pages[1].Data);
    P.Name := 'split1.png';
    P.OrigName := 'split1.png';
    P.OrigIndex := -1;
    P.Gone := False;
    P.Data := EncodeIntfImage(Pieces[1], '.png');
    P.Image := nil;
    AssertNotNull('piece 1 encodes', P.Data);
    PageInsertAt(Pages, Ch, 2, P);
    Ch := nil;
    PageRenumber(Pages, Ch);

    Save := TSyncSaveChanges.Create(CBZ, Pages, True, False, nil);
    try
      Save.RunSync;
      AssertTrue('save succeeds', Save.Result.Success);
    finally
      Save.Free;
    end;
  finally
    FreeImageArray(Pieces);
    for i := 0 to High(Pages) do
      Pages[i].Data.Free;
  end;

  { Verify: 4 renumbered pages + ComicInfo, with the piece bytes in place. }
  Img := DecodeEntry(CBZ, 'page_0001.png');
  try
    AssertNotNull('page_0001 present', Img);
    AssertEquals('page_0001 = original page_a height', 10, Img.Height);
  finally
    Img.Free;
  end;
  Img := DecodeEntry(CBZ, 'page_0002.png');
  try
    AssertNotNull('page_0002 (top piece) present', Img);
    AssertEquals('top piece height', Cut, Img.Height);
    AssertEquals('top piece first row', 0, FirstPixelGray(Img));
  finally
    Img.Free;
  end;
  Img := DecodeEntry(CBZ, 'page_0003.png');
  try
    AssertNotNull('page_0003 (bottom piece) present', Img);
    AssertEquals('bottom piece height', H - Cut, Img.Height);
    AssertEquals('bottom piece starts at the cut row', Cut, FirstPixelGray(Img));
  finally
    Img.Free;
  end;
  Img := DecodeEntry(CBZ, 'page_0004.png');
  try
    AssertNotNull('page_0004 = original page_c present', Img);
    AssertEquals('page_0004 height', 10, Img.Height);
  finally
    Img.Free;
  end;
  AssertTrue('ComicInfo.xml kept',
    HasEntry(CBZ, 'ComicInfo.xml'));
  DeleteFile(CBZ);
end;

{ Entries stored in reverse-alphabetical order (maximum shift cascades in the
  insertion sort).  The buggy sort overwrites several SortedNames slots with
  shifted copies, causing multiple distinct OrigName lookups to resolve to the
  same archive index — which produces duplicate page entries instead of four
  unique ones. }
procedure TSaveChangesTest.TestSave_ScrambledOrder_RenumbersAllPages;
var
  CBZ: string;
  S1, S2, S3, S4, CInfo: TMemoryStream;
  Save: TSyncSaveChanges;
  Pages: TPageStates;
begin
  { Build a CBZ with entries in descending order — forces 6 total shifts
    during insertion sort, corrupting multiple SortedNames slots. }
  CBZ := FTempDir + 'scrambled.cbz';
  S1 := CreateMinimalPNGStream;   { page_z (idx 0) }
  S2 := CreateMinimalPNGStream;   { page_d (idx 1) }
  S3 := CreateMinimalPNGStream;   { page_b (idx 2) }
  S4 := CreateMinimalPNGStream;   { page_a (idx 3) }
  CInfo := TStringStream.Create('<ComicInfo><Title>Scrambled</Title></ComicInfo>');
  CreateCBZ(CBZ, [S1, S2, S3, S4, CInfo],
    ['page_z.png', 'page_d.png', 'page_b.png', 'page_a.png', 'ComicInfo.xml']);
  S1.Free;
  S2.Free;
  S3.Free;
  S4.Free;
  CInfo.Free;

  { Build a page model — each page carries the correct OrigName. }
  SetLength(Pages, 4);
  Pages[0].Name := 'page_z.png';   Pages[0].OrigName := 'page_z.png';
  Pages[1].Name := 'page_d.png';   Pages[1].OrigName := 'page_d.png';
  Pages[2].Name := 'page_b.png';   Pages[2].OrigName := 'page_b.png';
  Pages[3].Name := 'page_a.png';   Pages[3].OrigName := 'page_a.png';
  Pages[0].Image := nil;           Pages[0].Data := nil;          Pages[0].OrigIndex := 0; Pages[0].Gone := False;
  Pages[1].Image := nil;           Pages[1].Data := nil;          Pages[1].OrigIndex := 1; Pages[1].Gone := False;
  Pages[2].Image := nil;           Pages[2].Data := nil;          Pages[2].OrigIndex := 2; Pages[2].Gone := False;
  Pages[3].Image := nil;           Pages[3].Data := nil;          Pages[3].OrigIndex := 3; Pages[3].Gone := False;

  { Save with renumber. }
  Save := TSyncSaveChanges.Create(CBZ, Pages, True, False, nil);
  try
    Save.RunSync;
    AssertTrue('save succeeds', Save.Result.Success);
  finally
    Save.Free;
  end;

  { Verify: exactly 4 renumbered pages + ComicInfo — no duplicates. }
  AssertEquals('5 entries total (4 pages + ComicInfo)',
    'page_0001.png,page_0002.png,page_0003.png,page_0004.png,ComicInfo.xml',
    EntryNames(CBZ));
  DeleteFile(CBZ);
end;

initialization
  RegisterTest(TPageEditModelTest);
  RegisterTest(TSaveChangesTest);
end.
