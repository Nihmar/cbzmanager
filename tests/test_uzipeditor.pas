unit test_uzipeditor;
{$mode objfpc}{$h+}
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils, IntfGraphics, uzipcore, uZipEditor, uWebP;

type
  TZipEditorTest = class(TTestCase)
  private
    FTempDir: string;
    FValidCBZ: string;
    FEmptyCBZ: string;
    FNonImageCBZ: string;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestIsValidCBZ_ValidFile;
    procedure TestIsValidCBZ_EmptyFile;
    procedure TestIsValidCBZ_NonImageFile;
    procedure TestGetImageCount_ValidFile;
    procedure TestGetImageCount_EmptyFile;
    procedure TestGetImageFileNames_ValidFile;
    procedure TestGetImageAsIntfImage;
    procedure TestCollectZipEntries;
    procedure TestCollectCBRFiles;
    procedure TestCollectCbrEntries;
    procedure TestForEachCbrImage;
    procedure TestGetCbrFirstImageInfo;
    procedure TestGetCbrImageAsIntfImage;
    procedure TestConvertCbrToCbz;
    procedure TestConvertCbrToCbz_SkipsNonImage;
    procedure TestConvertCbrToCbz_RealRar;
    procedure TestValidateCBZImages;
    procedure TestMergeIntoVolume;
    procedure TestMergeIntoVolume_SkipsNonImage;
    procedure TestMergeIntoVolume_SortsEntries;
    procedure TestFilterPages_DeleteFirst_Renumber;
    procedure TestFilterPages_DeleteLast_Renumber;
    procedure TestFilterPages_KeepOriginalNumbers_DeleteFirst;
    procedure TestFilterPages_KeepOriginalNumbers_DeleteMiddle;
    procedure TestFilterPages_DeleteNone;
    procedure TestFilterPages_DeleteAll;
    procedure TestConvertWebP_ParallelDeterministic;
    procedure TestValidateCBZImages_ParallelDeterministic;
  end;

  TImageUtilTest = class(TTestCase)
  published
    procedure TestIsImageExt;
    procedure TestReaderClassForExt;
    procedure TestCenterAnchorScrollPos;
    procedure TestGlobalFilePercent;
  end;

implementation

uses
  uImgUtil, uarchive, uservicebase, test_helpers, FileUtil, Process;

{ Counting image callback for ForEachCbrImage. }
type
  TImageCounter = class
    Count: integer;
    FirstName: string;
    RankSum: integer;
    procedure CountImage(const AName: string; AImage: TLazIntfImage;
      AIndex: integer; var ACancel: boolean);
  end;

procedure TImageCounter.CountImage(const AName: string; AImage: TLazIntfImage;
  AIndex: integer; var ACancel: boolean);
begin
  Inc(Count);
  if Count = 1 then
    FirstName := AName;
  Inc(RankSum, AIndex);
  AImage.Free;   { the callback owns the decoded image }
end;

{ Build a ZIP-format .cbr: libarchive auto-detects the container, so the
  whole CBR pipeline can be tested without a RAR compressor. }
function MakeCbr(const ADir, AName: string; const Entries: array of TMemoryStream;
  const Names: array of string): string;
begin
  Result := ADir + AName;
  CreateCBZ(Result, Entries, Names);
end;

{ TZipEditorTest }

procedure TZipEditorTest.SetUp;
var
  Png1, Png2, Png3, Txt: TMemoryStream;
begin
  FTempDir := CreateTempDir('cbztest_');

  { valid.cbz — 3 PNG images }
  Png1 := CreateMinimalPNGStream;
  Png2 := CreateMinimalPNGStream;
  Png3 := CreateMinimalPNGStream;
  FValidCBZ := FTempDir + 'valid.cbz';
  CreateCBZ(FValidCBZ, [Png1, Png2, Png3], ['page001.png', 'page002.png', 'page003.png']);
  Png1.Free; Png2.Free; Png3.Free;

  { empty.cbz — zero entries }
  FEmptyCBZ := FTempDir + 'empty.cbz';
  CreateCBZ(FEmptyCBZ, [], []);

  { non_image.cbz — text files only }
  Txt := TMemoryStream.Create;
  Txt.WriteAnsiString('hello');
  Txt.Position := 0;
  FNonImageCBZ := FTempDir + 'non_image.cbz';
  CreateCBZ(FNonImageCBZ, [Txt, Txt], ['info.txt', 'readme.txt']);
  Txt.Free;
end;

