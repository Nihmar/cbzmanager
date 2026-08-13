unit test_udlgvalidate;

{$mode objfpc}{$H+}

{ Smoke tests for the validation-results dialog (udlgvalidate.lfm
  streaming, incl. the report-view columns). }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TDlgValidateTest = class(TTestCase)
  private
    FAppInitialized: boolean;
    procedure EnsureApp;
  published
    procedure Dialog_StreamsControlsFromLfm;
  end;

implementation

uses
  ComCtrls,
  System.UITypes,
  Forms,
  udlgvalidate;

procedure TDlgValidateTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

procedure TDlgValidateTest.Dialog_StreamsControlsFromLfm;
var
  Dlg: TdlgValidate;
begin
  EnsureApp;
  Dlg := TdlgValidate.Create(nil);
  try
    AssertNotNull('result list streamed', Dlg.LVResult);
    AssertEquals('four report columns', 4, Dlg.LVResult.Columns.Count);
    AssertEquals('file column', 'File', Dlg.LVResult.Columns[0].Caption);
    AssertTrue('file column auto-sizes', Dlg.LVResult.Columns[0].AutoSize);
    AssertEquals('note column', 'Note', Dlg.LVResult.Columns[3].Caption);
    AssertTrue('report style', Dlg.LVResult.ViewStyle = vsReport);
    AssertTrue('read-only rows', Dlg.LVResult.ReadOnly);
    AssertNotNull('close button streamed', Dlg.BtnClose);
    AssertEquals('close is default', mrOK, Dlg.BtnClose.ModalResult);
    AssertTrue('close is cancel', Dlg.BtnClose.Cancel);
  finally
    Dlg.Free;
  end;
end;

initialization
  RegisterTest(TDlgValidateTest);
end.
