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

    procedure IsVolumeFile_Basic;
    procedure IsVolumeFile_SuffixRejected;
    procedure IsVolumeFile_OtherKinds;

    procedure IsChapterFile_Numeric;
    procedure IsChapterFile_Suffixed;
    procedure IsChapterFile_Special;
    procedure IsChapterFile_Rejected;

    procedure CollectChapters_FiltersAndSorts;
    procedure CollectChapters_SpecialNumbering;

    procedure CalcCPV_SymmetricVolumes;
    procedure CalcCPV_NoVolumes;
    procedure CalcCPV_ImpossibleDetect;
    procedure CalcCPV_IgnoresBackups;
    procedure CalcCPV_VolumesOnly;
    procedure CalcCPVFloat_Irregular;

    procedure LastVolumeNumber_None;
    procedure LastVolumeNumber_Mixed;
    procedure LastVolumeNumber_SuffixNotCounted;
    procedure LastVolumeNumber_EmptySeries;
    procedure LastVolumeNumber_OtherSeries;

    procedure Merge_BelowThresholdNoVolume;
    procedure Merge_DeleteOriginals;
    procedure Merge_NoChapters;
    procedure Merge_ChapterZeroIncluded;
    procedure Merge_ContinuesFromLastVolume;
    procedure Merge_ForceAbsorbsRemainder;
    procedure Merge_ForceOffLeavesRemainder;
    procedure Merge_InsufficientChapters;
    procedure Merge_NoVolumesDefaultCPV;
    procedure Merge_SpecialsWithManualCPV;
    procedure Merge_IrregularVolumes;
    procedure Merge_BelowFloatThreshold;
    procedure Merge_ExistingVolumesUntouched;
    procedure Merge_RollbackOnError;
    procedure Merge_OldBackupsNotReMerged;
    procedure Merge_CustomSeqOverflowSkipsBatch;
    procedure Merge_OtherSeriesUntouched;
    procedure Merge_ResumesAfterVolumes;
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

{ IsVolumeFile }

procedure TMergeServiceTest.IsVolumeFile_Basic;
begin
  AssertTrue('V001', IsVolumeFile('Series V001.cbz', 'Series'));
  AssertTrue('V12 (no padding)', IsVolumeFile('Series V12.cbz', 'Series'));
  AssertTrue('V0001', IsVolumeFile('Series V0001.cbz', 'Series'));
end;

procedure TMergeServiceTest.IsVolumeFile_SuffixRejected;
begin
  { A _OLD backup of a volume is not a volume (mirrors Python _VOLUME_RE). }
  AssertFalse('_OLD rejected', IsVolumeFile('Series V001_OLD.cbz', 'Series'));
  AssertFalse('_extra rejected', IsVolumeFile('Series V001_extra.cbz', 'Series'));
end;

procedure TMergeServiceTest.IsVolumeFile_OtherKinds;
begin
  AssertFalse('chapter is not a volume',
    IsVolumeFile('Series - 001.cbz', 'Series'));
  AssertFalse('other series not counted',
    IsVolumeFile('Other V001.cbz', 'Series'));
  AssertFalse('empty series name', IsVolumeFile('Series V001.cbz', ''));
end;

{ IsChapterFile }

procedure TMergeServiceTest.IsChapterFile_Numeric;
var
  Series: string;
  Num: integer;
  Special: boolean;
begin
  AssertTrue('plain chapter',
    IsChapterFile('Series - 0001.cbz', Series, Num, Special));
  AssertEquals('series', 'Series', Series);
  AssertEquals('number', 1, Num);
  AssertFalse('not special', Special);
end;

procedure TMergeServiceTest.IsChapterFile_Suffixed;
var
  Series: string;
  Num: integer;
  Special: boolean;
begin
  AssertTrue('sub-chapter suffix',
    IsChapterFile('Series - 010_15.cbz', Series, Num, Special));
  AssertEquals('integer part only', 10, Num);
  AssertTrue('multiple suffixes',
    IsChapterFile('Series - 010_15_2.cbz', Series, Num, Special));
  AssertEquals('integer part only', 10, Num);
end;

procedure TMergeServiceTest.IsChapterFile_Special;
var
  Series: string;
  Num: integer;
  Special: boolean;
begin
  AssertTrue('SP01', IsChapterFile('Series - SP01.cbz', Series, Num, Special));
  AssertEquals('series', 'Series', Series);
  AssertEquals('number 0 for special', 0, Num);
  AssertTrue('special flag', Special);
  AssertTrue('Omake', IsChapterFile('Series - Omake.cbz', Series, Num, Special));
  AssertTrue('special flag', Special);
  AssertTrue('SP01 with sub-suffix',
    IsChapterFile('Series - SP01_0001.cbz', Series, Num, Special));
  AssertTrue('special flag', Special);
