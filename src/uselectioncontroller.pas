unit uselectioncontroller;

{
  TListSelectionController – Explorer/Dolphin-style selection gestures for one
  TListView, extracted from TfrmMain.

  Why it exists: on Qt6 the widgetset computes icon-view shift ranges from
  visual rows between its own anchor and the clicked item, and runs its own
  selection reconcile on whichever message-loop tick it likes.  The form
  therefore computes the exact desired selection itself on MouseDown and
  re-applies it on the next tick (Reassert) after the native press/release
  reconcile.  The authoritative selection (FSel) makes Ctrl+click toggles
  deterministic regardless of the order in which the native selection changes
  arrive.

  Behaviour (unchanged from the original implementation):
  - Left click            : replace the selection with the clicked item.
  - Ctrl+left click       : toggle the clicked item, based on FSel.
  - Shift+left click      : contiguous anchor..clicked range, replacing the
                            previous selection; the anchor stays put.
  - Ctrl+Shift+left click : add the range to the existing selection.
  - Left click on empty   : clear the selection and the anchor.
  - Right click           : select the clicked item only when it was not
                            already selected (a right-click on an existing
                            multi-selection keeps it).
}

{$mode objfpc}{$H+}

interface

uses
  Classes, ComCtrls, Controls, Forms, Types, uselection;

type
  TListSelectionController = class
  private
    FList: TListView;
    { Shift+click anchor (item index, -1 = none). }
    FAnchor: integer;
    { Authoritative current selection (item indices). }
    FSel: TIntegerDynArray;
    { Pending re-assert scheduled by MouseUp / SelectOnly. }
    FPending: boolean;
    FPendingSel: TIntegerDynArray;
    FPendingFocus: integer;
    FReassertTicks: integer;
    FReassertStable: integer;
    procedure ClearPending;
    procedure SetPending(const A: array of integer; AFocus: integer);
  public
    constructor Create(AList: TListView);
    { Forgets a pending re-assert without touching the list. }
    procedure CancelPending;
    { Clears the anchor and the authoritative selection (the rows changed). }
    procedure Reset;
    { Reset plus pending cancellation. }
    procedure ResetAll;
    { Folds a native selection change (keyboard navigation, Ctrl+A) into the
      authoritative state and refreshes the anchor. }
    procedure SyncFromNative;
    { Native OnSelectItem hook: ignored while a re-assert is in flight. }
    procedure SelectItem(AItem: TListItem; ASelected: boolean);
    { MouseDown handler.  AShiftDown/ACtrlDown are the live modifier flags the
      form tracks (the Qt6 event Shift set drops them now and then). }
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer;
      AShiftDown, ACtrlDown: boolean);
    { Applies the selection gesture of a left click on item AIndex (-1 = empty
      space).  Exposed so the gesture matrix can be unit-tested without
      synthesising mouse coordinates; MouseDown resolves the item and calls
      this after cancelling any pending re-assert. }
    procedure Click(AIndex: integer; AShiftDown, ACtrlDown: boolean);
    { Schedules the deferred re-assert computed by MouseDown. }
    procedure MouseUp;
    { Message-loop callback: re-applies the pending selection until it has
      survived a couple of ticks untouched.  Exposed for tests. }
    procedure Reassert(Data: PtrInt);
    { Replaces the selection with item AIndex and arms the re-assert (the
      double-click path uses it before the preview opens). }
    procedure SelectOnly(AIndex: integer);
    property List: TListView read FList;
    { Current shift+click anchor (-1 = none). }
    property Anchor: integer read FAnchor;
  end;

{ Resolves the list item under a client-coordinate point, falling back to a
  DisplayRect scan when the widgetset's GetItemAt returns nil (vsIcon on
  Qt6).  Returns nil for empty space. }
function ItemAtPoint(ALV: TListView; X, Y: integer): TListItem;

implementation

const
  { Watch the selection until it has stayed ours for STABLE ticks in a row,
    and give up after MAX.  A widgetset runs its own click reconcile on
    whichever tick it pleases, so rather than guess a fixed number of
    re-applies we watch until the selection has stayed ours. }
  REASSERT_STABLE_TICKS = 2;
  REASSERT_MAX_TICKS = 30;

constructor TListSelectionController.Create(AList: TListView);
begin
  inherited Create;
  FList := AList;
  FAnchor := -1;
  FPendingFocus := -1;
end;

function ItemAtPoint(ALV: TListView; X, Y: integer): TListItem;
var
  i: integer;
  R: TRect;
  Pt: TPoint;
begin
  Result := ALV.GetItemAt(X, Y);
  if Result <> nil then Exit;
  Pt := Point(X, Y);
  for i := 0 to ALV.Items.Count - 1 do
  begin
    R := ALV.Items[i].DisplayRect(drBounds);
    if PtInRect(R, Pt) then
      Exit(ALV.Items[i]);
  end;
  Result := nil;
end;

procedure TListSelectionController.ClearPending;
begin
  FPending := False;
  FPendingSel := nil;
  FPendingFocus := -1;
  FReassertStable := 0;
  FReassertTicks := 0;
end;

procedure TListSelectionController.CancelPending;
begin
  ClearPending;
end;

procedure TListSelectionController.Reset;
begin
  FAnchor := -1;
  FSel := nil;
end;

procedure TListSelectionController.ResetAll;
begin
  Reset;
  ClearPending;
end;

