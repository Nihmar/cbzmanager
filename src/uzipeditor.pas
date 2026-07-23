unit uZipEditor;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Graphics;

function GetFirstImageAsBitmap(const FileName: string): TBitmap;
function GetImageCount(const FileName: string): Integer;
function GetImageFileNames(const FileName: string): TStringArray;
function IsValidCBZ(const FileName: string): Boolean;

implementation

uses
  Zipper,
  FPImage, FPReadJPEG, FPReadPNG, FPReadBMP, FPReadGIF,
  FileUtil, uWebP;

function IsImageExt(const Ext: string): Boolean;
begin
  Result := SameText(Ext, '.png') or SameText(Ext, '.jpg')
    or SameText(Ext, '.jpeg') or SameText(Ext, '.bmp')
    or SameText(Ext, '.gif') or SameText(Ext, '.webp');
end;

// Load an image from a file path (extracted ZIP entry) into a TBitmap
// using FPImage readers. Returns nil on failure.
function StreamToBitmap(Stream: TStream; const Ext: string): TBitmap;
var
  ReaderClass: TFPCustomImageReaderClass;
  Reader: TFPCustomImageReader;
  MemImg: TFPMemoryImage;
  x, y: Integer;
  SrcColor: TFPColor;
begin
  Result := nil;
  ReaderClass := nil;

  if SameText(Ext, '.jpg') or SameText(Ext, '.jpeg') then
    ReaderClass := TFPReaderJPEG
  else if SameText(Ext, '.png') then
    ReaderClass := TFPReaderPNG
  else if SameText(Ext, '.bmp') then
    ReaderClass := TFPReaderBMP
  else if SameText(Ext, '.gif') then
    ReaderClass := TFPReaderGIF;

  if ReaderClass = nil then Exit;

  Reader := ReaderClass.Create;
  try
    MemImg := TFPMemoryImage.Create(0, 0);
    try
      Stream.Position := 0;
      MemImg.LoadFromStream(Stream, Reader);
      Result := TBitmap.Create;
      Result.PixelFormat := pf24bit;
      Result.SetSize(MemImg.Width, MemImg.Height);
      for y := 0 to MemImg.Height - 1 do
        for x := 0 to MemImg.Width - 1 do
        begin
          SrcColor := MemImg.Colors[x, y];
          Result.Canvas.Pixels[x, y] := RGBToColor(
            SrcColor.Red shr 8,
            SrcColor.Green shr 8,
            SrcColor.Blue shr 8
          );
        end;
    finally
      MemImg.Free;
    end;
  finally
    Reader.Free;
  end;
end;

function ExtractEntryToStream(const FileName, EntryName: string): TMemoryStream;
var
  UnZipper: TUnZipper;
  TempDir: string;
  TempFile: string;
begin
  Result := nil;
  TempDir := SysUtils.GetTempDir + 'cbz_'
    + IntToHex(Random(MaxInt), 8);
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
    end;
  finally
    UnZipper.Free;
  end;

  DeleteDirectory(TempDir, False);
end;

function GetFirstImageAsBitmap(const FileName: string): TBitmap;
var
  Names: TStringArray;
  i: Integer;
  Stream: TMemoryStream;
  Ext: string;
begin
  Result := nil;
  Names := GetImageFileNames(FileName);
  for i := 0 to Length(Names) - 1 do
  begin
    Ext := ExtractFileExt(Names[i]);
    if IsImageExt(Ext) then
    begin
      Stream := ExtractEntryToStream(FileName, Names[i]);
      if Stream <> nil then
      begin
        if SameText(Ext, '.webp') then
          Result := WebPToBitmap(Stream.Memory, Stream.Size)
        else
          Result := StreamToBitmap(Stream, Ext);
        Stream.Free;
      end;
      Break;
    end;
  end;
end;

function GetImageCount(const FileName: string): Integer;
var
  UnZipper: TUnZipper;
  i: Integer;
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
  i, ImgCnt: Integer;
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

function IsValidCBZ(const FileName: string): Boolean;
begin
  Result := GetImageCount(FileName) > 0;
end;

end.