end;

procedure TMergeServiceTest.IsChapterFile_Rejected;
var
  Series: string;
  Num: integer;
  Special: boolean;
begin
  { _OLD backups are not chapters (mirrors Python regexes). }
  AssertFalse('_OLD chapter rejected',
    IsChapterFile('Series - 0001_OLD.cbz', Series, Num, Special));
  AssertFalse('_OLD alpha tag rejected',
    IsChapterFile('Series - extra_OLD.cbz', Series, Num, Special));
  { Decimal chapters are not Python chapter patterns. }
  AssertFalse('decimal rejected',
    IsChapterFile('Series - 010.5.cbz', Series, Num, Special));
  { Leading-underscore and other malformed tags are rejected. }
  AssertFalse('leading underscore rejected',
    IsChapterFile('Series - _0002.cbz', Series, Num, Special));
  { Volumes and non-chapter names are rejected. }
  AssertFalse('volume rejected',
    IsChapterFile('Series V001.cbz', Series, Num, Special));
  AssertFalse('no dash rejected',
    IsChapterFile('nodash.cbz', Series, Num, Special));
end;

{ CollectChapters }

procedure TMergeServiceTest.CollectChapters_FiltersAndSorts;
var
  Files: TStringArray;
  Ch: TChapterArray;
begin
  SetLength(Files, 6);
  Files[0] := 'Manga - 0003.cbz';
  Files[1] := 'Manga V001.cbz';        { volume — ignored }
  Files[2] := 'Manga - 0001_OLD.cbz';  { backup — ignored }
  Files[3] := 'Manga - 0002.cbz';
  Files[4] := 'Other - 0005.cbz';      { other series — ignored }
  Files[5] := 'Manga - 0001.cbz';
  Ch := TMergeService.CollectChapters(Files, 'Manga');
  AssertEquals('3 chapters of Manga', 3, Length(Ch));
  AssertEquals('first', 'Manga - 0001.cbz', Ch[0].FileName);
  AssertEquals(1, Ch[0].Number);
  AssertEquals('second', 'Manga - 0002.cbz', Ch[1].FileName);
  AssertEquals(2, Ch[1].Number);
  AssertEquals('third', 'Manga - 0003.cbz', Ch[2].FileName);
  AssertEquals(3, Ch[2].Number);
end;

procedure TMergeServiceTest.CollectChapters_SpecialNumbering;
var
  Files: TStringArray;
  Ch: TChapterArray;
begin
  SetLength(Files, 4);
  Files[0] := 'Manga - 0002.cbz';
  Files[1] := 'Manga - SP02.cbz';
  Files[2] := 'Manga - 0001.cbz';
  Files[3] := 'Manga - SP01.cbz';
  Ch := TMergeService.CollectChapters(Files, 'Manga');
  AssertEquals('all 4 collected', 4, Length(Ch));
  { Specials get numbers after the highest regular chapter, in filename
    order: SP01 → 3, SP02 → 4 (mirrors the Python reference). }
  AssertEquals('Manga - 0001.cbz', Ch[0].FileName);
  AssertEquals(1, Ch[0].Number);
  AssertEquals('Manga - 0002.cbz', Ch[1].FileName);
  AssertEquals(2, Ch[1].Number);
  AssertEquals('Manga - SP01.cbz', Ch[2].FileName);
  AssertEquals(3, Ch[2].Number);
  AssertTrue(Ch[2].IsSpecial);
  AssertEquals('Manga - SP02.cbz', Ch[3].FileName);
  AssertEquals(4, Ch[3].Number);
  AssertTrue(Ch[3].IsSpecial);
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
  Files[8] := 'other-file.txt';   { not a chapter — ignored by classification }
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

procedure TMergeServiceTest.CalcCPV_IgnoresBackups;
var
  Files: TStringArray;
begin
  { _OLD chapter backups and _OLD volumes must not distort the estimate:
    lowest real chapter is 8 over 2 real volumes → CPV=3, not 0. }
  SetLength(Files, 5);
  Files[0] := 'Series V001.cbz';
  Files[1] := 'Series V002.cbz';
  Files[2] := 'Series - 0001_OLD.cbz';  { backup — must not lower the bound }
  Files[3] := 'Series - 0008.cbz';
  Files[4] := 'Series - 0009.cbz';
  AssertEquals('CPV=(8-1)/2=3', 3, TMergeService.CalculateChaptersPerVolume(Files, 'Series'));
