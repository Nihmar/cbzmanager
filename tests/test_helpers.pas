unit test_helpers;
{$mode objfpc}{$h+}
interface
uses
  Classes, SysUtils;

{ Build a minimal valid 1x1 pixel red RGBA PNG in memory (70 bytes). }
function CreateMinimalPNGStream: TMemoryStream;

{ Build a 64x64 noise PNG — large enough that the WebP conversion is
  deterministically smaller, so conversion tests assert real conversions.
  The noise is seeded (RandSeed = 12345), so every call returns identical
  pixels. }
function CreateNoisePNGStream: TMemoryStream;

{ Compares two CBZ archives by entry content (names + data bytes), ignoring
  ZIP metadata.  Deterministic tests must NOT compare raw archive bytes:
  TZipper stamps the current time into the headers, so two writes of the
  same entries can differ whenever they straddle a second boundary.
  Returns False with a description in AMsg on the first mismatch. }
function ZipFilesEqual(const A, B: string; out AMsg: string): boolean;

{ Build a CBZ file at APath from memory streams with given names. }
procedure CreateCBZ(const APath: string; const Entries: array of TMemoryStream;
  const Names: array of string);

{ Create a temporary directory for test files. Returns trailing-slash path. }
function CreateTempDir(const Prefix: string): string;

implementation

uses
  Zipper,
  FPImage,
  FPWritePNG,
  uzipcore;

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

function ZipFilesEqual(const A, B: string; out AMsg: string): boolean;
var
  EA, EB: TZipEntries;
  i: integer;
begin
  Result := False;
  EA := CollectZipEntries(A);
  try
    EB := CollectZipEntries(B);
    try
      if Length(EA) <> Length(EB) then
      begin
        AMsg := Format('entry count differs: %d vs %d',
          [Length(EA), Length(EB)]);
        Exit;
      end;
      for i := 0 to High(EA) do
      begin
        if EA[i].Name <> EB[i].Name then
        begin
          AMsg := Format('entry %d name differs: "%s" vs "%s"',
            [i, EA[i].Name, EB[i].Name]);
          Exit;
        end;
        if EA[i].Data.Size <> EB[i].Data.Size then
        begin
          AMsg := Format('entry %d size differs: %d vs %d',
            [i, EA[i].Data.Size, EB[i].Data.Size]);
          Exit;
        end;
        if not CompareMem(EA[i].Data.Memory, EB[i].Data.Memory,
          EA[i].Data.Size) then
        begin
          AMsg := Format('entry %d data differs (%s)', [i, EA[i].Name]);
          Exit;
        end;
      end;
      Result := True;
      AMsg := '';
    finally
      FreeZipEntries(EB);
    end;
  finally
    FreeZipEntries(EA);
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