procedure TListSelectionController.SyncFromNative;
var
  i, n: integer;
begin
  n := 0;
  SetLength(FSel, FList.Items.Count);
  for i := 0 to FList.Items.Count - 1 do
    if FList.Items[i].Selected then
    begin
      FSel[n] := i;
      Inc(n);
    end;
  SetLength(FSel, n);
  if FList.Selected <> nil then
    FAnchor := FList.Selected.Index
  else
    FAnchor := -1;
end;

procedure TListSelectionController.SelectItem(AItem: TListItem;
  ASelected: boolean);
begin
  { While a reassert is in flight the events belong to the native click
    reconcile or to our own ApplySelection: ignore them.  This handler never
    modifies the selection itself, so it cannot recurse. }
  if FPending then Exit;
  SyncFromNative;
end;

procedure TListSelectionController.SetPending(const A: array of integer;
  AFocus: integer);
var
  i: integer;
begin
  FPending := True;
  SetLength(FPendingSel, Length(A));
  for i := 0 to High(A) do
    FPendingSel[i] := A[i];
  FPendingFocus := AFocus;
  SetLength(FSel, Length(A));
  for i := 0 to High(A) do
    FSel[i] := A[i];
end;

procedure TListSelectionController.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: integer; AShiftDown, ACtrlDown: boolean);
var
  It: TListItem;
begin
  It := ItemAtPoint(FList, X, Y);

  { Right-click on an unselected item makes that item the sole selection so
    the context menu acts on it alone; right-clicking an already-selected
    item keeps the existing multi-selection intact — and must NOT cancel a
    pending reassert from a preceding left-click. }
  if Button = mbRight then
  begin
    if (It <> nil) and not It.Selected then
    begin
      if not (ssDouble in Shift) then
        ClearPending;
      SetPending([It.Index], It.Index);
    end;
    Exit;
  end;

  if Button <> mbLeft then Exit;

  { Any new left-click gesture cancels a pending re-assert, except the second
    press of a double-click (which carries ssDouble) so the first click's
    pending selection survives into the completed double-click. }
  if not (ssDouble in Shift) then
    ClearPending;

  if It = nil then
    Click(-1, AShiftDown, ACtrlDown)
  else
    Click(It.Index, AShiftDown, ACtrlDown);
end;

procedure TListSelectionController.Click(AIndex: integer; AShiftDown,
  ACtrlDown: boolean);
var
  Base: integer;
begin
  if AIndex < 0 then
  begin
    { Click on empty space: clear the selection and drop the anchor. }
    SetPending([], -1);
    FAnchor := -1;
    Exit;
  end;

  if AShiftDown then
  begin
    { Shift+click (with or without Ctrl) selects the contiguous range from the
      anchor to the clicked item, replacing any previous selection — Explorer
      semantics.  The anchor is left in place so repeated shift+clicks extend
      from the same base. }
    Base := FAnchor;
    if Base < 0 then
    begin
      { No explicit anchor yet: extend from the currently focused item (Explorer
        keeps the focus as the shift base), falling back to the clicked item. }
      if FList.Selected <> nil then
        Base := FList.Selected.Index
      else
        Base := AIndex;
    end;
    if ACtrlDown then
      { Ctrl+Shift+click: add the anchor..clicked range to the existing
        selection (extend) instead of replacing it, matching Explorer. }
      SetPending(UnionSel(FSel, RangeSel(Base, AIndex)), AIndex)
    else
      SetPending(RangeSel(Base, AIndex), AIndex);
  end
  else if ACtrlDown then
  begin
    { Ctrl+click toggles the clicked item, based on the authoritative selection
      we last applied (the native widgetset may have toggled it first, so we
      must not read the native state here). }
    SetPending(ToggleSel(FSel, AIndex), AIndex);
    FAnchor := AIndex;
  end
  else
  begin
    { Plain click replaces the selection with the clicked item. }
    SetPending([AIndex], AIndex);
    FAnchor := AIndex;
  end;
end;

procedure TListSelectionController.MouseUp;
begin
  if not FPending then Exit;
  FReassertTicks := REASSERT_MAX_TICKS;
  FReassertStable := 0;
  Application.QueueAsyncCall(@Reassert, 0);
end;

procedure TListSelectionController.SelectOnly(AIndex: integer);
begin
  if (AIndex < 0) or (AIndex >= FList.Items.Count) then
    ClearPending
  else
    SetPending([AIndex], AIndex);
end;

procedure TListSelectionController.Reassert(Data: PtrInt);
begin
  if (not FPending) or (FList = nil) or (FList.Items.Count = 0) then
  begin
    ClearPending;
    Exit;
  end;

  { Only touch the list when it actually differs: re-applying an already
    correct selection fires selection-change events for nothing. }
  if SelectionMatches(FList, FPendingSel) then
    Inc(FReassertStable)
  else
  begin
    ApplySelection(FList, FPendingSel, FPendingFocus);
    FReassertStable := 0;
  end;

  if FReassertTicks > 0 then
    Dec(FReassertTicks);
  { Done once the selection has survived untouched for a couple of ticks.
    The cap is only a backstop against a widgetset that insists on undoing
    us every single tick; without it this would spin forever. }
  if (FReassertStable >= REASSERT_STABLE_TICKS) or (FReassertTicks <= 0) then
    ClearPending
  else
    Application.QueueAsyncCall(@Reassert, 0);
end;

end.