end;

procedure TMergeServiceTest.CalcCPV_VolumesOnly;
var
  Files: TStringArray;
begin
  { A fully-merged folder (volumes present, no chapters left) must not
    produce a nonsense huge CPV — it returns 0 so the caller falls back
    to the default. }
  SetLength(Files, 2);
  Files[0] := 'Series V001.cbz';
  Files[1] := 'Series V002.cbz';
  AssertEquals('No chapters → 0', 0,
    TMergeService.CalculateChaptersPerVolume(Files, 'Series'));
end;

procedure TMergeServiceTest.CalcCPVFloat_Irregular;
var
  Files: TStringArray;
begin
  { 4 volumes covering chapters 1..15 → CPV = 15/4 = 3.75 (Python REAL
    division); the integer wrapper truncates to 3. }
  SetLength(Files, 6);
  Files[0] := 'Series V001.cbz';
  Files[1] := 'Series V002.cbz';
  Files[2] := 'Series V003.cbz';
  Files[3] := 'Series V004.cbz';
  Files[4] := 'Series - 0016.cbz';
  Files[5] := 'Series - 0017.cbz';
  AssertEquals(3.75,
    TMergeService.CalculateChaptersPerVolumeFloat(Files, 'Series'));
  AssertEquals('integer wrapper truncates', 3,
    TMergeService.CalculateChaptersPerVolume(Files, 'Series'));
end;

{ LastVolumeNumber }

procedure TMergeServiceTest.LastVolumeNumber_None;
var
  Files: TStringArray;
begin
  SetLength(Files, 2);
  Files[0] := 'Series - 008.cbz';
  Files[1] := 'Series - 009.cbz';
  AssertEquals('No volumes', 0, TMergeService.LastVolumeNumber(Files, 'Series'));
end;

procedure TMergeServiceTest.LastVolumeNumber_Mixed;
var
  Files: TStringArray;
begin
  SetLength(Files, 5);
  Files[0] := 'Series V001.cbz';
  Files[1] := 'Series V002.cbz';
  Files[2] := 'Series V003.cbz';
  Files[3] := 'Series - 010.cbz';
  Files[4] := 'Series - 011.cbz';
  AssertEquals('Highest volume is 3', 3,
    TMergeService.LastVolumeNumber(Files, 'Series'));
end;

procedure TMergeServiceTest.LastVolumeNumber_SuffixNotCounted;
var
  Files: TStringArray;
begin
  { Only strict "Series VNNN.cbz" names count — backups and suffixed files
    must not advance the numbering (mirrors Python _max_volume_number). }
  SetLength(Files, 3);
  Files[0] := 'Series V001.cbz';
  Files[1] := 'Series V002_OLD.cbz';
  Files[2] := 'Series V005_extra.cbz';
  AssertEquals('Only V001 counts', 1,
    TMergeService.LastVolumeNumber(Files, 'Series'));
end;

procedure TMergeServiceTest.LastVolumeNumber_EmptySeries;
var
  Files: TStringArray;
begin
  SetLength(Files, 1);
  Files[0] := 'Series V001.cbz';
  AssertEquals('Empty series name', 0,
    TMergeService.LastVolumeNumber(Files, ''));
end;

procedure TMergeServiceTest.LastVolumeNumber_OtherSeries;
var
  Files: TStringArray;
begin
  SetLength(Files, 3);
  Files[0] := 'Bleach V007.cbz';
  Files[1] := 'Series - 010.cbz';
  Files[2] := 'Series V002.cbz';
  AssertEquals('Other series ignored', 2,
    TMergeService.LastVolumeNumber(Files, 'Series'));
end;

{ Merge }

procedure TMergeServiceTest.Merge_BelowThresholdNoVolume;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
begin
  { Two chapters, auto-CPV falls back to 7 → below threshold, no volume.
    Mirrors the Python reference ("Not enough chapters"). }
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

  AssertFalse('No volume below threshold', Res.Success);
  AssertEquals('0 volumes created', 0, Res.VolumesCreated);
  AssertTrue('Clear error message',
    Pos('Not enough chapters', Res.ErrorMsg) > 0);
  AssertFalse('No volume file', FileExists(FTempDir + 'Test V001.cbz'));
  AssertTrue('Chapters untouched',
    FileExists(FTempDir + 'Test - 01.cbz'));
  AssertFalse('No backup made',
    FileExists(FTempDir + 'Test - 01_OLD.cbz'));
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
  Opts.ChaptersPerVolume := 1;
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

