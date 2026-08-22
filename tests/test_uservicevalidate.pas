unit test_uservicevalidate;
{$mode objfpc}{$h+}
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TValidateServiceTest = class(TTestCase)
  private
    FTempDir: string;
    FValidCBZ: string;
    FCorruptCBZ: string;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Validate_ValidFile;
    procedure Validate_InvalidFile;
    procedure ValidateDeep_ValidFile;
    procedure ValidateDeep_CorruptFile;
    procedure ValidateDeep_NoImagesArchive;
    procedure ValidateDeep_AllImagesCorrupt;
    procedure ValidateDeep_ParallelEqualsSequential;
  end;

implementation

uses
  uZipEditor,
  uservicebase,
  uservicevalidate,
  test_helpers,
  FileUtil;

{ TValidateServiceTest }

procedure TValidateServiceTest.SetUp;
var
  Png1, Png2: TMemoryStream;
  Txt: TMemoryStream;
begin
  FTempDir := CreateTempDir('cbzval_');

  { valid.cbz — 2 PNG images (separate streams) }
  Png1 := CreateMinimalPNGStream;
  Png2 := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'valid.cbz', [Png1, Png2], ['page001.png', 'page002.png']);
  Png1.Free;
  Png2.Free;
  FValidCBZ := FTempDir + 'valid.cbz';

  { corrupt.cbz — not actually a ZIP file }
  Txt := TMemoryStream.Create;
  Txt.WriteAnsiString('not a zip file');
  Txt.Position := 0;
  Txt.SaveToFile(FTempDir + 'corrupt.cbz');
  Txt.Free;
  FCorruptCBZ := FTempDir + 'corrupt.cbz';
end;

procedure TValidateServiceTest.TearDown;
begin
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
end;

procedure TValidateServiceTest.Validate_ValidFile;
var
  Files: TStringArray;
  Results: TValidationResults;
begin
  SetLength(Files, 1);
  Files[0] := 'valid.cbz';
  Results := TValidateService.Validate(Files, FTempDir);
  AssertEquals('1 file', 1, Length(Results));
  AssertTrue('valid file marked valid', Results[0].Valid);
  AssertEquals('2 images', 2, Results[0].ImageCount);
  AssertEquals('empty error', '', Results[0].ErrorMsg);
end;

procedure TValidateServiceTest.Validate_InvalidFile;
var
  Files: TStringArray;
  Results: TValidationResults;
begin
  SetLength(Files, 1);
  Files[0] := 'corrupt.cbz';
  Results := TValidateService.Validate(Files, FTempDir);
  AssertEquals('1 file', 1, Length(Results));
  AssertFalse('corrupt file marked invalid', Results[0].Valid);
  AssertTrue('error message set', Results[0].ErrorMsg <> '');
end;

procedure TValidateServiceTest.ValidateDeep_ValidFile;
var
  Files: TStringArray;
  Results: TValidationResults;
begin
  SetLength(Files, 1);
  Files[0] := 'valid.cbz';
  Results := TValidateService.ValidateDeep(Files, FTempDir);
  AssertTrue('deep valid', Results[0].Valid);
  AssertEquals('2 images deep', 2, Results[0].ImageCount);
  AssertEquals('2 image checks', 2, Length(Results[0].ImageChecks));
  AssertTrue('page001 valid', Results[0].ImageChecks[0].Valid);
  AssertTrue('page002 valid', Results[0].ImageChecks[1].Valid);
end;

procedure TValidateServiceTest.ValidateDeep_CorruptFile;
var
  Files: TStringArray;
  Results: TValidationResults;
begin
  SetLength(Files, 1);
  Files[0] := 'corrupt.cbz';
  Results := TValidateService.ValidateDeep(Files, FTempDir);
  AssertFalse('corrupt deep invalid', Results[0].Valid);
  AssertTrue('error message set', Results[0].ErrorMsg <> '');
  AssertEquals('no image checks for corrupt', 1, Length(Results[0].ImageChecks));
  AssertFalse('the one check is invalid', Results[0].ImageChecks[0].Valid);
end;

{ An archive whose entries are all non-images (ComicInfo.xml only, or a stray
  text page) decodes zero images yet is still a well-formed CBZ: report
  valid/empty rather than a corruption failure. Mirrors the Python reference
  model and guards the ValidateDeep empty-archive branch of L2. }
procedure TValidateServiceTest.ValidateDeep_NoImagesArchive;
var
  Txt: TMemoryStream;
  Files: TStringArray;
  R1, R4: TValidationResults;
