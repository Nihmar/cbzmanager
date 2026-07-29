unit test_upageeditmodel;
{$mode objfpc}{$h+}
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils, upageeditmodel;

type
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

initialization
  RegisterTest(TPageEditModelTest);
end.