procedure TMergeServiceTest.Merge_ChapterZeroIncluded;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
begin
  { Regression: "Series - 0000.cbz" is a regular chapter (Python reference
    _CHAPTER_RE matches it).  The default range starts at 0, so it must be
    merged — it used to be dropped when ChapterStart defaulted to 1. }
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'ZeroTest - 0000.cbz', [Png], ['z.png']);
  Png.Free;

  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'ZeroTest - 0001.cbz', [Png], ['c.png']);
  Png.Free;

  SetLength(Files, 2);
  Files[0] := 'ZeroTest - 0000.cbz';
  Files[1] := 'ZeroTest - 0001.cbz';

  Opts.SeriesName := 'ZeroTest';
  Opts.ChapterStart := 0;  { the default — covers chapter 0 }
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 2;
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('1 volume created', 1, Res.VolumesCreated);
  AssertTrue('Volume exists', FileExists(FTempDir + 'ZeroTest V001.cbz'));
  { Chapter 0 plus chapter 1 → both pages in the volume. }
  AssertEquals('Volume contains both chapters', 2,
    GetImageCount(FTempDir + 'ZeroTest V001.cbz'));
  { Delete=False renames merged chapters to _OLD — chapter 0 must have
    been part of the merge, not silently skipped. }
  AssertTrue('Chapter 0 was merged (renamed to _OLD)',
    FileExists(FTempDir + 'ZeroTest - 0000_OLD.cbz'));
end;

procedure TMergeServiceTest.Merge_ContinuesFromLastVolume;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
begin
  { Existing V001 volume, then chapters 2 and 3 → the new volume must be
    numbered V002, not overwrite V001. }
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test V001.cbz', [Png], ['v.png']);
  Png.Free;

  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - 02.cbz', [Png], ['c.png']);
  Png.Free;

  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - 03.cbz', [Png], ['c.png']);
  Png.Free;

  SetLength(Files, 3);
  Files[0] := 'Test V001.cbz';
  Files[1] := 'Test - 02.cbz';
  Files[2] := 'Test - 03.cbz';

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 2;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 2;
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('1 volume created', 1, Res.VolumesCreated);
  AssertTrue('Existing volume untouched',
    FileExists(FTempDir + 'Test V001.cbz'));
  AssertTrue('New volume continues numbering',
    FileExists(FTempDir + 'Test V002.cbz'));
end;

procedure TMergeServiceTest.Merge_ForceAbsorbsRemainder;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
  i: integer;
begin
  { CLI differential "force": chapters 8-14 (7), volumes V001+V002 →
    CPV = 7/2 = 3.5 → V003 (ch 8-10, 3 pages), V004 (ch 11-14, 4 pages —
    force absorbs the remainder); all 7 chapters backed up. }
  for i := 1 to 2 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test V%.3d.cbz', [i]), [Png, Png],
      ['v1.jpg', 'v2.jpg']);
    Png.Free;
  end;
  for i := 8 to 14 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test - %.3d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;

  SetLength(Files, 9);
  Files[0] := 'Test V001.cbz';
  Files[1] := 'Test V002.cbz';
  for i := 8 to 14 do
    Files[i - 6] := Format('Test - %.3d.cbz', [i]);

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 0;  { auto → 7/2 = 3.5 }
  Opts.Force := True;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('2 volumes created', 2, Res.VolumesCreated);
  AssertEquals('V003 has 3 pages', 3,
    GetImageCount(FTempDir + 'Test V003.cbz'));
  AssertEquals('V004 has 4 pages (remainder forced in)', 4,
    GetImageCount(FTempDir + 'Test V004.cbz'));
  for i := 8 to 14 do
    AssertTrue(Format('Chapter %d backed up', [i]),
      FileExists(FTempDir + Format('Test - %.3d_OLD.cbz', [i])));
end;

procedure TMergeServiceTest.Merge_ForceOffLeavesRemainder;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
  i: integer;