begin
  { A single text entry (plus ComicInfo.xml) — entries present but no image. }
  Txt := TMemoryStream.Create;
  Txt.WriteAnsiString('not an image');
  Txt.Position := 0;
  CreateCBZ(FTempDir + 'noimage.cbz', [Txt], ['notes.txt']);
  Txt.Free;

  SetLength(Files, 1);
  Files[0] := 'noimage.cbz';
  R1 := TValidateService.ValidateDeep(Files, FTempDir, nil, 1);
  R4 := TValidateService.ValidateDeep(Files, FTempDir, nil, 4);

  AssertEquals('zero images', 0, R1[0].ImageCount);
  AssertTrue('entries-but-no-images is valid', R1[0].Valid);
  AssertEquals('empty message', 'No images found', R1[0].ErrorMsg);
  { Threads must agree on the valid/empty status. }
  AssertEquals('same valid flag', R1[0].Valid, R4[0].Valid);
  AssertEquals('same error', R1[0].ErrorMsg, R4[0].ErrorMsg);
end;

{ An archive with image-extension entries that all fail to decode is a genuine
  failure: invalid, with the "All images failed to decode" summary. This is a
  different branch from the no-entries case above and ensures the two are not
  conflated (e.g. a non-image byte stored as a .png still reports corruption). }
procedure TValidateServiceTest.ValidateDeep_AllImagesCorrupt;
var
  Garbage: TMemoryStream;
  Files: TStringArray;
  R2: TValidationResults;
begin
  Garbage := TMemoryStream.Create;
  Garbage.WriteAnsiString('this is not an image');
  Garbage.Position := 0;
  { Named with an image extension so it lands in the decode checks. }
  CreateCBZ(FTempDir + 'corruptimg.cbz', [Garbage], ['broken.png']);
  Garbage.Free;

  SetLength(Files, 1);
  Files[0] := 'corruptimg.cbz';
  { No ComicInfo.xml here so the single broken page is the only archive entry. }
  R2 := TValidateService.ValidateDeep(Files, FTempDir, nil, 1);

  { No image decoded -> ImageCount is the count of successes (0), yet one
    decode was attempted so there is a single failed check. }
  AssertEquals('zero successful decodes', 0, R2[0].ImageCount);
  AssertEquals('one decode attempt', 1, Length(R2[0].ImageChecks));
  AssertFalse('all-corrupt archive is invalid', R2[0].Valid);
  AssertEquals('corrupt message', 'All images failed to decode', R2[0].ErrorMsg);
end;

{ Parallel deep validation must produce identical per-image checks to the
  sequential run: the pool writes each check into its own slot and the
  results are assembled in archive order after the join. }
procedure TValidateServiceTest.ValidateDeep_ParallelEqualsSequential;
var
  Pngs: array[0..5] of TMemoryStream;
  Garbage, Xml: TMemoryStream;
  i: integer;
  Files: TStringArray;
  R1, R4: TValidationResults;
begin
  { 6 noise pages + a ComicInfo.xml + a fake image (decode failure). }
  for i := 0 to 5 do
    Pngs[i] := CreateNoisePNGStream;
  Xml := TMemoryStream.Create;
  Xml.WriteAnsiString('<ComicInfo/>');
  Xml.Position := 0;
  Garbage := TMemoryStream.Create;
  Garbage.WriteAnsiString('this is not an image');
  Garbage.Position := 0;
  CreateCBZ(FTempDir + 'par.cbz',
    [Pngs[0], Pngs[1], Xml, Garbage, Pngs[2], Pngs[3], Pngs[4], Pngs[5]],
    ['p01.png', 'p02.png', 'ComicInfo.xml', 'broken.png', 'p03.png',
     'p04.png', 'p05.png', 'p06.png']);
  for i := 0 to 5 do Pngs[i].Free;
  Xml.Free;
  Garbage.Free;

  SetLength(Files, 1);
  Files[0] := 'par.cbz';
  R1 := TValidateService.ValidateDeep(Files, FTempDir, nil, 1);
  R4 := TValidateService.ValidateDeep(Files, FTempDir, nil, 4);

  AssertEquals('same valid flag', R1[0].Valid, R4[0].Valid);
  AssertEquals('same image count', R1[0].ImageCount, R4[0].ImageCount);
  AssertEquals('same error', R1[0].ErrorMsg, R4[0].ErrorMsg);
  AssertEquals('same check count', Length(R1[0].ImageChecks),
    Length(R4[0].ImageChecks));
  for i := 0 to High(R1[0].ImageChecks) do
  begin
    AssertEquals('check name', R1[0].ImageChecks[i].EntryName,
      R4[0].ImageChecks[i].EntryName);
    AssertEquals('check valid', R1[0].ImageChecks[i].Valid,
      R4[0].ImageChecks[i].Valid);
  end;
  { 6 good pages decode, the broken one fails. }
  AssertEquals('6 valid images', 6, R1[0].ImageCount);
end;

initialization
  RegisterTest(TValidateServiceTest);
end.
