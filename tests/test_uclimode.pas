unit test_uclimode;
{$mode objfpc}{$h+}
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TClimodeTest = class(TTestCase)
  private
    FTempDir: string;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure IsHeadlessCommand_True;
    procedure IsHeadlessCommand_False;

    procedure RunHeadless_HelpAndVersion;
    procedure RunHeadless_UsageErrors;
    procedure RunHeadless_UnknownCommand;
    procedure RunHeadless_InvalidDirectory;

    procedure RunHeadless_Validate_Ok;
    procedure RunHeadless_Validate_Corrupt;

    procedure RunHeadless_ConvertWebp;
    procedure RunHeadless_ConvertWebp_Delete;

    procedure RunHeadless_CbrToCbz;
    procedure RunHeadless_CbrToCbz_Delete;
    procedure RunHeadless_CbrToCbz_UsageError;
    procedure RunHeadless_CbrToCbz_SkipsExisting;

    procedure RunHeadless_Merge;
    procedure RunHeadless_Merge_Force;
    procedure RunHeadless_Merge_FlagsBeforeDir;
    procedure RunHeadless_Merge_Chapters;
    procedure RunHeadless_Merge_MultiSeries;
    procedure RunHeadless_Merge_NoChapters;
    procedure RunHeadless_Merge_MutuallyExclusive;
  end;

implementation

uses
  Math,
  FPImage,
  FPWritePNG,
  uzipcore,
  uZipEditor,
  uclimode,
  uservicebase,
  uarchive,
  test_helpers,
  FileUtil;

{ TMergeServiceTest }

procedure TClimodeTest.SetUp;
begin
  FTempDir := CreateTempDir('cbzcli_');
end;

procedure TClimodeTest.TearDown;
begin
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
end;

{ Build a 64x64 noise PNG — large enough that the WebP conversion is
  deterministically smaller, so the convert tests assert real conversions. }
function CreateNoisePNGStream: TMemoryStream;
var
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  x, y: integer;
begin
  RandSeed := 12345;
  Img := TFPMemoryImage.Create(64, 64);
  try
    for y := 0 to 63 do
      for x := 0 to 63 do
        Img.Colors[x, y] := FPColor(Random(65536), Random(65536),
          Random(65536));
    Result := TMemoryStream.Create;
    Writer := TFPWriterPNG.Create;
    try
      Writer.ImageWrite(Result, Img);
    finally
      Writer.Free;
    end;
    Result.Position := 0;
  finally
    Img.Free;
  end;
end;

{ IsHeadlessCommand }

procedure TClimodeTest.IsHeadlessCommand_True;
begin
  AssertTrue('validate', IsHeadlessCommand('validate'));
  AssertTrue('convert-webp', IsHeadlessCommand('convert-webp'));
  AssertTrue('merge', IsHeadlessCommand('merge'));
  AssertTrue('cbr-to-cbz', IsHeadlessCommand('cbr-to-cbz'));
  AssertTrue('--help', IsHeadlessCommand('--help'));
  AssertTrue('-h', IsHeadlessCommand('-h'));
  AssertTrue('help', IsHeadlessCommand('help'));
  AssertTrue('--version', IsHeadlessCommand('--version'));
end;

procedure TClimodeTest.IsHeadlessCommand_False;
begin
  AssertFalse('empty', IsHeadlessCommand(''));
  AssertFalse('a folder path', IsHeadlessCommand('/some/folder'));
  AssertFalse('bogus command', IsHeadlessCommand('bogus'));
  AssertFalse('flag for GUI', IsHeadlessCommand('--open'));
end;

{ RunHeadless — trivial paths }

procedure TClimodeTest.RunHeadless_HelpAndVersion;
begin
  AssertEquals('--help exits 0', EXIT_OK, RunHeadless(['--help']));
  AssertEquals('-h exits 0', EXIT_OK, RunHeadless(['-h']));
  AssertEquals('--version exits 0', EXIT_OK, RunHeadless(['--version']));
end;

