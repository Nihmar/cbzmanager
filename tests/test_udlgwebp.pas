unit test_udlgwebp;

{$mode objfpc}{$H+}

{ Smoke tests for the WebP conversion dialog (udlgwebp.lfm streaming). }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TDlgWebpTest = class(TTestCase)
  private
    FAppInitialized: boolean;
    procedure EnsureApp;
  published
    procedure Dialog_StreamsControlsFromLfm;
  end;

implementation

uses
  Forms,
  udlgwebp;

procedure TDlgWebpTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

procedure TDlgWebpTest.Dialog_StreamsControlsFromLfm;
var
  Dlg: TdlgWebp;
begin
  EnsureApp;
  Dlg := TdlgWebp.Create(nil);
  try
    AssertNotNull('quality trackbar streamed', Dlg.TrackQuality);
    AssertEquals('quality min', 30, Dlg.TrackQuality.Min);
    AssertEquals('quality max', 100, Dlg.TrackQuality.Max);
    AssertEquals('quality default', 75, Dlg.TrackQuality.Position);
    AssertNotNull('quality value label streamed', Dlg.LblQualityVal);
    AssertEquals('quality value label', '75%', Dlg.LblQualityVal.Caption);
    AssertNotNull('smaller-only checkbox streamed', Dlg.CbReplaceOnlySmaller);
    AssertTrue('smaller-only on by default', Dlg.CbReplaceOnlySmaller.Checked);
    AssertNotNull('backup group streamed', Dlg.GroupBackup);
    AssertEquals('two backup modes', 2, Dlg.GroupBackup.Items.Count);
    AssertEquals('backup default', 0, Dlg.GroupBackup.ItemIndex);
    AssertNotNull('threads spin streamed', Dlg.SpinThreads);
    AssertEquals('threads default (auto)', 0, Dlg.SpinThreads.Value);
    AssertNotNull('convert button streamed', Dlg.BtnConvert);
  finally
    Dlg.Free;
  end;
end;

initialization
  RegisterTest(TDlgWebpTest);
end.