begin
  { CLI differential "force_off": same fixture without Force → V003
    (3 pages), V004 (3 pages), chapter 14 remains unmerged. }
  for i := 1 to 2 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test V%.3d.cbz', [i]), [Png, Png],
      ['v1.jpg', 'v2.jpg']);
    Png.Free;
  end;
  for i := 8 to 14 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test - %.3d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;

  SetLength(Files, 9);
  Files[0] := 'Test V001.cbz';
  Files[1] := 'Test V002.cbz';
  for i := 8 to 14 do
    Files[i - 6] := Format('Test - %.3d.cbz', [i]);

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 0;  { auto → 7/2 = 3.5 }
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('2 volumes created', 2, Res.VolumesCreated);
  AssertEquals('V003 has 3 pages', 3,
    GetImageCount(FTempDir + 'Test V003.cbz'));
  AssertEquals('V004 has 3 pages', 3,
    GetImageCount(FTempDir + 'Test V004.cbz'));
  for i := 8 to 13 do
    AssertTrue(Format('Chapter %d backed up', [i]),
      FileExists(FTempDir + Format('Test - %.3d_OLD.cbz', [i])));
  AssertTrue('Chapter 14 remains', FileExists(FTempDir + 'Test - 014.cbz'));
  AssertFalse('Chapter 14 not backed up',
    FileExists(FTempDir + 'Test - 014_OLD.cbz'));
end;

procedure TMergeServiceTest.Merge_InsufficientChapters;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
  i: integer;
begin
  { CLI differential "insufficient": 10 volumes + a single chapter 21 →
    CPV = 20/10 = 2.0, 1 < 2 → nothing created, chapter untouched. }
  for i := 1 to 10 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test V%.3d.cbz', [i]), [Png, Png],
      ['v1.jpg', 'v2.jpg']);
    Png.Free;
  end;
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - 021.cbz', [Png], ['c21.jpg']);
  Png.Free;

  SetLength(Files, 11);
  for i := 1 to 10 do
    Files[i - 1] := Format('Test V%.3d.cbz', [i]);
  Files[10] := 'Test - 021.cbz';

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 0;  { auto → 20/10 = 2.0 }
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertFalse('Nothing created', Res.Success);
  AssertEquals('0 volumes', 0, Res.VolumesCreated);
  AssertTrue('Not enough chapters message',
    Pos('Not enough chapters', Res.ErrorMsg) > 0);
  AssertTrue('Chapter 21 untouched', FileExists(FTempDir + 'Test - 021.cbz'));
  AssertFalse('No backup', FileExists(FTempDir + 'Test - 021_OLD.cbz'));
end;

procedure TMergeServiceTest.Merge_NoVolumesDefaultCPV;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
  i: integer;
begin
  { CLI differential "novol": 14 chapters, no volumes → default CPV 7 →
    V001 (7 pages), V002 (7 pages); all chapters backed up. }
  for i := 1 to 14 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test - %.3d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;

  SetLength(Files, 14);
  for i := 1 to 14 do
    Files[i - 1] := Format('Test - %.3d.cbz', [i]);

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 0;  { auto → no volumes → default 7 }
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('2 volumes created', 2, Res.VolumesCreated);
  AssertEquals('V001 has 7 pages', 7,
    GetImageCount(FTempDir + 'Test V001.cbz'));
  AssertEquals('V002 has 7 pages', 7,
    GetImageCount(FTempDir + 'Test V002.cbz'));
  for i := 1 to 14 do
    AssertTrue(Format('Chapter %d backed up', [i]),
      FileExists(FTempDir + Format('Test - %.3d_OLD.cbz', [i])));
end;

procedure TMergeServiceTest.Merge_SpecialsWithManualCPV;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
  i: integer;