procedure TZipEditorTest.TearDown;
begin
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
end;

procedure TZipEditorTest.TestIsValidCBZ_ValidFile;
begin
  AssertTrue('valid.cbz should be valid', IsValidCBZ(FValidCBZ));
end;

procedure TZipEditorTest.TestIsValidCBZ_EmptyFile;
begin
  AssertFalse('empty.cbz should not be valid', IsValidCBZ(FEmptyCBZ));
end;

procedure TZipEditorTest.TestIsValidCBZ_NonImageFile;
begin
  AssertFalse('non_image.cbz should not be valid', IsValidCBZ(FNonImageCBZ));
end;

procedure TZipEditorTest.TestGetImageCount_ValidFile;
begin
  AssertEquals('valid.cbz has 3 images', 3, GetImageCount(FValidCBZ));
end;

procedure TZipEditorTest.TestGetImageCount_EmptyFile;
begin
  AssertEquals('empty.cbz has 0 images', 0, GetImageCount(FEmptyCBZ));
end;

procedure TZipEditorTest.TestGetImageFileNames_ValidFile;
var
  Names: TStringArray;
begin
  Names := GetImageFileNames(FValidCBZ);
  AssertEquals('3 filenames', 3, Length(Names));
  AssertEquals('page001.png', 'page001.png', Names[0]);
  AssertEquals('page002.png', 'page002.png', Names[1]);
  AssertEquals('page003.png', 'page003.png', Names[2]);
end;

procedure TZipEditorTest.TestGetImageAsIntfImage;
var
  Img: TLazIntfImage;
begin
  { Full-resolution single-entry extraction: the entry must decode exactly. }
  Img := GetImageAsIntfImage(FValidCBZ, 'page001.png');
  try
    AssertNotNull('existing entry decodes', Img);
    if Img <> nil then
    begin
      AssertEquals('1x1 png width', 1, Img.Width);
      AssertEquals('1x1 png height', 1, Img.Height);
    end;
  finally
    Img.Free;
  end;

  { A late entry in the archive must also resolve. }
  Img := GetImageAsIntfImage(FValidCBZ, 'page003.png');
  try
    AssertNotNull('late entry decodes', Img);
  finally
    Img.Free;
  end;

  { Missing entry -> nil, no exception. }
  Img := GetImageAsIntfImage(FValidCBZ, 'none.png');
  AssertNull('missing entry returns nil', Img);
end;

procedure TZipEditorTest.TestCollectCBRFiles;
var
  Files: TStringArray;
  FS: TFileStream;
  HasOne, HasTwo: boolean;
  i: integer;
begin
  { The directory scan must pick up .cbr files (the file list merges
    CollectCBZFiles + CollectCBRFiles), matching only .cbr — and be
    case-insensitive like CollectCBZFiles.  The scan order is
    filesystem-dependent; TLoadThread sorts the merged list. }
  FS := TFileStream.Create(FTempDir + 'one.cbr', fmCreate);
  FS.Free;
  FS := TFileStream.Create(FTempDir + 'two.CBR', fmCreate);
  FS.Free;
  FS := TFileStream.Create(FTempDir + 'three.cbz', fmCreate);
  FS.Free;

  Files := CollectCBRFiles(FTempDir);
  AssertEquals('2 .cbr files', 2, Length(Files));
  HasOne := False;
  HasTwo := False;
  for i := 0 to High(Files) do
  begin
    if Files[i] = 'one.cbr' then HasOne := True;
    if Files[i] = 'two.CBR' then HasTwo := True;
  end;
  AssertTrue('one.cbr found', HasOne);
  AssertTrue('two.CBR found (case-insensitive)', HasTwo);
end;

procedure TZipEditorTest.TestCollectCbrEntries;
var
  Png1, Png2, Txt: TMemoryStream;
  Path: string;
  Entries: TZipEntries;
begin
  AssertTrue('libarchive present', CbrSupported);
  Png1 := CreateMinimalPNGStream;
  Png2 := CreateMinimalPNGStream;
  Txt := TMemoryStream.Create;
  Txt.WriteAnsiString('credits');
  Txt.Position := 0;
  Path := MakeCbr(FTempDir, 'book.cbr', [Png1, Txt, Png2],
    ['page002.png', 'credits.txt', 'page001.png']);
  Png1.Free;
  Png2.Free;
  Txt.Free;

  Entries := CollectCbrEntries(Path);
  try
    { All entries (including non-images) are collected, in archive order. }
    AssertEquals('3 entries', 3, Length(Entries));
    AssertEquals('first entry', 'page002.png', Entries[0].Name);
    AssertEquals('second entry', 'credits.txt', Entries[1].Name);
    AssertEquals('third entry', 'page001.png', Entries[2].Name);
    AssertTrue('data non-empty', Entries[0].Data.Size > 0);
  finally
    FreeZipEntries(Entries);
  end;
