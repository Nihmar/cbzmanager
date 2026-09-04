unit test_mainform;

{$mode objfpc}{$H+}

{ Streaming regression test for the main form: every event handler named
  in main.lfm must exist as a published method of TfrmMain, otherwise the
  program dies at startup with "Error reading ...: Invalid value for
  property" (as happened with LVFiles.OnSelectItem).  Creating the form
  offscreen proves the whole resource streams and the hooks are wired.

  Note: TfrmMain.FormCreate auto-loads ParamStr(1) as a directory when the
  process has arguments.  The suite always runs as `testrunner --all`, so
  that resolves to a nonexistent path: the loader finds zero files, spawns
  no workers and self-frees without touching the form. }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TMainFormTest = class(TTestCase)
  private
    FAppInitialized: boolean;
    procedure EnsureApp;
  published
    procedure MainForm_StreamsSelectionHooks;
  end;

implementation

uses
  Forms,
  main;

procedure TMainFormTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

procedure TMainFormTest.MainForm_StreamsSelectionHooks;
var
  F: TfrmMain;
begin
  EnsureApp;
  F := TfrmMain.Create(nil);
  try
    AssertTrue('files select hook wired', Assigned(F.LVFiles.OnSelectItem));
    AssertTrue('pages select hook wired', Assigned(F.LVPages.OnSelectItem));
    AssertTrue('files mouse hook wired', Assigned(F.LVFiles.OnMouseDown));
    AssertTrue('pages mouse hook wired', Assigned(F.LVPages.OnMouseDown));
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TMainFormTest);
end.
