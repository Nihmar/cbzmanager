unit test_uzipeditor;
{$mode objfpc}{$h+}
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils, IntfGraphics, uzipcore, uZipEditor;

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
    procedure TestCollectZipEntries;
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
  end;

  TImageUtilTest = class(TTestCase)
  published
    procedure TestIsImageExt;
    procedure TestReaderClassForExt;
  end;

implementation

uses
  uImgUtil, test_helpers, FileUtil;

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

initialization
  RegisterTest(TZipEditorTest);
  RegisterTest(TImageUtilTest);
end.
