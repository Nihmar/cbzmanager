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

initialization
  RegisterTest(TValidateServiceTest);
end.