end;

procedure TZipEditorTest.TestForEachCbrImage;
var
  Png1, Png2, Txt: TMemoryStream;
  Path: string;
  Counter: TImageCounter;
begin
  AssertTrue('libarchive present', CbrSupported);
  { Scrambled storage order: page002 stored before page001. }
  Png1 := CreateMinimalPNGStream;
  Png2 := CreateMinimalPNGStream;
  Txt := TMemoryStream.Create;
  Txt.WriteAnsiString('credits');
  Txt.Position := 0;
  Path := MakeCbr(FTempDir, 'order.cbr', [Png1, Txt, Png2],
    ['page002.png', 'credits.txt', 'page001.png']);
  Png1.Free;
  Png2.Free;
  Txt.Free;

  Counter := TImageCounter.Create;
  try
    ForEachCbrImage(Path, @Counter.CountImage);
    AssertEquals('2 images decoded', 2, Counter.Count);
    { The callback fires in archive order (like the ZIP walker); AIndex is
      the alphabetical rank, so ranks 0+1 in whatever order they arrive. }
    AssertEquals('first in archive order', 'page002.png', Counter.FirstName);
    AssertEquals('ranks 0+1', 1, Counter.RankSum);
  finally
    Counter.Free;
  end;
end;

procedure TZipEditorTest.TestGetCbrFirstImageInfo;
var
  Png1, Png2, Txt: TMemoryStream;
  Path: string;
  Img: TLazIntfImage;
  HasComicInfo: boolean;
begin
  AssertTrue('libarchive present', CbrSupported);
  Png1 := CreateMinimalPNGStream;
  Png2 := CreateMinimalPNGStream;
  Txt := TMemoryStream.Create;
  Txt.WriteAnsiString('credits');
  Txt.Position := 0;
  Path := MakeCbr(FTempDir, 'first.cbr', [Png1, Png2],
    ['page002.png', 'page001.png']);
  Png1.Free;
  Png2.Free;
  Txt.Free;

  Img := nil;
  AssertTrue('first image decoded',
    GetCbrFirstImageInfo(Path, Img, HasComicInfo, 0, 0));
  try
    AssertNotNull('image', Img);
    if Img <> nil then
    begin
      AssertEquals('1x1 png width', 1, Img.Width);
      AssertEquals('1x1 png height', 1, Img.Height);
    end;
  finally
    Img.Free;
  end;
  AssertFalse('no ComicInfo', HasComicInfo);

  { Missing entries -> false, no exception. }
  AssertFalse('garbage file', GetCbrFirstImageInfo(FTempDir + 'nope.cbr',
    Img, HasComicInfo, 0, 0));
end;

procedure TZipEditorTest.TestGetCbrImageAsIntfImage;
var
  Png: TMemoryStream;
  Path: string;
  Img: TLazIntfImage;
begin
  AssertTrue('libarchive present', CbrSupported);
  Png := CreateMinimalPNGStream;
  Path := MakeCbr(FTempDir, 'single.cbr', [Png], ['page_0001.png']);
  Png.Free;

  Img := GetCbrImageAsIntfImage(Path, 'page_0001.png');
  try
    AssertNotNull('existing entry decodes', Img);
  finally
    Img.Free;
  end;
  Img := GetCbrImageAsIntfImage(Path, 'missing.png');
  AssertNull('missing entry returns nil', Img);
end;

procedure TZipEditorTest.TestConvertCbrToCbz;
var
  Png1, Png2, Txt: TMemoryStream;
  Path, Target: string;
  Entries: TZipEntries;
  FS: TFileStream;
  i: integer;
