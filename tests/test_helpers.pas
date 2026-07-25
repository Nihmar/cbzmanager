unit test_helpers;
{$mode objfpc}{$h+}
interface
uses
  Classes, SysUtils;

{ Build a minimal valid 1x1 pixel red RGBA PNG in memory (70 bytes). }
function CreateMinimalPNGStream: TMemoryStream;

{ Build a CBZ file at APath from memory streams with given names. }
procedure CreateCBZ(const APath: string; const Entries: array of TMemoryStream;
  const Names: array of string);

{ Create a temporary directory for test files. Returns trailing-slash path. }
function CreateTempDir(const Prefix: string): string;

implementation

uses
  Zipper;

const
  { Minimal 1x1 red RGBA PNG, generated with Python }
  TEST_PNG: array[0..69] of byte = (
    $89, $50, $4e, $47, $0d, $0a, $1a, $0a, $00, $00, $00, $0d,
    $49, $48, $44, $52, $00, $00, $00, $01, $00, $00, $00, $01,
    $08, $06, $00, $00, $00, $1f, $15, $c4, $89, $00, $00, $00,
    $0d, $49, $44, $41, $54, $78, $9c, $63, $f8, $cf, $c0, $f0,
    $1f, $00, $05, $00, $01, $ff, $89, $99, $3d, $1d, $00, $00,
    $00, $00, $49, $45, $4e, $44, $ae, $42, $60, $82
  );

function CreateMinimalPNGStream: TMemoryStream;
begin
  Result := TMemoryStream.Create;
  Result.Write(TEST_PNG[0], Length(TEST_PNG));
  Result.Position := 0;
end;

procedure CreateCBZ(const APath: string; const Entries: array of TMemoryStream;
  const Names: array of string);
var
  ZW: TZipper;
  ZEntries: TZipFileEntries;
  i: integer;
begin
  ZW := TZipper.Create;
  try
    ZEntries := TZipFileEntries.Create(TZipFileEntry);
    try
      for i := 0 to High(Entries) do
      begin
        Entries[i].Position := 0;
        ZEntries.AddFileEntry(Entries[i], Names[i]);
      end;
      ZW.ZipFiles(APath, ZEntries);
    finally
      ZEntries.Free;
    end;
  finally
    ZW.Free;
  end;
end;

function CreateTempDir(const Prefix: string): string;
var
  Guid: TGuid;
begin
  CreateGUID(Guid);
  Result := GetTempDir + Prefix + Copy(GuidToString(Guid), 2, 36) + PathDelim;
  CreateDir(Result);
end;

end.
