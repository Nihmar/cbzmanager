unit test_udlgbatchedit;

{$mode objfpc}{$H+}

{ Smoke tests for the batch edit dialog: the whole UI is declared in
  udlgbatchedit.lfm, so creating the dialog offscreen proves the resource
  streams correctly and the parameters round-trip through ExtractParams. }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TDlgBatchEditTest = class(TTestCase)
  private
    FAppInitialized: boolean;
    FTempDir: string;
    procedure EnsureApp;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Dialog_StreamsControlsFromLfm;
    procedure Dialog_CollectsParams;
  end;

implementation

uses
  Forms,
  udlgbatchedit,
  ubatchedit,
  FileUtil,
  test_helpers;

procedure TDlgBatchEditTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

procedure TDlgBatchEditTest.SetUp;
begin
  FTempDir := CreateTempDir('cbzbedlg_');
  EnsureApp;
end;

procedure TDlgBatchEditTest.TearDown;
begin
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
end;

procedure TDlgBatchEditTest.Dialog_StreamsControlsFromLfm;
var
  Dlg: TdlgBatchEdit;
begin
  Dlg := TdlgBatchEdit.Create(nil);
  try
    AssertNotNull('resize checkbox streamed', Dlg.CbResize);
    AssertNotNull('scale spin streamed', Dlg.SpinPercent);
    AssertFalse('scale disabled until resize is checked',
      Dlg.SpinPercent.Enabled);
    AssertEquals('scale default', 100, Dlg.SpinPercent.Value);
    AssertNotNull('brightness trackbar streamed', Dlg.TrackBrightness);
    AssertNotNull('saturation trackbar streamed', Dlg.TrackSaturation);
    AssertNotNull('tab control streamed', Dlg.PageControl);
    AssertEquals('three tool tabs', 3, Dlg.PageControl.PageCount);
    AssertEquals('resize tab', 'Resize', Dlg.PageControl.Pages[0].Caption);
    AssertEquals('colors tab', 'Colors', Dlg.PageControl.Pages[1].Caption);
    AssertEquals('split tab', 'Split', Dlg.PageControl.Pages[2].Caption);
    AssertNotNull('cut direction streamed', Dlg.RgDirection);
    AssertEquals('two directions', 2, Dlg.RgDirection.Items.Count);
    AssertNotNull('cut line list streamed', Dlg.LBLines);
    AssertEquals('line position default', 50, Dlg.SpinLinePos.Value);
    AssertNotNull('preview streamed', Dlg.ImgPreview);
    AssertNotNull('preview timer streamed', Dlg.TimerPreview);
    AssertEquals('debounce interval', 80, Dlg.TimerPreview.Interval);
    AssertNotNull('apply button streamed', Dlg.BtnApply);
  finally
    Dlg.Free;
  end;
end;

procedure TDlgBatchEditTest.Dialog_CollectsParams;
var
  Dlg: TdlgBatchEdit;
  Input: TMultiEditPageInput;
  P: TMultiEditParams;
begin
  Dlg := TdlgBatchEdit.Create(nil);
  try
    Input.OrigName := 'page_0001.png';
    Input.Data := nil;
    Input.Ext := '.png';
    { Missing file: the preview degrades gracefully but the dialog lives. }
    Dlg.LoadTarget(FTempDir + 'nope.cbz', Input, 3);

    AssertTrue('defaults are neutral', ParamsAreNeutral(Dlg.ExtractParams));

    Dlg.CbResize.Checked := True;
    Dlg.SpinPercent.Value := 150;
    Dlg.CbGray.Checked := True;
    Dlg.SpinLinePos.Value := 50;
    Dlg.BtnAddLineClick(nil);
    AssertEquals('one cut line listed', 1, Dlg.LBLines.Items.Count);

    P := Dlg.ExtractParams;
    AssertTrue('resize collected', P.Resize);
    AssertEquals('percent collected', 150, P.Percent);
    AssertTrue('grayscale collected', P.Adj.Grayscale);
    AssertTrue('split collected', P.Split);
    AssertEquals('one split line', 1, Length(P.Lines));
    AssertTrue('split at 50%', Abs(P.Lines[0] - 0.5) < 0.001);
    AssertFalse('not neutral anymore', ParamsAreNeutral(P));
  finally
    Dlg.Free;
  end;
end;

initialization
  RegisterTest(TDlgBatchEditTest);
end.
