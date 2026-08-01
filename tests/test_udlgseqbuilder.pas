unit test_udlgseqbuilder;
{$mode objfpc}{$h+}
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TSeqBuilderTest = class(TTestCase)
  private
    FTempDir: string;
    FAppInitialized: boolean;
    procedure EnsureApp;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure SeqBuilder_PreviewDblClickLoads;
    procedure SeqBuilder_FrontConsumptionRejectsGap;
    procedure SeqBuilder_SequenceReflectsVolumes;
    procedure MergeDlg_CustomSeqPreview;
    procedure CustomLabels_EmptyAndOverflow;
  end;

implementation

uses
  Forms,
  Controls,
  ComCtrls,
  IntfGraphics,
  uzipcore,
  uZipEditor,
  uimgutil,
  uloaderthread,
  udlgmerge,
  udlgseqbuilder,
  uservicemerge,
  test_helpers,
  FileUtil;

{ TSeqBuilderTest }

procedure TSeqBuilderTest.SetUp;
begin
  FTempDir := CreateTempDir('cbzseq_');
  EnsureApp;
end;

procedure TSeqBuilderTest.TearDown;
begin
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
end;

{ Initialize the LCL widgetset once, offscreen (make test exports
  QT_QPA_PLATFORM=offscreen).  Forms can only be created after this. }
procedure TSeqBuilderTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

function MakeChapterCBZ(const ADir, AName: string): string;
var
  Png: TMemoryStream;
begin
  Result := ADir + AName;
  Png := CreateMinimalPNGStream;
  CreateCBZ(Result, [Png], ['p1.png']);
  Png.Free;
end;

procedure TSeqBuilderTest.SeqBuilder_PreviewDblClickLoads;
var
  Builder: TdlgSeqBuilder;
  Images: TLazIntfImageList;
  Img: TLazIntfImage;
  Files: TStringArray;
  Idx: TIntArray;
  i: integer;
  Path: string;
begin
  { Regression: double-clicking a chapter must load its preview without
    raising (the preview-loader lifecycle used to race and crash). }
  Path := MakeChapterCBZ(FTempDir, 'ch.cbz');
  SetLength(Files, 1);
  Files[0] := 'ch.cbz';
  Images := TLazIntfImageList.Create(True);
  Img := GetFirstImageAsIntfImage(Path);
  Images.Add(Img);   { may be nil for undecodable files — fine }
  SetLength(Idx, 1);
  Idx[0] := 0;

  Builder := TdlgSeqBuilder.Create(nil);
  try
    Builder.LoadChapters(Files, Images, Idx, FTempDir);
    AssertEquals('1 row', 1, Builder.LVChapters.Items.Count);
    Builder.LVChapters.Items[0].Selected := True;
    Builder.LVChapters.Selected := Builder.LVChapters.Items[0];
    Builder.LVChaptersDblClick(nil);
    { Wait for the preview thread (OnTerminate is delivered via the main
      message loop). }
    for i := 1 to 50 do
    begin
      Application.ProcessMessages;
      if Pos('1 / 1', Builder.LblPreviewPage.Caption) > 0 then Break;
      Sleep(100);
    end;
    AssertTrue('preview loaded', Pos('1 / 1', Builder.LblPreviewPage.Caption) > 0);
    AssertEquals('preview title', 'ch', Builder.LblPreviewTitle.Caption);
  finally
    Builder.Free;
    Images.Free;
  end;
end;

procedure TSeqBuilderTest.SeqBuilder_FrontConsumptionRejectsGap;
var
  Builder: TdlgSeqBuilder;
  Images: TLazIntfImageList;
  Files: TStringArray;
  Idx: TIntArray;
  i: integer;
begin
  { Volumes are assembled in list order, so only selections covering
    exactly the first N chapters are accepted.  The rule is a pure
    function (the offscreen widgetset cannot drive multi-selection). }
  Builder := TdlgSeqBuilder.Create(nil);
  try
    AssertTrue('front block ok',
      Builder.IsFrontBlockSelection([True, True, False], 2));
    AssertTrue('all selected ok',
      Builder.IsFrontBlockSelection([True, True, True], 3));
    AssertFalse('gap (items 1..2) rejected',
      Builder.IsFrontBlockSelection([False, True, True], 2));
    AssertFalse('hole (item 0 unselected) rejected',
      Builder.IsFrontBlockSelection([False, True, False], 2));
    AssertFalse('extra selection rejected',
      Builder.IsFrontBlockSelection([True, True, True], 2));
    AssertFalse('zero rejected',
      Builder.IsFrontBlockSelection([True, True], 0));
  finally
    Builder.Free;
  end;
end;

procedure TSeqBuilderTest.SeqBuilder_SequenceReflectsVolumes;
var
  Builder: TdlgSeqBuilder;
  Images: TLazIntfImageList;
  Files: TStringArray;
  Idx: TIntArray;
  i: integer;
