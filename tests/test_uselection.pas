unit test_uselection;

{$mode objfpc}{$H+}

{ Unit tests for the pure selection-set helpers (uselection.pas) that back
  the Explorer-style multi-selection in the main form and the sequence
  builder: contiguous ranges, toggle/union without duplicates, membership. }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils, Types;

type
  TSelectionTest = class(TTestCase)
  published
    procedure RangeSel_Ascending;
    procedure RangeSel_Reversed;
    procedure RangeSel_Single;
    procedure HasSel_FoundAndMissing;
    procedure ToggleSel_AddsMissing;
    procedure ToggleSel_RemovesPresent;
    procedure UnionSel_NoDuplicates;
    procedure UnionSel_PreservesOrder;
  end;

implementation

uses
  uselection;

procedure TSelectionTest.RangeSel_Ascending;
var
  R: TIntegerDynArray;
begin
  R := RangeSel(2, 5);
  AssertEquals('range length', 4, Length(R));
  AssertEquals('first', 2, R[0]);
  AssertEquals('last', 5, R[3]);
end;

procedure TSelectionTest.RangeSel_Reversed;
var
  R: TIntegerDynArray;
begin
  { Reversed arguments yield the same ascending range (anchor may sit
    after the clicked item). }
  R := RangeSel(5, 2);
  AssertEquals('range length', 4, Length(R));
  AssertEquals('first', 2, R[0]);
  AssertEquals('last', 5, R[3]);
end;

procedure TSelectionTest.RangeSel_Single;
var
  R: TIntegerDynArray;
begin
  R := RangeSel(3, 3);
  AssertEquals('single length', 1, Length(R));
  AssertEquals('single value', 3, R[0]);
end;

procedure TSelectionTest.HasSel_FoundAndMissing;
var
  A: TIntegerDynArray;
begin
  A := RangeSel(1, 3);
  AssertTrue('present', HasSel(A, 2));
  AssertFalse('missing', HasSel(A, 9));
  AssertFalse('empty never matches', HasSel(nil, 1));
end;

procedure TSelectionTest.ToggleSel_AddsMissing;
var
  R: TIntegerDynArray;
begin
  R := ToggleSel(RangeSel(1, 2), 5);
  AssertEquals('grew by one', 3, Length(R));
  AssertTrue('new member present', HasSel(R, 5));
  AssertTrue('old members kept', HasSel(R, 1) and HasSel(R, 2));
end;

procedure TSelectionTest.ToggleSel_RemovesPresent;
var
  R: TIntegerDynArray;
begin
  R := ToggleSel(RangeSel(1, 3), 2);
  AssertEquals('shrank by one', 2, Length(R));
  AssertFalse('toggled member gone', HasSel(R, 2));
  AssertTrue('others kept', HasSel(R, 1) and HasSel(R, 3));
end;

procedure TSelectionTest.UnionSel_NoDuplicates;
var
  R: TIntegerDynArray;
begin
  R := UnionSel(RangeSel(1, 3), RangeSel(2, 4));
  AssertEquals('no duplicates', 4, Length(R));
  AssertTrue('covers both', HasSel(R, 1) and HasSel(R, 4));
end;

procedure TSelectionTest.UnionSel_PreservesOrder;
var
  R: TIntegerDynArray;
begin
  { Ctrl+Shift extend keeps the existing selection order first, then the
    new range members — the authoritative FSel order must stay stable so
    repeated toggles are deterministic. }
  R := UnionSel(RangeSel(5, 6), RangeSel(1, 2));
  AssertEquals('length', 4, Length(R));
  AssertEquals('A order first', 5, R[0]);
  AssertEquals('A order second', 6, R[1]);
  AssertEquals('B appended', 1, R[2]);
  AssertEquals('B appended', 2, R[3]);
end;

initialization
  RegisterTest(TSelectionTest);
end.
