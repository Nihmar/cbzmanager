unit test_uservicecomicinfo;
{$mode objfpc}{$h+}
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TComicInfoServiceTest = class(TTestCase)
  private
    FTempDir: string;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Scan_HasComicInfo;
    procedure Scan_NoComicInfo;
    procedure Remove_RemovesComicInfo;
    procedure Remove_BackupCreated;
  end;

implementation

uses
  uZipEditor,
  uservicebase,
  uservicecomicinfo,
  test_helpers,
  FileUtil;

{ TComicInfoServiceTest }

procedure TComicInfoServiceTest.SetUp;
var
  Png: TMemoryStream;
  Xml: TMemoryStream;
begin
  FTempDir := CreateTempDir('cbzci_');

  { with_ci.cbz — 1 PNG + 1 XML }
  Png := CreateMinimalPNGStream;
  Xml := TMemoryStream.Create;
  Xml.WriteAnsiString('<ComicInfo><Series>Test</Series></ComicInfo>');
  Xml.Position := 0;
  CreateCBZ(FTempDir + 'with_ci.cbz', [Png, Xml], ['page001.jpg', 'ComicInfo.xml']);
  Png.Free;
  Xml.Free;

  { no_ci.cbz — 1 PNG only }
  Png := CreateMinimalPNGStream;
  CreateCBZ(FTempDir + 'no_ci.cbz', [Png], ['page001.jpg']);
  Png.Free;
end;

procedure TComicInfoServiceTest.TearDown;
begin
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
end;

procedure TComicInfoServiceTest.Scan_HasComicInfo;
var
  Files: TStringArray;
  Results: TComicInfoResults;
begin
  SetLength(Files, 1);
  Files[0] := 'with_ci.cbz';
  Results := TComicInfoService.Scan(Files, FTempDir);
  AssertEquals('1 result', 1, Length(Results));
  AssertTrue('has ComicInfo', Results[0].HasComicInfo);
  AssertEquals('no error', '', Results[0].Error);
end;

procedure TComicInfoServiceTest.Scan_NoComicInfo;
var
  Files: TStringArray;
  Results: TComicInfoResults;
begin
  SetLength(Files, 1);
  Files[0] := 'no_ci.cbz';
  Results := TComicInfoService.Scan(Files, FTempDir);
  AssertFalse('no ComicInfo', Results[0].HasComicInfo);
end;

procedure TComicInfoServiceTest.Remove_RemovesComicInfo;
var
  Files: TStringArray;
  Results: TComicInfoResults;
  ScanAfter: TComicInfoResults;
  ImgCount: integer;
begin
  SetLength(Files, 1);
  Files[0] := 'with_ci.cbz';
  Results := TComicInfoService.Remove(Files, FTempDir, False);
  AssertTrue('removed', Results[0].Removed);
  AssertEquals('no error', '', Results[0].Error);

  { Verify ComicInfo.xml is gone }
  ScanAfter := TComicInfoService.Scan(Files, FTempDir);
  AssertFalse('no ComicInfo after remove', ScanAfter[0].HasComicInfo);

  { Verify image is still there }
  ImgCount := GetImageCount(FTempDir + 'with_ci.cbz');
  AssertEquals('1 image remains', 1, ImgCount);
end;

procedure TComicInfoServiceTest.Remove_BackupCreated;
var
  Files: TStringArray;
  Results: TComicInfoResults;
begin
  SetLength(Files, 1);
  Files[0] := 'with_ci.cbz';
  Results := TComicInfoService.Remove(Files, FTempDir, True);
  AssertTrue('removed with backup', Results[0].Removed);

  { Backup should exist }
  AssertTrue('backup created',
    FileExists(FTempDir + 'with_ci_OLD.cbz'));
end;

initialization
  RegisterTest(TComicInfoServiceTest);
end.
