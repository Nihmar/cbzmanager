unit uZipEditor;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, IntfGraphics;

{ Prima pagina del CBZ come TLazIntfImage (sola memoria, nessuna GDI):
  invocabile da thread secondari. nil se il file non contiene immagini
  leggibili. Il chiamante e' proprietario dell'oggetto restituito. }
function GetFirstImageAsIntfImage(const FileName: string): TLazIntfImage;
function GetImageCount(const FileName: string): integer;
function GetImageFileNames(const FileName: string): TStringArray;
function IsValidCBZ(const FileName: string): boolean;

implementation

uses
  Zipper, FileUtil, uImgUtil, uWebP, uLog;

function IsImageExt(const Ext: string): boolean;
begin
  Result := SameText(Ext, '.png') or SameText(Ext, '.jpg') or
    SameText(Ext, '.jpeg') or SameText(Ext, '.bmp') or SameText(Ext, '.gif') or
    SameText(Ext, '.webp');
end;

function ExtractEntryToStream(const FileName, EntryName: string): TMemoryStream;
var
  UnZipper: TUnZipper;
  TempDir: string;
  TempFile: string;
begin
  Result := nil;
  TempDir := SysUtils.GetTempDir + 'cbz_' + IntToHex(Random(MaxInt), 8);
  CreateDir(TempDir);

  UnZipper := TUnZipper.Create;
  try
    UnZipper.FileName := FileName;
    UnZipper.OutputPath := TempDir;
    UnZipper.Examine;
    UnZipper.UnZipFile(EntryName);

    TempFile := IncludeTrailingPathDelimiter(TempDir) + EntryName;
    if FileExists(TempFile) then
    begin
      Result := TMemoryStream.Create;
      Result.LoadFromFile(TempFile);
      Result.Position := 0;
      Log('Extract: %s -> %d byte', [EntryName, Result.Size]);
    end
    else
      Log('Extract: FALLITO, %s non creato', [TempFile]);
  finally
    UnZipper.Free;
  end;

  DeleteDirectory(TempDir, False);
end;

function GetFirstImageAsIntfImage(const FileName: string): TLazIntfImage;
var
  Names: TStringArray;
  i: integer;
  Stream: TMemoryStream;
  Ext: string;
begin
  Result := nil;
  Names := GetImageFileNames(FileName);
  Log('GetFirstImage: %s -> %d immagini', [ExtractFileName(FileName), Length(Names)]);
  for i := 0 to Length(Names) - 1 do
  begin
    Ext := ExtractFileExt(Names[i]);
    if IsImageExt(Ext) then
    begin
      Stream := ExtractEntryToStream(FileName, Names[i]);
      if Stream = nil then
      begin
        Log('GetFirstImage: stream nil per %s', [Names[i]]);
        Break;
      end;
      try
        if SameText(Ext, '.webp') then
          Result := WebPToIntfImage(Stream.Memory, Stream.Size)
        else
          Result := StreamToIntfImage(Stream, ReaderClassForExt(Ext));
      except
        on E: Exception do
        begin
          Log('GetFirstImage: decodifica fallita (%s): %s: %s',
            [Ext, E.ClassName, E.Message]);
          Result := nil;
        end;
      end;
      Stream.Free;
      if Result = nil then
        Log('GetFirstImage: RISULTATO NIL per %s', [Names[i]])
      else
        Log('GetFirstImage: OK %dx%d', [Result.Width, Result.Height]);
      Break;
    end;
  end;
end;

function GetImageCount(const FileName: string): integer;
var
  UnZipper: TUnZipper;
  i: integer;
begin
  Result := 0;
  UnZipper := TUnZipper.Create;
  try
    UnZipper.FileName := FileName;
    UnZipper.Examine;
    for i := 0 to UnZipper.Entries.Count - 1 do
      if IsImageExt(ExtractFileExt(UnZipper.Entries[i].ArchiveFileName)) then
        Inc(Result);
  finally
    UnZipper.Free;
  end;
end;

function GetImageFileNames(const FileName: string): TStringArray;
var
  UnZipper: TUnZipper;
  i, ImgCnt: integer;
begin
  Result := nil;
  UnZipper := TUnZipper.Create;
  try
    UnZipper.FileName := FileName;
    UnZipper.Examine;
    ImgCnt := 0;
    for i := 0 to UnZipper.Entries.Count - 1 do
      if IsImageExt(ExtractFileExt(UnZipper.Entries[i].ArchiveFileName)) then
      begin
        SetLength(Result, ImgCnt + 1);
        Result[ImgCnt] := UnZipper.Entries[i].ArchiveFileName;
        Inc(ImgCnt);
      end;
  finally
    UnZipper.Free;
  end;
end;

function IsValidCBZ(const FileName: string): boolean;
begin
  Result := GetImageCount(FileName) > 0;
end;

end.