begin
  AssertTrue('libarchive present', CbrSupported);
  { 2 images + credits.txt: the txt must not become a page. }
  Png1 := CreateMinimalPNGStream;
  Png2 := CreateMinimalPNGStream;
  Txt := TMemoryStream.Create;
  Txt.WriteAnsiString('credits');
  Txt.Position := 0;
  Path := MakeCbr(FTempDir, 'conv.cbr', [Png1, Txt, Png2],
    ['page002.png', 'credits.txt', 'page001.png']);
  Png1.Free;
  Png2.Free;
  Txt.Free;

  Entries := ConvertCbrToCbz(Path);
  AssertEquals('2 pages', 2, Length(Entries));
  AssertEquals('page_001.png', 'page_001.png', Entries[0].Name);
  AssertEquals('page_002.png', 'page_002.png', Entries[1].Name);
  for i := 0 to High(Entries) do
    AssertTrue('data non-empty', Entries[i].Data.Size > 0);

  { Writing the entries produces a readable CBZ. }
  Target := FTempDir + 'conv.cbz';
  WriteZipFromEntriesDeflated(Target, Entries);
  FreeZipEntries(Entries);

  { The source .cbr is never modified. }
  FS := TFileStream.Create(Path, fmOpenRead);
  try
    AssertTrue('source still present', FS.Size > 0);
  finally
    FS.Free;
  end;
  AssertTrue('target exists', FileExists(Target));
  AssertEquals('target readable', 2, GetImageCount(Target));
end;

procedure TZipEditorTest.TestConvertCbrToCbz_SkipsNonImage;
var
  Png: TMemoryStream;
  Path: string;
  Entries: TZipEntries;
begin
  AssertTrue('libarchive present', CbrSupported);
  { Only a text file: no pages survive -> empty result, no crash. }
  Png := TMemoryStream.Create;
  Png.WriteAnsiString('nothing here');
  Png.Position := 0;
  Path := MakeCbr(FTempDir, 'empty.cbr', [Png], ['readme.txt']);
  Png.Free;

  Entries := ConvertCbrToCbz(Path);
  try
    AssertEquals('0 pages', 0, Length(Entries));
  finally
    FreeZipEntries(Entries);
  end;
end;

procedure TZipEditorTest.TestConvertCbrToCbz_RealRar;
var
  Png: TMemoryStream;
  PngFile, Path: string;
  Proc: TProcess;
  Entries: TZipEntries;
begin
  { True RAR coverage requires the rar compressor; skip when absent. }
  if FindDefaultExecutablePath('rar') = '' then Exit;
  AssertTrue('libarchive present', CbrSupported);

  PngFile := FTempDir + 'page.png';
  Png := CreateMinimalPNGStream;
  Png.SaveToFile(PngFile);
  Png.Free;

  Path := FTempDir + 'real.cbr';
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := 'rar';
    Proc.Parameters.Add('a');
    Proc.Parameters.Add('-idq');
    Proc.Parameters.Add('-ep');   { store bare names, no path prefix }
    Proc.Parameters.Add(Path);
    Proc.Parameters.Add(PngFile);
    Proc.Options := Proc.Options + [poWaitOnExit];
    Proc.Execute;
    Proc.WaitOnExit;
  finally
    Proc.Free;
  end;
  if not FileExists(Path) then
    Fail('rar compressor did not produce ' + Path);

  Entries := ConvertCbrToCbz(Path);
  try
    AssertEquals('1 page', 1, Length(Entries));
    AssertEquals('page_001.png', 'page_001.png', Entries[0].Name);
    AssertTrue('data non-empty', Entries[0].Data.Size > 0);
  finally
    FreeZipEntries(Entries);
  end;
  AssertTrue('source .cbr untouched', FileExists(Path));
end;

procedure TZipEditorTest.TestCollectZipEntries;
var
  Entries: TZipEntries;
begin
  Entries := CollectZipEntries(FValidCBZ);
  try
    AssertEquals('3 entries', 3, Length(Entries));
    AssertEquals('first entry name', 'page001.png', Entries[0].Name);
    AssertNotNull('first entry data', Entries[0].Data);
    AssertTrue('first entry data has content', Entries[0].Data.Size > 0);
  finally
    FreeZipEntries(Entries);
  end;
end;

procedure TZipEditorTest.TestValidateCBZImages;
var
  Checks: TImageChecks;
  Total: integer;
begin
  { Valid file: all 3 PNGs should decode }
  Total := ValidateCBZImages(FValidCBZ, Checks);
  AssertEquals('3 valid images', 3, Total);
  AssertEquals('3 checks', 3, Length(Checks));
  AssertTrue('first valid', Checks[0].Valid);
  AssertEquals('page001.png', 'page001.png', Checks[0].EntryName);

  { Empty file: exception leads to 1 error entry }
  Total := ValidateCBZImages(FEmptyCBZ, Checks);
  AssertEquals('0 valid for empty', 0, Total);
  AssertEquals('1 error entry for empty', 1, Length(Checks));
  AssertFalse('error entry invalid', Checks[0].Valid);

  { Non-image file: no image entries (ForEachImage skips non-image exts) }
  Total := ValidateCBZImages(FNonImageCBZ, Checks);
  AssertEquals('0 valid for non-image', 0, Total);
  AssertEquals('0 entries for non-image', 0, Length(Checks));
