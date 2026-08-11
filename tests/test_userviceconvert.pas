unit test_userviceconvert;
{$mode objfpc}{$h+}
{ Batch WebP conversion service (TConvertService) — parallel worker pool
  equivalence.  The Threads option must plumb through to ConvertCBZToWebP
  and the output must be byte-identical regardless of the pool size. }
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TConvertServiceTest = class(TTestCase)
  private
    FTempDir: string;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Convert_ParallelEqualsSequential;
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
  F1, F2: TMemoryStream;
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

  F1 := TMemoryStream.Create;
  F2 := TMemoryStream.Create;
  try
    F1.LoadFromFile(FTempDir + 'seq.cbz');
    F2.LoadFromFile(FTempDir + 'par.cbz');
    AssertEquals('same output size', F1.Size, F2.Size);
    if F1.Size > 0 then
      AssertTrue('byte-identical output',
        CompareMem(F1.Memory, F2.Memory, F1.Size));
  finally
    F1.Free;
    F2.Free;
  end;
end;

initialization
  RegisterTest(TConvertServiceTest);
end.