begin
  { CLI differential "special_cpv5": chapters 1-3 + SP01 + SP02, no
    volumes, manual CPV 5 → one volume of 5 pages (specials are numbered
    4 and 5 after the regular chapters); all 5 files backed up. }
  for i := 1 to 3 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test - %.3d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - SP01.cbz', [Png], ['sp1.jpg']);
  Png.Free;
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - SP02.cbz', [Png], ['sp2.jpg']);
  Png.Free;

  SetLength(Files, 5);
  Files[0] := 'Test - 001.cbz';
  Files[1] := 'Test - 002.cbz';
  Files[2] := 'Test - 003.cbz';
  Files[3] := 'Test - SP01.cbz';
  Files[4] := 'Test - SP02.cbz';

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 5;  { manual, like the CLI's --chapters-per-volume }
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('1 volume created', 1, Res.VolumesCreated);
  AssertEquals('V001 has all 5 pages', 5,
    GetImageCount(FTempDir + 'Test V001.cbz'));
  for i := 1 to 3 do
    AssertTrue(Format('Chapter %d backed up', [i]),
      FileExists(FTempDir + Format('Test - %.3d_OLD.cbz', [i])));
  AssertTrue('SP01 backed up', FileExists(FTempDir + 'Test - SP01_OLD.cbz'));
  AssertTrue('SP02 backed up', FileExists(FTempDir + 'Test - SP02_OLD.cbz'));
end;

procedure TMergeServiceTest.Merge_IrregularVolumes;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
  i: integer;
begin
  { Python-exact float planning: 4 existing volumes cover chapters 1..15
    (irregular), then chapters 16..30 remain.  Auto CPV = 15/4 = 3.75 →
    exactly 4 new volumes of 3 (V005..V008), chapters 28-30 left unmerged
    as Python's 'remaining'.  (The old integer-division code produced 5
    volumes and merged everything.) }
  for i := 1 to 4 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test V%.3d.cbz', [i]), [Png, Png],
      ['v1.jpg', 'v2.jpg']);
    Png.Free;
  end;
  for i := 16 to 30 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test - %.3d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;

  SetLength(Files, 19);
  for i := 1 to 4 do
    Files[i - 1] := Format('Test V%.3d.cbz', [i]);
  for i := 16 to 30 do
    Files[i - 12] := Format('Test - %.3d.cbz', [i]);

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 0;  { auto → 15/4 = 3.75 }
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('4 volumes created (Python float plan)', 4, Res.VolumesCreated);
  for i := 5 to 8 do
  begin
    AssertTrue(Format('V%.3d exists', [i]),
      FileExists(FTempDir + Format('Test V%.3d.cbz', [i])));
    AssertEquals(Format('V%.3d has 3 pages', [i]), 3,
      GetImageCount(FTempDir + Format('Test V%.3d.cbz', [i])));
  end;
  AssertFalse('No V009', FileExists(FTempDir + 'Test V009.cbz'));
  { Chapters 16-27 merged and backed up }
  for i := 16 to 27 do
    AssertTrue(Format('Chapter %d backed up', [i]),
      FileExists(FTempDir + Format('Test - %.3d_OLD.cbz', [i])));
  { Chapters 28-30 left unmerged (Python 'remaining') }
  for i := 28 to 30 do
  begin
    AssertTrue(Format('Chapter %d untouched', [i]),
      FileExists(FTempDir + Format('Test - %.3d.cbz', [i])));
    AssertFalse(Format('Chapter %d not backed up', [i]),
      FileExists(FTempDir + Format('Test - %.3d_OLD.cbz', [i])));
  end;
end;

procedure TMergeServiceTest.Merge_BelowFloatThreshold;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
  i: integer;
begin
  { 2 irregular volumes → auto CPV = 7/2 = 3.5.  3 chapters < 3.5, so
    nothing is created (Python: num_chapters < chapters_per_volume →
    'Not enough chapters').  The old integer code (CPV=3) would have
    created one volume of 3. }
  for i := 1 to 2 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test V%.3d.cbz', [i]), [Png, Png],
      ['v1.jpg', 'v2.jpg']);
    Png.Free;
  end;
  for i := 8 to 10 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test - %.3d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;

  SetLength(Files, 5);
  Files[0] := 'Test V001.cbz';
  Files[1] := 'Test V002.cbz';
  for i := 8 to 10 do
    Files[i - 6] := Format('Test - %.3d.cbz', [i]);

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 0;  { auto → 7/2 = 3.5 }
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertFalse('No volume below float threshold', Res.Success);
  AssertEquals('0 volumes created', 0, Res.VolumesCreated);
  AssertTrue('Clear error message',
    Pos('Not enough chapters', Res.ErrorMsg) > 0);
  AssertTrue('Float CPV shown with one decimal like Python',
    Pos('3.5', Res.ErrorMsg) > 0);
  AssertFalse('No volume file', FileExists(FTempDir + 'Test V003.cbz'));
  for i := 8 to 10 do
    AssertTrue(Format('Chapter %d untouched', [i]),
      FileExists(FTempDir + Format('Test - %.3d.cbz', [i])));
end;

