unit test_userviceconvert;
{$mode objfpc}{$h+}
{ Batch WebP conversion service (TConvertService) — parallel worker pool
  equivalence.  The Threads option must plumb through to ConvertCBZToWebP
  and the output must be byte-identical regardless of the pool size. }
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils, IntfGraphics, FPImage, GraphType;

type
  TConvertServiceTest = class(TTestCase)
  private
    FTempDir: string;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Convert_ParallelEqualsSequential;
    procedure Convert_RenamesOnly_StillWrites;
  end;

implementation

uses
  uzipcore,
  uZipEditor,
  uWebP,
  uservicebase,
  userviceconvert,
  test_helpers,
  FileUtil;

procedure TConvertServiceTest.SetUp;
begin
  FTempDir := CreateTempDir('cbzsvc_');
end;

procedure TConvertServiceTest.TearDown;
begin
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
end;

procedure TConvertServiceTest.Convert_ParallelEqualsSequential;
var
  Png1, Png2, Png3: TMemoryStream;
  Files: TStringArray;
  Opts: TConvertOptions;
  Results: TConvertResults;
  Msg: string;
begin
  if not WebPAvailable then Exit;   { degraded env: nothing to convert }

  { Two identical sources (seeded noise): one converted sequentially, one
    with a 4-worker pool. }
  Png1 := CreateNoisePNGStream;
  Png2 := CreateNoisePNGStream;
  Png3 := CreateNoisePNGStream;
  CreateCBZ(FTempDir + 'seq.cbz', [Png1, Png2, Png3],
    ['page_001.png', 'page_002.png', 'page_003.png']);
  Png1.Free; Png2.Free; Png3.Free;

  Png1 := CreateNoisePNGStream;
  Png2 := CreateNoisePNGStream;
  Png3 := CreateNoisePNGStream;
  CreateCBZ(FTempDir + 'par.cbz', [Png1, Png2, Png3],
    ['page_001.png', 'page_002.png', 'page_003.png']);
  Png1.Free; Png2.Free; Png3.Free;

  Opts.Quality := 75;
  Opts.ReplaceOnlyIfSmaller := True;
  Opts.SkipExistingWebP := True;
  Opts.RemoveComicInfo := True;
  Opts.RenumberPages := True;
  Opts.BackupOld := False;

  SetLength(Files, 1);
  Files[0] := 'seq.cbz';
  Opts.Threads := 1;
  Results := TConvertService.Convert(Files, FTempDir, Opts);
  AssertEquals('seq converted', 3, Results[0].PagesConverted);

  Files[0] := 'par.cbz';
  Opts.Threads := 4;
  Results := TConvertService.Convert(Files, FTempDir, Opts);
  AssertEquals('par converted', 3, Results[0].PagesConverted);

  { Compared by entry content — raw archive bytes carry TZipper's write
    timestamp, so a byte comparison would flake across second boundaries. }
  AssertTrue('identical archives by content',
    ZipFilesEqual(FTempDir + 'seq.cbz', FTempDir + 'par.cbz', Msg));
end;

{ Regression for bughunt L1: Modified was computed but never consumed, so a
  batch that only renamed pages / stripped ComicInfo.xml (no WebP conversion,
  e.g. an already-all-WebP archive) was left untouched with "Already up to
  date" even though the options asked for both operations. }
procedure TConvertServiceTest.Convert_RenamesOnly_StillWrites;

  function MakeWebPStream: TMemoryStream;
  var
    Img: TLazIntfImage;
    Desc: TRawImageDescription;
    x, y: integer;
    C: TFPColor;
  begin
    Desc.Init_BPP32_B8G8R8A8_BIO_TTB(4, 4);
    Img := TLazIntfImage.Create(0, 0);
    Img.DataDescription := Desc;
    C.Red := 61440; C.Green := 30720; C.Blue := 15360; C.Alpha := 65535;
    for y := 0 to 3 do
      for x := 0 to 3 do
        Img.Colors[x, y] := C;
    Result := IntfImageToWebP(Img, 75);
    Img.Free;
  end;

  function MakeComicInfoStream: TMemoryStream;
  const
    XML = '<?xml version="1.0"?><ComicInfo><Series>T</Series></ComicInfo>';
  begin
    Result := TMemoryStream.Create;
    Result.WriteBuffer(XML[1], Length(XML));
  end;

var
  S1, S2, S3: TMemoryStream;
  Files: TStringArray;
  Opts: TConvertOptions;
  Results: TConvertResults;
  Entries: TZipEntries;
  i: integer;
  FoundComicInfo, FoundPage1, FoundPage2: boolean;
begin
  if not WebPAvailable then Exit;   { degraded env: cannot build webp entries }

  { All-WebP archive with SkipExistingWebP=True -> zero conversions, but the
    names need renumbering and ComicInfo.xml must go. }
  S1 := MakeWebPStream;
  S2 := MakeWebPStream;
  S3 := MakeComicInfoStream;
  CreateCBZ(FTempDir + 'renames.cbz', [S1, S2, S3],
    ['a.webp', 'b.webp', 'ComicInfo.xml']);
  S1.Free; S2.Free; S3.Free;

  Opts.Quality := 75;
  Opts.ReplaceOnlyIfSmaller := True;
  Opts.SkipExistingWebP := True;
  Opts.RemoveComicInfo := True;
  Opts.RenumberPages := True;
  Opts.BackupOld := False;
  Opts.Threads := 1;

  SetLength(Files, 1);
  Files[0] := 'renames.cbz';
  Results := TConvertService.Convert(Files, FTempDir, Opts);

  AssertTrue('success', Results[0].Success);
  AssertEquals('zero conversions', 0, Results[0].PagesConverted);

  Entries := CollectZipEntries(FTempDir + 'renames.cbz');
  try
    AssertEquals('comicinfo stripped', 2, Length(Entries));
    FoundComicInfo := False;
    FoundPage1 := False;
    FoundPage2 := False;
    for i := 0 to High(Entries) do
    begin
      if SameText(Entries[i].Name, 'ComicInfo.xml') then FoundComicInfo := True;
      if Entries[i].Name = 'page_0001.webp' then FoundPage1 := True;
      if Entries[i].Name = 'page_0002.webp' then FoundPage2 := True;
    end;
    AssertFalse('comicinfo gone', FoundComicInfo);
    AssertTrue('renamed page_0001.webp', FoundPage1);
    AssertTrue('renamed page_0002.webp', FoundPage2);
  finally
    FreeZipEntries(Entries);
  end;
end;

initialization
  RegisterTest(TConvertServiceTest);
end.