begin
  for i := 1 to 5 do
    MakeChapterCBZ(FTempDir, Format('c%.2d.cbz', [i]));
  SetLength(Files, 5);
  for i := 1 to 5 do
    Files[i - 1] := Format('c%.2d.cbz', [i]);
  Images := TLazIntfImageList.Create(True);
  for i := 0 to 4 do
    Images.Add(GetFirstImageAsIntfImage(FTempDir + Files[i]));
  SetLength(Idx, 5);
  for i := 0 to 4 do
    Idx[i] := i;

  Builder := TdlgSeqBuilder.Create(nil);
  try
    Builder.LoadChapters(Files, Images, Idx, FTempDir);
    { Vol.1: first 2, Vol.2: next 3 (front-consumption via AddVolume) }
    Builder.AddVolume(2);
    Builder.AddVolume(3);
    AssertEquals('2 volumes', 2, Length(Builder.GetSequence));
    AssertEquals('vol 1 = 2', 2, Builder.GetSequence[0]);
    AssertEquals('vol 2 = 3', 3, Builder.GetSequence[1]);
    AssertTrue('sequence shows chapters of vol.1',
      Pos('c01, c02', Builder.CbSequence.Items[0]) > 0);
    AssertTrue('all chapters assigned shown',
      Pos('all assigned', Builder.CbSequence.Items[2]) > 0);
  finally
    Builder.Free;
    Images.Free;
  end;
end;

procedure TSeqBuilderTest.MergeDlg_CustomSeqPreview;
var
  Dlg: TdlgMerge;
  Files: TStringArray;
  Labels: TStringArray;
  i: integer;
begin
  { The merge dialog's Volume column must reflect the custom sequence
    written by the builder (the coherence regression: the preview used to
    keep showing the CPV-based assignment).  The plumbing is verified via
    the public ChaptersList property; the labeling via the shared pure
    function CustomSequenceLabels. }
  for i := 1 to 4 do
    MakeChapterCBZ(FTempDir, Format('Test - %.2d.cbz', [i]));
  MakeChapterCBZ(FTempDir, 'Test V001.cbz');       { volume — not a chapter }
  MakeChapterCBZ(FTempDir, 'Test - 0001_OLD.cbz'); { backup — not a chapter }
  MakeChapterCBZ(FTempDir, 'Other - 0001.cbz');    { other series — ignored }

  SetLength(Files, 7);
  Files[0] := 'Test - 01.cbz';
  Files[1] := 'Test - 02.cbz';
  Files[2] := 'Test - 03.cbz';
  Files[3] := 'Test - 04.cbz';
  Files[4] := 'Test V001.cbz';
  Files[5] := 'Test - 0001_OLD.cbz';
  Files[6] := 'Other - 0001.cbz';

  Dlg := TdlgMerge.Create(nil);
  try
    Dlg.LoadChapters(Files, FTempDir, 'Test');
    { Custom sequence off by default: no chapters list }
    AssertEquals('no custom sequence by default', 0,
      Length(Dlg.ChaptersList));
    Dlg.CbCustomSeq.Checked := True;
    Dlg.MemoChapterSequence.Text := '2,1';
    AssertEquals('chapters list parsed from memo', 2, Length(Dlg.ChaptersList));
    AssertEquals('vol.1 count', 2, Dlg.ChaptersList[0]);
    AssertEquals('vol.2 count', 1, Dlg.ChaptersList[1]);
    { 4 chapter rows, sequence 2,1 -> Vol.1, Vol.1, Vol.2, '-' }
    Labels := CustomSequenceLabels(4, Dlg.ChaptersList, 0);
    AssertEquals('row 1 -> Vol.1', 'Vol.1', Labels[0]);
    AssertEquals('row 2 -> Vol.1', 'Vol.1', Labels[1]);
    AssertEquals('row 3 -> Vol.2', 'Vol.2', Labels[2]);
    AssertEquals('row 4 unassigned', '-', Labels[3]);
    { Volume numbering continues after existing volumes }
    Labels := CustomSequenceLabels(4, Dlg.ChaptersList, 3);
    AssertEquals('continues after V003', 'Vol.4', Labels[0]);
  finally
    Dlg.Free;
  end;
end;

procedure TSeqBuilderTest.CustomLabels_EmptyAndOverflow;
var
  Labels: TStringArray;
  Seq: TIntArray;
begin
  { Empty sequence -> '?' everywhere }
  Seq := nil;
  Labels := CustomSequenceLabels(3, Seq, 0);
  AssertEquals('3 rows', 3, Length(Labels));
  AssertEquals('?', '?', Labels[0]);
  AssertEquals('?', '?', Labels[2]);
  { Overflowing batch is skipped entirely (service parity) }
  SetLength(Seq, 2);
  Seq[0] := 2;
  Seq[1] := 5;
  Labels := CustomSequenceLabels(6, Seq, 0);
  AssertEquals('Vol.1', 'Vol.1', Labels[0]);
  AssertEquals('Vol.1', 'Vol.1', Labels[1]);
  AssertEquals('overflow rows unassigned', '-', Labels[2]);
  AssertEquals('-', '-', Labels[5]);
end;

initialization
  RegisterTest(TSeqBuilderTest);
end.
