unit test_udlgpageeditor;

{$mode objfpc}{$H+}

{ Smoke tests for the modal page editor dialog: the whole UI is declared in
  udlgpageeditor.lfm, so creating the dialog offscreen proves the resource
  streams correctly (controls parented, events wired, defaults applied). }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TPageEditorTest = class(TTestCase)
  private
    FAppInitialized: boolean;
    procedure EnsureApp;
  published
    procedure Dialog_StreamsControlsFromLfm;
  end;

implementation

uses
  Forms,
  udlgpageeditor;

{ Initialize the LCL widgetset once, offscreen (make test exports
  QT_QPA_PLATFORM=offscreen).  Forms can only be created after this. }
procedure TPageEditorTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

procedure TPageEditorTest.Dialog_StreamsControlsFromLfm;
var
  Dlg: TdlgPageEditor;
begin
  EnsureApp;
  Dlg := TdlgPageEditor.Create(nil);
  try
    AssertNotNull('page control streamed', Dlg.PageControl);
    AssertEquals('three tool tabs', 3, Dlg.PageControl.PageCount);
    AssertEquals('resize tab', 'Resize', Dlg.PageControl.Pages[0].Caption);
    AssertEquals('colors tab', 'Colors', Dlg.PageControl.Pages[1].Caption);
    AssertEquals('split tab', 'Split', Dlg.PageControl.Pages[2].Caption);
    AssertFalse('tools disabled until the page loads', Dlg.PageControl.Enabled);

    AssertNotNull('preview image streamed', Dlg.ImgPreview);
    AssertNotNull('cut-line paintbox streamed', Dlg.PaintBoxLines);
    AssertNotNull('slices scrollbox streamed', Dlg.ScrollBoxSlices);
    AssertFalse('slices hidden initially', Dlg.ScrollBoxSlices.Visible);
    AssertNotNull('slice panel streamed', Dlg.SlicePanel);

    AssertNotNull('reset button streamed', Dlg.BtnReset);
    AssertFalse('reset disabled until the page loads', Dlg.BtnReset.Enabled);
    AssertFalse('OK disabled until the page loads', Dlg.BtnOk.Enabled);

    AssertNotNull('preview debounce timer streamed', Dlg.TimerPreview);
    AssertEquals('preview debounce interval', 80, Dlg.TimerPreview.Interval);

    AssertEquals('two cut directions', 2, Dlg.RgDirection.Items.Count);
    AssertEquals('default cut position', 50, Dlg.SpinLinePos.Value);
    AssertTrue('aspect lock on by default', Dlg.CbKeepAspect.Checked);
    AssertEquals('max page width', 16384, Dlg.SpinW.MaxValue);

    AssertNotNull('size info label streamed', Dlg.LblResizeInfo);
    AssertEquals('size info placeholder', 'Loading...',
      Dlg.LblResizeInfo.Caption);
  finally
    Dlg.Free;
  end;
end;

initialization
  RegisterTest(TPageEditorTest);
end.