procedure TClimodeTest.RunHeadless_UsageErrors;
begin
  AssertEquals('missing directory', EXIT_USAGE, RunHeadless(['validate']));
  AssertEquals('missing --chapters value', EXIT_USAGE,
    RunHeadless(['merge', FTempDir, '--chapters']));
  AssertEquals('bad --chapters value', EXIT_USAGE,
    RunHeadless(['merge', FTempDir, '--chapters', 'x,y']));
  AssertEquals('bad --chapters-per-volume value', EXIT_USAGE,
    RunHeadless(['merge', FTempDir, '--chapters-per-volume', 'abc']));
  AssertEquals('unknown convert flag', EXIT_USAGE,
    RunHeadless(['convert-webp', FTempDir, '--bogus']));
end;

procedure TClimodeTest.RunHeadless_UnknownCommand;
begin
  AssertEquals(EXIT_USAGE, RunHeadless(['bogus', FTempDir]));
end;

procedure TClimodeTest.RunHeadless_InvalidDirectory;
begin
  AssertEquals('nonexistent dir', EXIT_ERROR,
    RunHeadless(['validate', FTempDir + 'nope']));
end;

{ validate }

procedure TClimodeTest.RunHeadless_Validate_Ok;
var
  Png: TMemoryStream;
  Args: TStringArray;
begin
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'ok.cbz', [Png], ['p1.png']);
  Png.Free;
  SetLength(Args, 2);
  Args[0] := 'validate';
  Args[1] := FTempDir;
  AssertEquals(EXIT_OK, RunHeadless(Args));
end;

procedure TClimodeTest.RunHeadless_Validate_Corrupt;
var
  FS: TFileStream;
  Args: TStringArray;
begin
  FS := TFileStream.Create(FTempDir + 'bad.cbz', fmCreate);
  FS.WriteBuffer('this is not a zip', 17);
  FS.Free;
  SetLength(Args, 2);
  Args[0] := 'validate';
  Args[1] := FTempDir;
  AssertEquals(EXIT_ERROR, RunHeadless(Args));
end;

{ convert-webp }

procedure TClimodeTest.RunHeadless_ConvertWebp;
var
  Png, Png2: TMemoryStream;
  Args: TStringArray;
  Entries: TZipEntries;
  i: integer;
begin
  { Two DISTINCT streams: TZipper defers reading, so reusing one stream
    would produce an empty second ZIP entry (fixture artifact). }
  Png := CreateNoisePNGStream;
  Png2 := CreateNoisePNGStream;
  CreateCBZ(FTempDir + 'conv.cbz', [Png, Png2], ['p1.png', 'p2.png']);
  Png.Free;
  Png2.Free;
  SetLength(Args, 2);
  Args[0] := 'convert-webp';
  Args[1] := FTempDir;
  AssertEquals(EXIT_OK, RunHeadless(Args));
  AssertTrue('original backed up as _OLD',
    FileExists(FTempDir + 'conv_OLD.cbz'));
  AssertTrue('converted file exists', FileExists(FTempDir + 'conv.cbz'));
  Entries := CollectZipEntries(FTempDir + 'conv.cbz');
  try
    AssertEquals('2 pages', 2, Length(Entries));
    for i := 0 to High(Entries) do
      AssertEquals('page renamed to .webp', '.webp',
        LowerCase(ExtractFileExt(Entries[i].Name)));
  finally
    FreeZipEntries(Entries);
  end;
end;

procedure TClimodeTest.RunHeadless_ConvertWebp_Delete;
var
  Png: TMemoryStream;
  Args: TStringArray;
begin
  Png := CreateNoisePNGStream;
  CreateCBZ(FTempDir + 'conv.cbz', [Png], ['p1.png']);
  Png.Free;
  SetLength(Args, 3);
  Args[0] := 'convert-webp';
  Args[1] := FTempDir;
  Args[2] := '--delete';
  AssertEquals(EXIT_OK, RunHeadless(Args));
  AssertFalse('no _OLD backup with --delete',
    FileExists(FTempDir + 'conv_OLD.cbz'));
  AssertTrue('file still present', FileExists(FTempDir + 'conv.cbz'));
end;

{ cbr-to-cbz }

procedure TClimodeTest.RunHeadless_CbrToCbz;
var
  Png1, Png2, Txt: TMemoryStream;
  Args: TStringArray;
  Names: TStringArray;
