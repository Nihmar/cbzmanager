unit test_udlgcbr;

{$mode objfpc}{$H+}

{ Smoke tests for the CBR-to-CBZ conversion dialog: the whole UI is
  declared in udlgcbr.lfm, so creating the dialog offscreen proves the
  resource streams correctly. }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TDlgCbrTest = class(TTestCase)
  private
    FAppInitialized: boolean;
    procedure EnsureApp;
  published
    procedure Dialog_StreamsControlsFromLfm;
  end;

implementation

uses
  System.UITypes,
  Forms,
  udlgcbr;

procedure TDlgCbrTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

procedure TDlgCbrTest.Dialog_StreamsControlsFromLfm;
var
  Dlg: TdlgCbr;
begin
  EnsureApp;
  Dlg := TdlgCbr.Create(nil);
  try
    AssertNotNull('skip-existing checkbox streamed', Dlg.CbSkipExisting);
    AssertTrue('skip existing on by default', Dlg.CbSkipExisting.Checked);
    AssertNotNull('delete-source checkbox streamed', Dlg.CbDeleteSource);
    AssertFalse('delete source off by default', Dlg.CbDeleteSource.Checked);
    AssertNotNull('threads spin streamed', Dlg.SpinThreads);
    AssertEquals('threads max', 32, Dlg.SpinThreads.MaxValue);
    AssertEquals('threads default (auto)', 0, Dlg.SpinThreads.Value);
    AssertNotNull('convert button streamed', Dlg.BtnConvert);
    AssertEquals('convert is default', mrOK, Dlg.BtnConvert.ModalResult);
    AssertNotNull('cancel button streamed', Dlg.BtnClose);
    AssertTrue('cancel is cancel', Dlg.BtnClose.Cancel);
  finally
    Dlg.Free;
  end;
end;

initialization
  RegisterTest(TDlgCbrTest);
end.
