unit uselection;

{$mode ObjFPC}{$H+}

interface

uses
  ComCtrls, Types;

{ Contiguous index range [Lo..Hi] (inclusive, ascending regardless of
  argument order). }
function RangeSel(Lo, Hi: integer): TIntegerDynArray;

{ True when V is present in A. }
function HasSel(const A: TIntegerDynArray; V: integer): boolean;

{ If V is in A, remove it; otherwise append it. }
function ToggleSel(const A: TIntegerDynArray; V: integer): TIntegerDynArray;

{ Union of A and B (no duplicates, preserves A order). }
function UnionSel(const A, B: TIntegerDynArray): TIntegerDynArray;

{ True when exactly the items at indices in A are selected in ALV. }
function SelectionMatches(ALV: TListView; const A: array of integer): boolean;

{ Make exactly the indices in A selected (clearing everything else);
  focus the item at AFocus when the selection is a single item. }
procedure ApplySelection(ALV: TListView; const A: array of integer;
  AFocus: integer);

implementation

function RangeSel(Lo, Hi: integer): TIntegerDynArray;
var
  i, t: integer;
begin
  Result := nil;
  if Lo > Hi then begin t := Lo; Lo := Hi; Hi := t; end;
  SetLength(Result, Hi - Lo + 1);
  for i := Lo to Hi do
    Result[i - Lo] := i;
end;

function HasSel(const A: TIntegerDynArray; V: integer): boolean;
var
  i: integer;
begin
  Result := False;
  for i := 0 to High(A) do
    if A[i] = V then Exit(True);
end;

function ToggleSel(const A: TIntegerDynArray; V: integer): TIntegerDynArray;
var
  i, n: integer;
begin
  Result := nil;
  if HasSel(A, V) then
  begin
    n := 0;
    SetLength(Result, Length(A) - 1);
    for i := 0 to High(A) do
      if A[i] <> V then begin Result[n] := A[i]; Inc(n); end;
  end
  else
  begin
    SetLength(Result, Length(A) + 1);
    for i := 0 to High(A) do Result[i] := A[i];
    Result[High(Result)] := V;
  end;
end;

function UnionSel(const A, B: TIntegerDynArray): TIntegerDynArray;
var
  i, n: integer;
begin
  Result := Copy(A);
  for i := 0 to High(B) do
    if not HasSel(Result, B[i]) then
    begin
      n := Length(Result);
      SetLength(Result, n + 1);
      Result[n] := B[i];
    end;
end;

function SelectionMatches(ALV: TListView;
  const A: array of integer): boolean;
var
  i: integer;
begin
  Result := False;
  if ALV.SelCount <> Length(A) then Exit;
  for i := 0 to High(A) do
    if (A[i] < 0) or (A[i] >= ALV.Items.Count) or
       not ALV.Items[A[i]].Selected then
      Exit;
  Result := True;
end;

procedure ApplySelection(ALV: TListView; const A: array of integer;
  AFocus: integer);
var
  i, idx: integer;
begin
  ALV.BeginUpdate;
  try
    for i := 0 to ALV.Items.Count - 1 do
      ALV.Items[i].Selected := False;
    for idx in A do
      if (idx >= 0) and (idx < ALV.Items.Count) then
        ALV.Items[idx].Selected := True;
  finally
    ALV.EndUpdate;
  end;
  if (Length(A) <= 1) and (AFocus >= 0) and (AFocus < ALV.Items.Count) then
    ALV.Selected := ALV.Items[AFocus];
end;

end.