begin
  AssertTrue('libarchive present', CbrSupported);
  { A ZIP-format .cbr (libarchive auto-detects): 2 pages + a text file. }
  Png1 := CreateMinimalPNGStream;
  Png2 := CreateMinimalPNGStream;
  Txt := TMemoryStream.Create;
  Txt.WriteAnsiString('credits');
  Txt.Position := 0;
  CreateCBZ(FTempDir + 'comic.cbr', [Png1, Txt, Png2],
    ['page002.png', 'credits.txt', 'page001.png']);
  Png1.Free;
  Png2.Free;
  Txt.Free;

  SetLength(Args, 2);
  Args[0] := 'cbr-to-cbz';
  Args[1] := FTempDir;
  AssertEquals(EXIT_OK, RunHeadless(Args));
  AssertTrue('target .cbz created', FileExists(FTempDir + 'comic.cbz'));
  AssertTrue('source kept by default', FileExists(FTempDir + 'comic.cbr'));
  Names := GetImageFileNames(FTempDir + 'comic.cbz');
  AssertEquals('2 renumbered pages', 2, Length(Names));
  if Length(Names) = 2 then
  begin
    AssertEquals('page_001.png', 'page_001.png', Names[0]);
    AssertEquals('page_002.png', 'page_002.png', Names[1]);
  end;
end;

procedure TClimodeTest.RunHeadless_CbrToCbz_Delete;
var
  Png: TMemoryStream;
  Args: TStringArray;
begin
  AssertTrue('libarchive present', CbrSupported);
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'del.cbr', [Png], ['p1.png']);
  Png.Free;

  SetLength(Args, 3);
  Args[0] := 'cbr-to-cbz';
  Args[1] := FTempDir;
  Args[2] := '--delete';
  AssertEquals(EXIT_OK, RunHeadless(Args));
  AssertTrue('target .cbz created', FileExists(FTempDir + 'del.cbz'));
  AssertFalse('source deleted with --delete', FileExists(FTempDir + 'del.cbr'));
end;

procedure TClimodeTest.RunHeadless_CbrToCbz_SkipsExisting;
var
  Png: TMemoryStream;
  Args: TStringArray;
begin
  AssertTrue('libarchive present', CbrSupported);
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'skip.cbr', [Png], ['p1.png']);
  Png.Free;
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'skip.cbz', [Png], ['existing.png']);
  Png.Free;

  SetLength(Args, 2);
  Args[0] := 'cbr-to-cbz';
  Args[1] := FTempDir;
  { A skipped file is a benign no-op (exit 0), like the reference CLI. }
  AssertEquals(EXIT_OK, RunHeadless(Args));
  AssertEquals('existing target untouched', 1,
    GetImageCount(FTempDir + 'skip.cbz'));
end;

procedure TClimodeTest.RunHeadless_CbrToCbz_UsageError;
var
  Args: TStringArray;
begin
  SetLength(Args, 3);
  Args[0] := 'cbr-to-cbz';
  Args[1] := FTempDir;
  Args[2] := '--force';
  AssertEquals('--force not valid for cbr-to-cbz', EXIT_USAGE,
    RunHeadless(Args));
end;

{ merge }

procedure TClimodeTest.RunHeadless_Merge;var
  Png: TMemoryStream;
  Args: TStringArray;
  i: integer;
begin
  { 8 chapters, no volumes → default CPV 7 → one volume of 7, 1 remaining }
  for i := 1 to 8 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test - %.2d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;
  SetLength(Args, 2);
  Args[0] := 'merge';
  Args[1] := FTempDir;
  AssertEquals(EXIT_OK, RunHeadless(Args));
  AssertTrue('V001 exists', FileExists(FTempDir + 'Test V001.cbz'));
  AssertEquals('V001 has 7 pages', 7,
    GetImageCount(FTempDir + 'Test V001.cbz'));
  for i := 1 to 7 do
    AssertTrue(Format('chapter %d backed up', [i]),
      FileExists(FTempDir + Format('Test - %.2d_OLD.cbz', [i])));
  AssertTrue('chapter 8 remains', FileExists(FTempDir + 'Test - 08.cbz'));
