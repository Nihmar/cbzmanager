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
  AssertNull('.webp', ReaderClassForExt('.webp'));
  AssertNull('.tiff', ReaderClassForExt('.tiff'));  // no built-in TIFF reader
  AssertNull('.txt', ReaderClassForExt('.txt'));
end;

initialization
  RegisterTest(TZipEditorTest);
  RegisterTest(TImageUtilTest);
end.
