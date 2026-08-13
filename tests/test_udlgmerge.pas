unit test_udlgmerge;

{$mode objfpc}{$H+}

{ Smoke tests for the merge dialog: LVFiles is declared in udlgmerge.lfm
  (inside PanelRight, with its three columns), so creating the dialog
  offscreen proves that part of the resource streams correctly. }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TDlgMergeTest = class(TTestCase)
  private
    FAppInitialized: boolean;
    procedure EnsureApp;
  published
    procedure Dialog_StreamsControlsFromLfm;
  end;

implementation

uses
  Forms,
  udlgmerge;

procedure TDlgMergeTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

procedure TDlgMergeTest.Dialog_StreamsControlsFromLfm;
var
  Dlg: TdlgMerge;
begin
  EnsureApp;
  Dlg := TdlgMerge.Create(nil);
  try
    AssertNotNull('chapter list streamed', Dlg.LVFiles);
    AssertSame('chapter list parented to the right panel', Dlg.PanelRight,
      Dlg.LVFiles.Parent);
    AssertEquals('three report columns', 3, Dlg.LVFiles.Columns.Count);
    AssertEquals('chapter column', 'Chapter file',
      Dlg.LVFiles.Columns[1].Caption);
    AssertTrue('chapter column auto-sizes', Dlg.LVFiles.Columns[1].AutoSize);
    AssertNotNull('manual CPV edit streamed', Dlg.EditCPV);
    AssertFalse('manual CPV disabled initially', Dlg.EditCPV.Enabled);
    AssertNotNull('sequence builder button streamed', Dlg.BtnBuildSeq);
    AssertFalse('sequence builder disabled initially', Dlg.BtnBuildSeq.Enabled);
  finally
    Dlg.Free;
  end;
end;

initialization
  RegisterTest(TDlgMergeTest);
end.