end;

procedure TZipEditorTest.TestMergeIntoVolume;
var
  Vol1: TZipEntries;
  Sources: TStringArray;
  Png: TMemoryStream;
begin
  { Create two chapter CBZs — MergeIntoVolume expects filenames + ADir }
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'ch01.cbz', [Png, Png], ['img001.jpg', 'img002.jpg']);
  Png.Free;
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'ch02.cbz', [Png, Png], ['img001.jpg', 'img002.jpg']);
  Png.Free;

  { Pass filenames only, FTempDir as ADir }
  SetLength(Sources, 2);
  Sources[0] := 'ch01.cbz';
  Sources[1] := 'ch02.cbz';

  Vol1 := MergeIntoVolume(Sources, FTempDir);
  try
    AssertEquals('merged 4 pages', 4, Length(Vol1));
    AssertEquals('page_001.jpg', 'page_001.jpg', Vol1[0].Name);
    AssertEquals('page_004.jpg', 'page_004.jpg', Vol1[3].Name);
  finally
    FreeZipEntries(Vol1);
  end;
end;

procedure TZipEditorTest.TestMergeIntoVolume_SkipsNonImage;
var
  Vol: TZipEntries;
  Sources: TStringArray;
  Png, Txt: TMemoryStream;
  i: integer;
begin
  { A chapter containing 2 images plus a non-image entry (credits.txt).
    The merged volume must contain only the 2 image pages — the .txt must
    not be renumbered into the page sequence. }
  Png := CreateMinimalPNGStream;
  Txt := TMemoryStream.Create;
  Txt.WriteAnsiString('credits');
  Txt.Position := 0;
  CreateCBZ(FTempDir + 'chp.cbz', [Png, Txt, Png],
    ['img001.jpg', 'credits.txt', 'img002.jpg']);
  Png.Free;
  Txt.Free;

  SetLength(Sources, 1);
  Sources[0] := 'chp.cbz';

  Vol := MergeIntoVolume(Sources, FTempDir);
  try
    AssertEquals('only 2 image pages', 2, Length(Vol));
    AssertEquals('page_001.jpg', 'page_001.jpg', Vol[0].Name);
    AssertEquals('page_002.jpg', 'page_002.jpg', Vol[1].Name);
    for i := 0 to High(Vol) do
      AssertTrue('no .txt entry', LowerCase(ExtractFileExt(Vol[i].Name)) <> '.txt');
  finally
    FreeZipEntries(Vol);
  end;
end;

procedure TZipEditorTest.TestMergeIntoVolume_SortsEntries;
var
  Vol: TZipEntries;
  Sources: TStringArray;
  A, M, Z: TMemoryStream;
  Data: string;
begin
  { Entries stored in the archive in non-alphabetical order (z, a, m) must
    end up in alphabetical page order, like the Python reference's
    sorted(namelist()).  Before the fix this test fails: TUnZipper emits
    entries in archive (central-directory) order, so page_001 was 'z'. }
  A := TMemoryStream.Create;
  A.WriteBuffer('AAA', 3);
  A.Position := 0;
  M := TMemoryStream.Create;
  M.WriteBuffer('MMM', 3);
  M.Position := 0;
  Z := TMemoryStream.Create;
  Z.WriteBuffer('ZZZ', 3);
  Z.Position := 0;
  CreateCBZ(FTempDir + 'ch_order.cbz', [Z, A, M], ['z.jpg', 'a.jpg', 'm.jpg']);
  A.Free;
  M.Free;
  Z.Free;

  SetLength(Sources, 1);
  Sources[0] := 'ch_order.cbz';

  Vol := MergeIntoVolume(Sources, FTempDir);
  try
    AssertEquals('3 pages', 3, Length(Vol));
    AssertEquals('page_001.jpg', 'page_001.jpg', Vol[0].Name);
    AssertEquals('page_002.jpg', 'page_002.jpg', Vol[1].Name);
    AssertEquals('page_003.jpg', 'page_003.jpg', Vol[2].Name);
    { Alphabetical source order a.jpg, m.jpg, z.jpg must become pages 1..3 }
    SetLength(Data, Vol[0].Data.Size);
    Vol[0].Data.Position := 0;
    Vol[0].Data.ReadBuffer(Data[1], Vol[0].Data.Size);
    AssertEquals('page_001 is a.jpg', 'AAA', Data);
    SetLength(Data, Vol[1].Data.Size);
    Vol[1].Data.Position := 0;
    Vol[1].Data.ReadBuffer(Data[1], Vol[1].Data.Size);
    AssertEquals('page_002 is m.jpg', 'MMM', Data);
    SetLength(Data, Vol[2].Data.Size);
    Vol[2].Data.Position := 0;
    Vol[2].Data.ReadBuffer(Data[1], Vol[2].Data.Size);
    AssertEquals('page_003 is z.jpg', 'ZZZ', Data);
  finally
    FreeZipEntries(Vol);
  end;
