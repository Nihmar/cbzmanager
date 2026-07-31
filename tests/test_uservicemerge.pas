unit test_uservicemerge;
{$mode objfpc}{$h+}
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TMergeServiceTest = class(TTestCase)
  private
    FTempDir: string;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure DetectSeriesName_SingleChapter;
    procedure DetectSeriesName_MultiChapter;
    procedure DetectSeriesName_NoDash;
    procedure DetectSeriesName_EmptyList;
    procedure DetectSeriesName_ComplexName;

    procedure ExtractChapterNumStr_Plain;
    procedure ExtractChapterNumStr_UnderscoreSuffix;
    procedure ExtractChapterNumStr_LeadingUnderscore;
    procedure ExtractChapterNumStr_Decimal;
    procedure ExtractChapterNumStr_Volume;
    procedure ExtractChapterNumStr_VolumeSuffix;
    procedure ExtractChapterNumStr_NoPattern;
    procedure ExtractChapterNumStr_NonNumericChapter;

    procedure CalcCPV_SymmetricVolumes;
    procedure CalcCPV_NoVolumes;
    procedure CalcCPV_ImpossibleDetect;

    procedure Merge_TwoChapters;
    procedure Merge_DeleteOriginals;
    procedure Merge_NoChapters;
  end;

implementation

uses
  Math,
  uZipEditor,
  uservicebase,
  uservicemerge,
  test_helpers,
  FileUtil;

{ TMergeServiceTest }

procedure TMergeServiceTest.SetUp;
begin
  FTempDir := CreateTempDir('cbzmerge_');
end;

procedure TMergeServiceTest.TearDown;
begin
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
end;

{ DetectSeriesName }

procedure TMergeServiceTest.DetectSeriesName_SingleChapter;
var
  Files: TStringArray;
begin
  SetLength(Files, 1);
  Files[0] := 'Bleach - 001.cbz';
  AssertEquals('Bleach', TMergeService.DetectSeriesName(Files));
end;

procedure TMergeServiceTest.DetectSeriesName_MultiChapter;
var
  Files: TStringArray;
begin
  SetLength(Files, 3);
  Files[0] := 'One Piece - 056.cbz';
  Files[1] := 'One Piece - 057.cbz';
  Files[2] := 'One Piece - 058.cbz';
  AssertEquals('One Piece', TMergeService.DetectSeriesName(Files));
end;

procedure TMergeServiceTest.DetectSeriesName_NoDash;
var
  Files: TStringArray;
begin
  SetLength(Files, 2);
  Files[0] := 'nodash.cbz';
  Files[1] := 'also_nodash.cbz';
  AssertEquals('', TMergeService.DetectSeriesName(Files));
end;

procedure TMergeServiceTest.DetectSeriesName_EmptyList;
var
  Files: TStringArray;
begin
  SetLength(Files, 0);
  AssertEquals('', TMergeService.DetectSeriesName(Files));
end;

procedure TMergeServiceTest.DetectSeriesName_ComplexName;
var
  Files: TStringArray;
begin
  SetLength(Files, 1);
  Files[0] := 'Attack - On - Titan - 12.cbz';
  AssertEquals('Attack - On - Titan', TMergeService.DetectSeriesName(Files));
end;

{ ExtractChapterNumStr }

procedure TMergeServiceTest.ExtractChapterNumStr_Plain;
begin
  AssertEquals('0001', ExtractChapterNumStr('Bleach - 0001.cbz'));
end;

procedure TMergeServiceTest.ExtractChapterNumStr_UnderscoreSuffix;
begin
  { The suffix must be kept so variant/part files stay distinguishable }
  AssertEquals('010_15', ExtractChapterNumStr('Naruto - 010_15.cbz'));
  AssertEquals('042_extra', ExtractChapterNumStr('Manga - 042_extra.cbz'));
end;

procedure TMergeServiceTest.ExtractChapterNumStr_LeadingUnderscore;
begin
  AssertEquals('0002', ExtractChapterNumStr('Series - _0002.cbz'));
end;

procedure TMergeServiceTest.ExtractChapterNumStr_Decimal;
begin
  AssertEquals('010.5', ExtractChapterNumStr('Manga - 010.5.cbz'));
end;

procedure TMergeServiceTest.ExtractChapterNumStr_Volume;
begin
  AssertEquals('V012', ExtractChapterNumStr('Series V012.cbz'));
end;

procedure TMergeServiceTest.ExtractChapterNumStr_VolumeSuffix;
begin
  AssertEquals('V012_extra', ExtractChapterNumStr('Series V012_extra.cbz'));
