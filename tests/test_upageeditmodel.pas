unit test_upageeditmodel;
{$mode objfpc}{$h+}
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils, upageeditmodel, uzipcore, test_helpers;

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

initialization
  RegisterTest(TPageEditModelTest);
  RegisterTest(TSaveChangesTest);
end.
