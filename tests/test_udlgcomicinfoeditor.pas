unit test_udlgcomicinfoeditor;

{$mode objfpc}{$H+}

{ Smoke tests for the ComicInfo editor dialog: the whole four-tab UI is
  declared in udlgcomicinfoeditor.lfm, so creating the dialog offscreen
  proves the resource streams correctly. }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TDlgComicInfoEditorTest = class(TTestCase)
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
  udlgcomicinfoeditor;

procedure TDlgComicInfoEditorTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

procedure TDlgComicInfoEditorTest.Dialog_StreamsControlsFromLfm;
var
  Dlg: TdlgComicInfoEditor;
begin
  EnsureApp;
  Dlg := TdlgComicInfoEditor.Create(nil);
  try
    AssertNotNull('tab control streamed', Dlg.Pages);
    AssertEquals('four editor tabs', 4, Dlg.Pages.PageCount);
    AssertEquals('general tab', 'General', Dlg.Pages.Pages[0].Caption);
    AssertEquals('story tab', 'Story', Dlg.Pages.Pages[1].Caption);
    AssertEquals('credits tab', 'Credits', Dlg.Pages.Pages[2].Caption);
    AssertEquals('publishing tab', 'Publishing', Dlg.Pages.Pages[3].Caption);

    AssertNotNull('series edit streamed', Dlg.EdSeries);
    AssertNotNull('summary memo streamed', Dlg.MemoSummary);
    AssertNotNull('writer edit streamed', Dlg.EdWriter);

    AssertNotNull('manga combo streamed', Dlg.CbManga);
    AssertEquals('five manga choices', 5, Dlg.CbManga.Items.Count);
    AssertNotNull('age-rating combo streamed', Dlg.CbAgeRating);
    AssertEquals('sixteen rating choices', 16, Dlg.CbAgeRating.Items.Count);
    AssertNotNull('community rating spin streamed', Dlg.SpCommunityRating);
    AssertEquals('rating decimals', 1, Dlg.SpCommunityRating.DecimalPlaces);
    AssertEquals('rating step', 0.5, Dlg.SpCommunityRating.Increment);

    AssertNotNull('remove button streamed', Dlg.BtnRemove);
    AssertFalse('remove disabled until a file loads', Dlg.BtnRemove.Enabled);
    AssertNotNull('save button streamed', Dlg.BtnSave);
    AssertEquals('save is default', mrOK, Dlg.BtnSave.ModalResult);
    AssertTrue('backup on by default', Dlg.CbBackup.Checked);
  finally
    Dlg.Free;
  end;
end;

initialization
  RegisterTest(TDlgComicInfoEditorTest);
end.