procedure TMergeServiceTest.Merge_ExistingVolumesUntouched;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
begin
  { Regression: a folder that already contains volumes.  ChapterStart = 0
    was the old GUI default that pulled existing volume files into the
    merge batch (they parsed as chapter 0), duplicating all their pages
    into new volumes and then renaming/deleting the originals.  Now the
    volume must be completely untouched. }
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test V001.cbz', [Png, Png], ['v1a.jpg', 'v1b.jpg']);
  Png.Free;

  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - 0002.cbz', [Png], ['c2.jpg']);
  Png.Free;

  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - 0003.cbz', [Png], ['c3.jpg']);
  Png.Free;

  SetLength(Files, 3);
  Files[0] := 'Test V001.cbz';
  Files[1] := 'Test - 0002.cbz';
  Files[2] := 'Test - 0003.cbz';

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 0;  { the old GUI default — must be harmless now }
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 2;
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('1 volume created', 1, Res.VolumesCreated);
  AssertTrue('New volume V002 exists', FileExists(FTempDir + 'Test V002.cbz'));
  AssertEquals('V002 contains only the 2 chapters', 2,
    GetImageCount(FTempDir + 'Test V002.cbz'));
  AssertTrue('Existing volume untouched', FileExists(FTempDir + 'Test V001.cbz'));
  AssertEquals('V001 still has its 2 pages', 2,
    GetImageCount(FTempDir + 'Test V001.cbz'));
  AssertFalse('Volume was not backed up',
    FileExists(FTempDir + 'Test V001_OLD.cbz'));
  AssertTrue('Chapter 2 backed up',
    FileExists(FTempDir + 'Test - 0002_OLD.cbz'));
  AssertTrue('Chapter 3 backed up',
    FileExists(FTempDir + 'Test - 0003_OLD.cbz'));
end;

procedure TMergeServiceTest.Merge_RollbackOnError;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
  FS: TFileStream;
begin
  { A failure while writing the second volume must remove the first volume
    (already written) — mirroring the Python reference's rollback — so a
    re-run cannot duplicate its chapters. }
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - 01.cbz', [Png], ['c1.jpg']);
  Png.Free;

  { Second chapter is not a valid CBZ — CollectZipEntries raises. }
  FS := TFileStream.Create(FTempDir + 'Test - 02.cbz', fmCreate);
  FS.WriteBuffer('this is not a zip', 17);
  FS.Free;

  SetLength(Files, 2);
  Files[0] := 'Test - 01.cbz';
  Files[1] := 'Test - 02.cbz';

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 1;  { 2 batches → V001 written, second fails }
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertFalse('Merge failed', Res.Success);
  AssertEquals('No volume counts as created', 0, Res.VolumesCreated);
  AssertTrue('Error mentions the rollback',
    Pos('created volumes have been removed', Res.ErrorMsg) > 0);
  AssertFalse('First volume rolled back',
    FileExists(FTempDir + 'Test V001.cbz'));
  AssertTrue('Chapter 1 untouched (cleanup skipped)',
    FileExists(FTempDir + 'Test - 01.cbz'));
  AssertFalse('No _OLD backup of chapter 1',
    FileExists(FTempDir + 'Test - 01_OLD.cbz'));
end;

procedure TMergeServiceTest.Merge_OldBackupsNotReMerged;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
begin
  { A previous merge left _OLD chapter backups.  A new merge must not
    treat them as live chapters: no re-merging, no double backup. }
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - 0001_OLD.cbz', [Png], ['b1.jpg']);
  Png.Free;

  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - 0002.cbz', [Png], ['c2.jpg']);
  Png.Free;

  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - 0003.cbz', [Png], ['c3.jpg']);
  Png.Free;

  SetLength(Files, 3);
  Files[0] := 'Test - 0001_OLD.cbz';
  Files[1] := 'Test - 0002.cbz';
  Files[2] := 'Test - 0003.cbz';

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 0;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 2;
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('1 volume created', 1, Res.VolumesCreated);
  AssertEquals('V001 contains only the 2 live chapters', 2,
    GetImageCount(FTempDir + 'Test V001.cbz'));
  AssertTrue('Old backup still exists',
    FileExists(FTempDir + 'Test - 0001_OLD.cbz'));
  AssertFalse('Backup was not backed up again',
    FileExists(FTempDir + 'Test - 0001_OLD_OLD.cbz'));
  AssertTrue('Chapter 2 backed up',
    FileExists(FTempDir + 'Test - 0002_OLD.cbz'));
  AssertTrue('Chapter 3 backed up',
    FileExists(FTempDir + 'Test - 0003_OLD.cbz'));
end;

procedure TMergeServiceTest.Merge_CustomSeqOverflowSkipsBatch;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
  i: integer;
