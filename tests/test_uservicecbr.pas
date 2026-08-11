unit test_uservicecbr;
{$mode objfpc}{$h+}
{ Batch CBR-to-CBZ conversion service (TConvertCbrService) — parallel
  worker-pool equivalence.  The Threads option must plumb through and the
  output must be byte-identical regardless of the pool size. }
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TCbrServiceTest = class(TTestCase)
  private
    FTempDir: string;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Convert_ParallelEqualsSequential;
    procedure Convert_ParallelSkipsExisting;
    procedure Convert_ParallelDeletesSource;
  end;

implementation

uses
  uzipcore,
  uZipEditor,
  uarchive,
  uservicebase,
  userviceconvert,
  uservicecbr,
  test_helpers,
  FileUtil;

procedure TCbrServiceTest.SetUp;
begin
  FTempDir := CreateTempDir('cbzcbr_');
end;

procedure TCbrServiceTest.TearDown;
begin
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
end;

{ Build a ZIP-format .cbr from two pages plus a text file (libarchive
  auto-detects the container, so the whole CBR pipeline works without a
  RAR compressor).  Returns the filename. }
function MakeCbrFixture(const ADir, AName: string): string;
var
  Png1, Png2, Txt: TMemoryStream;
begin
  Png1 := CreateMinimalPNGStream;
  Png2 := CreateMinimalPNGStream;
  Txt := TMemoryStream.Create;
  Txt.WriteAnsiString('credits');
  Txt.Position := 0;
  CreateCBZ(ADir + AName, [Png1, Txt, Png2],
    ['page002.png', 'credits.txt', 'page001.png']);
  Png1.Free;
  Png2.Free;
  Txt.Free;
  Result := AName;
end;

procedure TCbrServiceTest.Convert_ParallelEqualsSequential;
var
  Files: TStringArray;
  Opts: TCbrConvertOptions;
  Results: TConvertResults;
  Msg: string;
begin
  AssertTrue('libarchive present', CbrSupported);

  { Two identical sources: one converted sequentially, one with a
    4-worker pool. }
  MakeCbrFixture(FTempDir, 'seq.cbr');
  MakeCbrFixture(FTempDir, 'par.cbr');

  Opts.SkipExisting := True;
  Opts.DeleteSource := False;

  SetLength(Files, 1);
  Files[0] := 'seq.cbr';
  Opts.Threads := 1;
  Results := TConvertCbrService.Convert(Files, FTempDir, Opts);
  AssertEquals('seq converted', 2, Results[0].PagesConverted);

  Files[0] := 'par.cbr';
  Opts.Threads := 4;
  Results := TConvertCbrService.Convert(Files, FTempDir, Opts);
  AssertEquals('par converted', 2, Results[0].PagesConverted);

  { Compared by entry content — raw archive bytes carry TZipper's write
    timestamp, so a byte comparison would flake across second boundaries. }
  AssertTrue('identical archives by content',
    ZipFilesEqual(FTempDir + 'seq.cbz', FTempDir + 'par.cbz', Msg));
end;

procedure TCbrServiceTest.Convert_ParallelSkipsExisting;
var
  Png: TMemoryStream;
  Files: TStringArray;
  Opts: TCbrConvertOptions;
  Results: TConvertResults;
begin
  AssertTrue('libarchive present', CbrSupported);

  MakeCbrFixture(FTempDir, 'skip.cbr');
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'skip.cbz', [Png], ['existing.png']);
  Png.Free;

  Opts.SkipExisting := True;
  Opts.DeleteSource := False;
  Opts.Threads := 4;

  SetLength(Files, 1);
  Files[0] := 'skip.cbr';
  Results := TConvertCbrService.Convert(Files, FTempDir, Opts);
  AssertTrue('skipped is a success', Results[0].Success);
  AssertEquals('no pages written', 0, Results[0].PagesConverted);
  AssertEquals('existing target untouched', 1,
    GetImageCount(FTempDir + 'skip.cbz'));
end;

procedure TCbrServiceTest.Convert_ParallelDeletesSource;
var
  Files: TStringArray;
  Opts: TCbrConvertOptions;
  Results: TConvertResults;
begin
  AssertTrue('libarchive present', CbrSupported);

  MakeCbrFixture(FTempDir, 'del.cbr');

  Opts.SkipExisting := True;
  Opts.DeleteSource := True;
  Opts.Threads := 4;

  SetLength(Files, 1);
  Files[0] := 'del.cbr';
  Results := TConvertCbrService.Convert(Files, FTempDir, Opts);
  AssertTrue('converted', Results[0].Success);
  AssertTrue('target .cbz created', FileExists(FTempDir + 'del.cbz'));
  AssertFalse('source deleted', FileExists(FTempDir + 'del.cbr'));
end;

initialization
  RegisterTest(TCbrServiceTest);
end.
