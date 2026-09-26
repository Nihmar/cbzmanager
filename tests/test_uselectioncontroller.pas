unit test_uselectioncontroller;

{$mode objfpc}{$H+}

{ Tests for TListSelectionController: the Qt6-safe Explorer-style gesture
  logic behind the file/page grids.  The controller applies the exact desired
  selection on the next message-loop tick (Reassert); these tests call Click
  directly (no mouse coordinates needed) and Reassert to publish, then verify
  the native list through uselection.SelectionMatches. }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TListSelectionControllerTest = class(TTestCase)
  private
    FAppInitialized: boolean;
    procedure EnsureApp;
  published
    procedure PlainClick_ReplacesSelectionAndAnchors;
    procedure CtrlClick_TogglesFromAuthoritativeState;
    procedure ShiftClick_ReplacesWithRange;
    procedure CtrlShiftClick_UnionsWithExisting;
    procedure EmptyClick_ClearsSelection;
    procedure ShiftAfterSyncFromNative_ExtendsFromFocus;
    procedure SelectOnly_AppliesSingleSelection;
    procedure ResetAll_DropsAnchorAndPending;
  end;

implementation

uses
  Forms, ComCtrls, Types,
  uselection, uselectioncontroller;

procedure TListSelectionControllerTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

{ A list with 5 items and a controller on top.  Caller frees both. }
procedure MakeList(out ALV: TListView; out ACtl: TListSelectionController;
  ACount: integer = 5);
var
  i: integer;
begin
  ALV := TListView.Create(nil);
  for i := 0 to ACount - 1 do
    ALV.Items.Add;
  ACtl := TListSelectionController.Create(ALV);
end;

procedure TListSelectionControllerTest.PlainClick_ReplacesSelectionAndAnchors;
var
  LV: TListView;
  Ctl: TListSelectionController;
begin
  EnsureApp;
  MakeList(LV, Ctl);
  try
    Ctl.Click(1, False, False);
    Ctl.Reassert(0);
    AssertTrue('item 1 selected', SelectionMatches(LV, [1]));
    AssertEquals('anchor at clicked item', 1, Ctl.Anchor);
  finally
    Ctl.Free;
    LV.Free;
  end;
end;

procedure TListSelectionControllerTest.CtrlClick_TogglesFromAuthoritativeState;
var
  LV: TListView;
  Ctl: TListSelectionController;
begin
  EnsureApp;
  MakeList(LV, Ctl);
  try
    { The native widgetset may have toggled the item before we run: the
      toggle must base on OUR authoritative selection, so clicking 1, then
      Ctrl+clicking 3 gives {1,3} even though the list was still empty. }
    Ctl.Click(1, False, False);
    Ctl.Click(3, False, True);
    Ctl.Reassert(0);
    AssertTrue('{1,3} selected', SelectionMatches(LV, [1, 3]));

    { Ctrl+click the same item again removes it. }
    Ctl.Click(1, False, True);
    Ctl.Reassert(0);
    AssertTrue('{3} after second toggle', SelectionMatches(LV, [3]));
  finally
    Ctl.Free;
    LV.Free;
  end;
end;

procedure TListSelectionControllerTest.ShiftClick_ReplacesWithRange;
var
  LV: TListView;
  Ctl: TListSelectionController;
begin
  EnsureApp;
  MakeList(LV, Ctl);
  try
    Ctl.Click(1, False, False);   { anchor = 1 }
    Ctl.Click(4, True, False);    { shift+click }
    Ctl.Reassert(0);
    AssertTrue('range 1..4', SelectionMatches(LV, [1, 2, 3, 4]));

    { The anchor stays put: a second shift+click extends from it again. }
    Ctl.Click(2, True, False);
    Ctl.Reassert(0);
    AssertTrue('range 1..2 from the same anchor',
      SelectionMatches(LV, [1, 2]));
  finally
    Ctl.Free;
    LV.Free;
  end;
end;

procedure TListSelectionControllerTest.CtrlShiftClick_UnionsWithExisting;
var
  LV: TListView;
  Ctl: TListSelectionController;
begin
  EnsureApp;
  MakeList(LV, Ctl);
  try
    Ctl.Click(0, False, False);      { {0}, anchor 0 }
    Ctl.Click(2, False, True);       { Ctrl+click: {0,2}, anchor 2 }
    Ctl.Click(4, True, True);        { Ctrl+Shift: 2..4 added }
    Ctl.Reassert(0);
    AssertTrue('{0,2,3,4}', SelectionMatches(LV, [0, 2, 3, 4]));
  finally
    Ctl.Free;
    LV.Free;
  end;
end;

procedure TListSelectionControllerTest.EmptyClick_ClearsSelection;
var
  LV: TListView;
  Ctl: TListSelectionController;
begin
  EnsureApp;
  MakeList(LV, Ctl);
  try
    Ctl.Click(2, False, False);
    Ctl.Reassert(0);
    AssertTrue('selected before', SelectionMatches(LV, [2]));

    Ctl.Click(-1, False, False);
    Ctl.Reassert(0);
    AssertTrue('cleared', SelectionMatches(LV, []));
    AssertEquals('anchor dropped', -1, Ctl.Anchor);
  finally
    Ctl.Free;
    LV.Free;
  end;
end;

procedure TListSelectionControllerTest.ShiftAfterSyncFromNative_ExtendsFromFocus;
var
  LV: TListView;
  Ctl: TListSelectionController;
begin
  EnsureApp;
  MakeList(LV, Ctl);
  try
    { Keyboard navigation selects natively; the hook folds it in.  A later
      shift+click with no explicit anchor must extend from the focused item. }
    LV.Items[3].Selected := True;
    Ctl.SyncFromNative;
    Ctl.Click(1, True, False);
    Ctl.Reassert(0);
    AssertTrue('range 1..3 from the native focus',
      SelectionMatches(LV, [1, 2, 3]));
  finally
    Ctl.Free;
    LV.Free;
  end;
end;

procedure TListSelectionControllerTest.SelectOnly_AppliesSingleSelection;
var
  LV: TListView;
  Ctl: TListSelectionController;
begin
  EnsureApp;
  MakeList(LV, Ctl);
  try
    Ctl.SelectOnly(3);
    Ctl.Reassert(0);
    AssertTrue('item 3 only', SelectionMatches(LV, [3]));

    { Out-of-range index cancels instead of selecting nothing. }
    Ctl.SelectOnly(99);
    Ctl.Reassert(0);
    AssertTrue('selection unchanged', SelectionMatches(LV, [3]));
  finally
    Ctl.Free;
    LV.Free;
  end;
end;

procedure TListSelectionControllerTest.ResetAll_DropsAnchorAndPending;
var
  LV: TListView;
  Ctl: TListSelectionController;
begin
  EnsureApp;
  MakeList(LV, Ctl);
  try
    Ctl.Click(2, False, False);   { arms a pending re-assert + anchor 2 }
    Ctl.ResetAll;

    { With the anchor and the pending state gone, a shift+click starts from
      the clicked item instead of the old anchor. }
    Ctl.Click(4, True, False);
    Ctl.Reassert(0);
    AssertTrue('only item 4', SelectionMatches(LV, [4]));
  finally
    Ctl.Free;
    LV.Free;
  end;
end;

initialization
  RegisterTest(TListSelectionControllerTest);
end.
