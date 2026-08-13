unit test_udlgvalidateopts;

{$mode objfpc}{$H+}

{ Smoke tests for the validation options dialog (udlgvalidateopts.lfm
  streaming). }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TDlgValidateOptsTest = class(TTestCase)
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
  udlgvalidateopts;

procedure TDlgValidateOptsTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

procedure TDlgValidateOptsTest.Dialog_StreamsControlsFromLfm;
var
  Dlg: TdlgValidateOpts;
begin
  EnsureApp;
  Dlg := TdlgValidateOpts.Create(nil);
  try
    AssertEquals('dialog caption', 'Validate CBZ files', Dlg.Caption);
    AssertNotNull('threads spin streamed', Dlg.SpinThreads);
    AssertEquals('threads max', 32, Dlg.SpinThreads.MaxValue);
    AssertEquals('threads default (auto)', 0, Dlg.SpinThreads.Value);
    AssertNotNull('validate button streamed', Dlg.BtnValidate);
    AssertEquals('validate is default', mrOK, Dlg.BtnValidate.ModalResult);
    AssertNotNull('cancel button streamed', Dlg.BtnCancel);
    AssertTrue('cancel is cancel', Dlg.BtnCancel.Cancel);
  finally
    Dlg.Free;
  end;
end;

initialization
  RegisterTest(TDlgValidateOptsTest);
end.