end;

{ FilterPagesFromCBZ — regression tests.  FValidCBZ has 3 PNG images.
  The delete mask is 1-indexed-by-image via a 0-based boolean array:
  True = delete the image at that position. }

procedure TZipEditorTest.TestFilterPages_DeleteFirst_Renumber;
var
  E: TZipEntries;
begin
  { Delete the first page; renumber survivors sequentially.
    This case used to crash (Result sized to 0, then written at index 0). }
  E := FilterPagesFromCBZ(FValidCBZ, [True, False, False], True);
  try
    AssertEquals('2 survivors', 2, Length(E));
    AssertEquals('renumbered 1', 'page_001.png', E[0].Name);
    AssertEquals('renumbered 2', 'page_002.png', E[1].Name);
    AssertNotNull('data 0', E[0].Data);
    AssertNotNull('data 1', E[1].Data);
    AssertTrue('data 0 non-empty', E[0].Data.Size > 0);
  finally
    FreeZipEntries(E);
  end;
end;

procedure TZipEditorTest.TestFilterPages_DeleteLast_Renumber;
var
  E: TZipEntries;
begin
  { Delete the last page; renumber.  This case used to leave a trailing
    entry with Data=nil (Result over-sized) and crash on write. }
  E := FilterPagesFromCBZ(FValidCBZ, [False, False, True], True);
  try
    AssertEquals('2 survivors', 2, Length(E));
    AssertEquals('renumbered 1', 'page_001.png', E[0].Name);
    AssertEquals('renumbered 2', 'page_002.png', E[1].Name);
    AssertNotNull('data 1', E[1].Data);
  finally
    FreeZipEntries(E);
  end;
end;

procedure TZipEditorTest.TestFilterPages_KeepOriginalNumbers_DeleteFirst;
var
  E: TZipEntries;
begin
  { Delete the first page WITHOUT renumbering: survivors keep their original
    numbers (2 and 3), leaving a gap at 1, compacted into the array. }
  E := FilterPagesFromCBZ(FValidCBZ, [True, False, False], False);
  try
    AssertEquals('2 survivors', 2, Length(E));
    AssertEquals('kept original 2', 'page_002.png', E[0].Name);
    AssertEquals('kept original 3', 'page_003.png', E[1].Name);
  finally
    FreeZipEntries(E);
  end;
end;

procedure TZipEditorTest.TestFilterPages_KeepOriginalNumbers_DeleteMiddle;
var
  E: TZipEntries;
begin
  { Delete the middle page without renumbering: keep 1 and 3, gap at 2. }
  E := FilterPagesFromCBZ(FValidCBZ, [False, True, False], False);
  try
    AssertEquals('2 survivors', 2, Length(E));
    AssertEquals('kept original 1', 'page_001.png', E[0].Name);
    AssertEquals('kept original 3', 'page_003.png', E[1].Name);
  finally
    FreeZipEntries(E);
  end;
end;

procedure TZipEditorTest.TestFilterPages_DeleteNone;
var
  E: TZipEntries;
begin
  { Nothing marked: all pages survive. }
  E := FilterPagesFromCBZ(FValidCBZ, [False, False, False], True);
  try
    AssertEquals('3 survivors', 3, Length(E));
    AssertEquals('1', 'page_001.png', E[0].Name);
    AssertEquals('3', 'page_003.png', E[2].Name);
  finally
    FreeZipEntries(E);
  end;
end;

procedure TZipEditorTest.TestFilterPages_DeleteAll;
var
  E: TZipEntries;