begin
  { Custom sequence [2,5] with 6 chapters: the second batch (5 chapters)
    does not fully fit the 4 remaining chapters, so it is skipped entirely
    — chapters 3-6 stay unmerged, exactly as the dialog preview shows them
    (unassigned '-'), and matching the Python reference's per-batch break. }
  for i := 1 to 6 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test - %.2d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;

  SetLength(Files, 6);
  for i := 1 to 6 do
    Files[i - 1] := Format('Test - %.2d.cbz', [i]);

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 7;   { irrelevant when ChaptersList is set }
  SetLength(Opts.ChaptersList, 2);
  Opts.ChaptersList[0] := 2;
  Opts.ChaptersList[1] := 5;
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('1 volume created', 1, Res.VolumesCreated);
  AssertTrue('V001 exists', FileExists(FTempDir + 'Test V001.cbz'));
  AssertEquals('V001 has the 2 first chapters', 2,
    GetImageCount(FTempDir + 'Test V001.cbz'));
  AssertTrue('Chapter 1 backed up',
    FileExists(FTempDir + 'Test - 01_OLD.cbz'));
  AssertTrue('Chapter 2 backed up',
    FileExists(FTempDir + 'Test - 02_OLD.cbz'));
  { Overflow chapters stay untouched }
  for i := 3 to 6 do
  begin
    AssertTrue(Format('Chapter %d untouched', [i]),
      FileExists(FTempDir + Format('Test - %.2d.cbz', [i])));
    AssertFalse(Format('Chapter %d not backed up', [i]),
      FileExists(FTempDir + Format('Test - %.2d_OLD.cbz', [i])));
  end;
end;

procedure TMergeServiceTest.Merge_OtherSeriesUntouched;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
begin
  { Files of another series in the same folder must not be merged into
    this series' volumes nor cleaned up. }
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test - 0001.cbz', [Png], ['c1.jpg']);
  Png.Free;

  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Other - 0001.cbz', [Png], ['o1.jpg']);
  Png.Free;

  SetLength(Files, 2);
  Files[0] := 'Test - 0001.cbz';
  Files[1] := 'Other - 0001.cbz';

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 1;
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('1 volume created', 1, Res.VolumesCreated);
  AssertEquals('V001 has only the Test chapter', 1,
    GetImageCount(FTempDir + 'Test V001.cbz'));
  AssertTrue('Other series file untouched',
    FileExists(FTempDir + 'Other - 0001.cbz'));
  AssertFalse('Other series not backed up',
    FileExists(FTempDir + 'Other - 0001_OLD.cbz'));
  AssertTrue('Merged chapter backed up',
    FileExists(FTempDir + 'Test - 0001_OLD.cbz'));
end;

procedure TMergeServiceTest.Merge_ResumesAfterVolumes;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TMergeOptions;
  Res: TMergeResult;
  i: integer;
begin
  { Python merge_basic scenario: volumes V001+V002 already exist, chapters
    7-12 remain.  Auto-CPV = (7-1)/2 = 3 → V003 (ch 7-9), V004 (ch 10-12). }
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test V001.cbz', [Png, Png], ['v1a.jpg', 'v1b.jpg']);
  Png.Free;

  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'Test V002.cbz', [Png, Png], ['v2a.jpg', 'v2b.jpg']);
  Png.Free;

  for i := 7 to 12 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test - %.4d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;

  SetLength(Files, 8);
  Files[0] := 'Test V001.cbz';
  Files[1] := 'Test V002.cbz';
  for i := 7 to 12 do
    Files[i - 5] := Format('Test - %.4d.cbz', [i]);

  Opts.SeriesName := 'Test';
  Opts.ChapterStart := 1;
  Opts.ChapterEnd := 99;
  Opts.ChaptersPerVolume := 0;  { auto: (7-1)/2 = 3 }
  Opts.Force := False;
  Opts.Delete := False;

  Res := TMergeService.Merge(Files, FTempDir, Opts);

  AssertTrue('Merge succeeded', Res.Success);
  AssertEquals('2 volumes created', 2, Res.VolumesCreated);
  AssertTrue('V003 exists', FileExists(FTempDir + 'Test V003.cbz'));
  AssertEquals('V003 has 3 pages', 3, GetImageCount(FTempDir + 'Test V003.cbz'));
  AssertTrue('V004 exists', FileExists(FTempDir + 'Test V004.cbz'));
  AssertEquals('V004 has 3 pages', 3, GetImageCount(FTempDir + 'Test V004.cbz'));
  AssertTrue('V001 untouched', FileExists(FTempDir + 'Test V001.cbz'));
  AssertTrue('V002 untouched', FileExists(FTempDir + 'Test V002.cbz'));
  for i := 7 to 12 do
    AssertTrue(Format('Chapter %d backed up', [i]),
      FileExists(FTempDir + Format('Test - %.4d_OLD.cbz', [i])));
end;

initialization
  RegisterTest(TMergeServiceTest);
end.