end;

procedure TClimodeTest.RunHeadless_Merge_Force;
var
  Png: TMemoryStream;
  Args: TStringArray;
  i: integer;
begin
  for i := 1 to 8 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test - %.2d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;
  SetLength(Args, 3);
  Args[0] := 'merge';
  Args[1] := FTempDir;
  Args[2] := '--force';
  AssertEquals(EXIT_OK, RunHeadless(Args));
  AssertEquals('V001 absorbs all 8 chapters', 8,
    GetImageCount(FTempDir + 'Test V001.cbz'));
end;

procedure TClimodeTest.RunHeadless_Merge_FlagsBeforeDir;
var
  Png: TMemoryStream;
  Args: TStringArray;
  i: integer;
begin
  { argparse tolerance: flags may precede the directory. }
  for i := 1 to 8 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test - %.2d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;
  SetLength(Args, 3);
  Args[0] := 'merge';
  Args[1] := '--force';
  Args[2] := FTempDir;
  AssertEquals(EXIT_OK, RunHeadless(Args));
  AssertEquals('V001 absorbs all 8 chapters', 8,
    GetImageCount(FTempDir + 'Test V001.cbz'));
end;

procedure TClimodeTest.RunHeadless_Merge_Chapters;
var
  Png: TMemoryStream;
  Args: TStringArray;
  i: integer;
begin
  for i := 1 to 6 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Test - %.2d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;
  SetLength(Args, 4);
  Args[0] := 'merge';
  Args[1] := FTempDir;
  Args[2] := '--chapters';
  Args[3] := '3,3';
  AssertEquals(EXIT_OK, RunHeadless(Args));
  AssertTrue('V001 exists', FileExists(FTempDir + 'Test V001.cbz'));
  AssertTrue('V002 exists', FileExists(FTempDir + 'Test V002.cbz'));
  AssertEquals('V001 has 3 pages', 3,
    GetImageCount(FTempDir + 'Test V001.cbz'));
  AssertEquals('V002 has 3 pages', 3,
    GetImageCount(FTempDir + 'Test V002.cbz'));
end;

procedure TClimodeTest.RunHeadless_Merge_MultiSeries;
var
  Png: TMemoryStream;
  Args: TStringArray;
  i: integer;
begin
  { Two series in one folder; --chapters-per-volume 3 applies to both. }
  for i := 1 to 3 do
  begin
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('One - %.2d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
    Png := CreateMinimalPNGStream;
    CreateCBZ(FTempDir + Format('Two - %.2d.cbz', [i]), [Png],
      [Format('c%d.jpg', [i])]);
    Png.Free;
  end;
  SetLength(Args, 4);
  Args[0] := 'merge';
  Args[1] := FTempDir;
  Args[2] := '--chapters-per-volume';
  Args[3] := '3';
  AssertEquals(EXIT_OK, RunHeadless(Args));
  AssertTrue('One V001 exists', FileExists(FTempDir + 'One V001.cbz'));
  AssertTrue('Two V001 exists', FileExists(FTempDir + 'Two V001.cbz'));
  AssertEquals('One V001 has 3 pages', 3,
    GetImageCount(FTempDir + 'One V001.cbz'));
  AssertEquals('Two V001 has 3 pages', 3,
    GetImageCount(FTempDir + 'Two V001.cbz'));
end;

procedure TClimodeTest.RunHeadless_Merge_NoChapters;
var
  Args: TStringArray;
begin
  SetLength(Args, 2);
  Args[0] := 'merge';
  Args[1] := FTempDir;
  AssertEquals('no chapters is a benign no-op', EXIT_OK, RunHeadless(Args));
end;

procedure TClimodeTest.RunHeadless_Merge_MutuallyExclusive;
var
  Args: TStringArray;
begin
  SetLength(Args, 6);
  Args[0] := 'merge';
  Args[1] := FTempDir;
  Args[2] := '--chapters';
  Args[3] := '2';
  Args[4] := '--chapters-per-volume';
  Args[5] := '2';
  AssertEquals('mutually exclusive flags', EXIT_ERROR, RunHeadless(Args));
end;

initialization
  RegisterTest(TClimodeTest);
end.