begin
  { Every page marked: no survivors, empty result (caller skips the write). }
  E := FilterPagesFromCBZ(FValidCBZ, [True, True, True], True);
  try
    AssertEquals('0 survivors', 0, Length(E));
  finally
    FreeZipEntries(E);
  end;
end;

{ Parallel WebP conversion must produce identical archives to the
  sequential one: the pool writes each slot by source index and the
  compaction pass runs in archive order, so the thread count must not
  change the output.  Compared by entry content — raw archive bytes carry
  TZipper's write timestamp. }
procedure TZipEditorTest.TestConvertWebP_ParallelDeterministic;
var
  Pngs: array[0..7] of TMemoryStream;
  CiXml: TMemoryStream;
  i, N1, N2, C1, C2: integer;
  M1, M2: boolean;
  E1, E2: TZipEntries;
  Msg: string;
begin
  if not WebPAvailable then Exit;   { degraded env: nothing to convert }

  for i := 0 to 7 do
    Pngs[i] := CreateNoisePNGStream;
  CiXml := TMemoryStream.Create;
  CiXml.WriteAnsiString('<ComicInfo/>');
  CiXml.Position := 0;
  { ComicInfo.xml + 8 noise pages: exercises the skip/keep branch of the
    compaction pass alongside the pooled decode+encode work. }
  CreateCBZ(FTempDir + 'par.cbz',
    [Pngs[0], Pngs[1], CiXml, Pngs[2], Pngs[3], Pngs[4], Pngs[5], Pngs[6], Pngs[7]],
    ['p01.png', 'p02.png', 'ComicInfo.xml', 'p03.png', 'p04.png', 'p05.png',
     'p06.png', 'p07.png', 'p08.png']);
  for i := 0 to 7 do Pngs[i].Free;
  CiXml.Free;

  E1 := ConvertCBZToWebP(FTempDir + 'par.cbz', 75, True, True, True, True,
    N1, C1, M1, nil, 1);
  try
    WriteZipFromEntriesDeflated(FTempDir + 'seq.cbz', E1);
  finally
    FreeZipEntries(E1);
  end;

  E2 := ConvertCBZToWebP(FTempDir + 'par.cbz', 75, True, True, True, True,
    N2, C2, M2, nil, 4);
  try
    WriteZipFromEntriesDeflated(FTempDir + 'par.cbz.out', E2);
  finally
    FreeZipEntries(E2);
  end;

  AssertEquals('entry count matches', N1, N2);
  AssertEquals('converted count matches', C1, C2);
  AssertEquals('modified flag matches', M1, M2);
  AssertTrue('identical archives by content',
    ZipFilesEqual(FTempDir + 'seq.cbz', FTempDir + 'par.cbz.out', Msg));
end;

{ Parallel validation must produce identical per-image checks to the
  sequential run: the pool writes each check into its own slot and the
  results are assembled in archive order after the join. }
procedure TZipEditorTest.TestValidateCBZImages_ParallelDeterministic;
var
  Pngs: array[0..3] of TMemoryStream;
  Garbage, Xml: TMemoryStream;
  i: integer;
  Checks1, Checks4: TImageChecks;
  V1, V4: integer;
begin
  for i := 0 to 3 do
    Pngs[i] := CreateNoisePNGStream;
  Xml := TMemoryStream.Create;
  Xml.WriteAnsiString('<ComicInfo/>');
  Xml.Position := 0;
  Garbage := TMemoryStream.Create;
  Garbage.WriteAnsiString('not an image');
  Garbage.Position := 0;
  CreateCBZ(FTempDir + 'parval.cbz',
    [Pngs[0], Xml, Garbage, Pngs[1], Pngs[2], Pngs[3]],
    ['p01.png', 'ComicInfo.xml', 'broken.png', 'p02.png', 'p03.png', 'p04.png']);
  for i := 0 to 3 do Pngs[i].Free;
  Xml.Free;
  Garbage.Free;

  V1 := ValidateCBZImages(FTempDir + 'parval.cbz', Checks1, 1);
  V4 := ValidateCBZImages(FTempDir + 'parval.cbz', Checks4, 4);

  AssertEquals('valid count matches', V1, V4);
  AssertEquals('check count matches', Length(Checks1), Length(Checks4));
  for i := 0 to High(Checks1) do
  begin
    AssertEquals('check name', Checks1[i].EntryName, Checks4[i].EntryName);
    AssertEquals('check valid', Checks1[i].Valid, Checks4[i].Valid);
  end;
  { 4 good pages decode, the fake one fails; ComicInfo.xml is skipped. }
  AssertEquals('4 valid images', 4, V1);
  AssertEquals('5 checks (4 pages + 1 broken)', 5, Length(Checks1));
  AssertEquals('broken entry named', 'broken.png', Checks1[1].EntryName);
  AssertFalse('broken entry reported invalid', Checks1[1].Valid);
end;

{ TImageUtilTest }

procedure TImageUtilTest.TestIsImageExt;
begin
  AssertTrue('.png', IsImageExt('.png'));
  AssertTrue('.jpg', IsImageExt('.jpg'));
  AssertTrue('.jpeg', IsImageExt('.jpeg'));
  AssertTrue('.webp', IsImageExt('.webp'));
  AssertTrue('.bmp', IsImageExt('.bmp'));
  AssertTrue('.gif', IsImageExt('.gif'));
  AssertTrue('.tiff', IsImageExt('.tiff'));
  AssertTrue('.tif', IsImageExt('.tif'));
  AssertFalse('.txt', IsImageExt('.txt'));
  AssertFalse('.xml', IsImageExt('.xml'));
  AssertFalse('empty string', IsImageExt(''));
end;

procedure TImageUtilTest.TestReaderClassForExt;
begin
  AssertNotNull('.png', ReaderClassForExt('.png'));
  AssertNotNull('.jpg', ReaderClassForExt('.jpg'));
  AssertNotNull('.bmp', ReaderClassForExt('.bmp'));
  AssertNotNull('.gif', ReaderClassForExt('.gif'));
  AssertNotNull('.tiff', ReaderClassForExt('.tiff'));
  AssertNotNull('.tif', ReaderClassForExt('.tif'));
  AssertNull('.webp', ReaderClassForExt('.webp'));  // handled by uWebP separately
  AssertNull('.txt', ReaderClassForExt('.txt'));
end;

procedure TImageUtilTest.TestGlobalFilePercent;
begin
  { Folds within-file progress into a smooth global sweep across the batch:
    file 0 of 4 at 50% -> 12, last file at 100% -> 100. }
  AssertEquals('file 0/4 at 50%', 12, GlobalFilePercent(0, 4, 50));
  AssertEquals('file 1/4 at 0%', 25, GlobalFilePercent(1, 4, 0));
  AssertEquals('file 2/4 at 100%', 75, GlobalFilePercent(2, 4, 100));
  AssertEquals('file 3/4 at 100%', 100, GlobalFilePercent(3, 4, 100));
  { Monotonic within a file: never regresses while pages advance. }
  AssertTrue('monotonic', GlobalFilePercent(1, 4, 10) <=
    GlobalFilePercent(1, 4, 90));
  { Guards }
  AssertEquals('no files -> 0', 0, GlobalFilePercent(0, 0, 50));
  AssertEquals('negative total -> 0', 0, GlobalFilePercent(0, -3, 50));
  { Single file: within-file percent maps directly. }
  AssertEquals('single file', 50, GlobalFilePercent(0, 1, 50));
end;

procedure TImageUtilTest.TestCenterAnchorScrollPos;
begin
  { Zoom-anchoring math shared by the sequence builder preview and the
    page-view dialog: the scroll position that keeps the content point
    under the viewport centre stationary when zooming. }
  AssertEquals('zoom in keeps centre', 600,
    CenterAnchorScrollPos(400, 1.0, 2.0, 400, 1600));
  AssertEquals('zoom in (odd centre) keeps centre', 202,
    CenterAnchorScrollPos(201, 1.0, 2.0, 400, 1600));
  { Identity zoom (page switch) preserves the scroll position. }
  AssertEquals('identity preserves position', 250,
    CenterAnchorScrollPos(450, 2.0, 2.0, 400, 1600));
  { Zooming out pulls the centre to a negative scroll -> clamped to 0. }
  AssertEquals('clamps at start', 0,
    CenterAnchorScrollPos(100, 2.0, 1.0, 400, 800));
  { Content point near the end -> clamped to the max position. }
  AssertEquals('clamps at end', 400,
    CenterAnchorScrollPos(1000, 2.0, 2.0, 400, 800));
  { Content smaller than the viewport -> no scrolling possible. }
  AssertEquals('fits viewport', 0,
    CenterAnchorScrollPos(100, 1.0, 1.0, 400, 300));
end;

initialization
  RegisterTest(TZipEditorTest);
  RegisterTest(TImageUtilTest);
end.