end;

procedure TMergeServiceTest.ExtractChapterNumStr_NoPattern;
begin
  AssertEquals('', ExtractChapterNumStr('nodash.cbz'));
  AssertEquals('', ExtractChapterNumStr('also_nodash_01.cbz'));
end;

procedure TMergeServiceTest.ExtractChapterNumStr_NonNumericChapter;
begin
  AssertEquals('extra', ExtractChapterNumStr('Series - extra.cbz'));
end;

{ CalculateChaptersPerVolume }

procedure TMergeServiceTest.CalcCPV_SymmetricVolumes;
var
  Files: TStringArray;
begin
  { Chapters 8-14, one existing volume → implies that volume has ch1-7, CPV=7 }
  SetLength(Files, 9);
  Files[0] := 'Series V001.cbz';  { existing volume }
  Files[1] := 'Series - 008.cbz';
  Files[2] := 'Series - 009.cbz';
  Files[3] := 'Series - 010.cbz';
  Files[4] := 'Series - 011.cbz';
  Files[5] := 'Series - 012.cbz';
  Files[6] := 'Series - 013.cbz';
  Files[7] := 'Series - 014.cbz';
  Files[8] := 'other-file.txt';   { non-cbz — should be ignored by CollectCBZFiles
                                      but this function just iterates TStringArray }
  AssertEquals('CPV=(8-1)/1=7', 7, TMergeService.CalculateChaptersPerVolume(Files, 'Series'));
end;

procedure TMergeServiceTest.CalcCPV_NoVolumes;
var
  Files: TStringArray;
begin
  SetLength(Files, 1);
  Files[0] := 'Series - 001.cbz';
  AssertEquals('No volumes → 0', 0, TMergeService.CalculateChaptersPerVolume(Files, 'Series'));
end;

procedure TMergeServiceTest.CalcCPV_ImpossibleDetect;
var
  Files: TStringArray;
begin
  { LowestCh=1, so (1-1) div anything = 0 }
  SetLength(Files, 3);
  Files[0] := 'Series V001.cbz';
  Files[1] := 'Series V002.cbz';
  Files[2] := 'Series - 001.cbz';
  AssertEquals('(1-1)/2=0', 0, TMergeService.CalculateChaptersPerVolume(Files, 'Series'));
end;

{ Merge }

procedure TMergeServiceTest.Merge_TwoChapters;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
  VolPath: string;
begin
  { Create two chapter CBZs }
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - 01.cbz', [Png, Png], ['a.jpg', 'b.jpg']);
  Png.Free;

  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - 02.cbz', [Png], ['c.jpg']);
  Png.Free;

  SetLength(Files, 2);
  Files[0] := 'Test - 01.cbz';
  Files[1] := 'Test - 02.cbz';

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 0;  { auto-CPV → defaults to 7 }
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('1 volume created', 1, Res.VolumesCreated);

  VolPath := FTempDir + 'Test V001.cbz';
  AssertTrue('Volume file exists', FileExists(VolPath));
  AssertEquals('Volume has 3 images', 3, GetImageCount(VolPath));

  { Original renamed to _OLD }
  AssertTrue('Chapter 1 renamed to _OLD',
    FileExists(FTempDir + 'Test - 01_OLD.cbz'));
  AssertTrue('Chapter 2 renamed to _OLD',
    FileExists(FTempDir + 'Test - 02_OLD.cbz'));
end;

procedure TMergeServiceTest.Merge_DeleteOriginals;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
  VolPath: string;
begin
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'DeleteTest - 01.cbz', [Png], ['x.png']);
  Png.Free;

  SetLength(Files, 1);
  Files[0] := 'DeleteTest - 01.cbz';

  Opts.SeriesName := 'DeleteTest';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 7;
  Opts.Force := False;
  Opts.Delete := True;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  VolPath := FTempDir + 'DeleteTest V001.cbz';
  AssertTrue('Volume file exists', FileExists(VolPath));

  { Original should be deleted }
  AssertFalse('Original chapter deleted',
    FileExists(FTempDir + 'DeleteTest - 01.cbz'));
  AssertFalse('No _OLD backup',
    FileExists(FTempDir + 'DeleteTest - 01_OLD.cbz'));
end;

procedure TMergeServiceTest.Merge_NoChapters;
var
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
begin
  SetLength(Files, 0);
  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 7;
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertFalse('No chapters → failure', Res.Success);
  AssertTrue('Error message set', Res.ErrorMsg <> '');
end;

initialization
  RegisterTest(TMergeServiceTest);
end.
