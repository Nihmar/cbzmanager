unit uImgUtil;

{
  Decodifica immagini in TLazIntfImage: sola memoria, nessuna chiamata GDI.
  Utilizzabile quindi anche da thread secondari, a differenza di TBitmap.

  La conversione in TBitmap (IntfToBitmap) tocca il widgetset e va invocata
  esclusivamente dal thread principale.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Graphics,
  FPImage,
  IntfGraphics,
  Math;

{ Restituisce la classe di reader adatta all'estensione, nil se non gestita.
  Il WebP non e' incluso: se ne occupa uWebP. }
function ReaderClassForExt(const Ext: string): TFPCustomImageReaderClass;

{ Decodifica lo stream (dall'inizio) nel formato indicato. nil se fallisce. }
function StreamToIntfImage(Stream: TStream;
  ReaderClass: TFPCustomImageReaderClass): TLazIntfImage;

{ Come sopra, leggendo da file. }
function FileToIntfImage(const FileName: string;
  ReaderClass: TFPCustomImageReaderClass): TLazIntfImage;

{ SOLO MAIN THREAD: crea un TBitmap a partire da una TLazIntfImage. }
function IntfToBitmap(Src: TLazIntfImage): TBitmap;

{ SOLO MAIN THREAD: IntfToBitmap e Canvas toccano il widgetset. }
function MakeThumb(Src: TLazIntfImage; W, H: integer): TBitmap;

function IsImageExt(const Ext: string): boolean;

implementation

uses
  FPReadJPEG, FPReadPNG, FPReadBMP, FPReadGIF, GraphType, LCLType;

function IsImageExt(const Ext: string): boolean;
begin
  Result := SameText(Ext, '.png') or SameText(Ext, '.jpg') or
    SameText(Ext, '.jpeg') or SameText(Ext, '.bmp') or SameText(Ext, '.gif') or
    SameText(Ext, '.webp');
end;

function MakeThumb(Src: TLazIntfImage; W, H: integer): TBitmap;
var
  F: double;
  DW, DH: integer;
  Full: TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(W, H);
  Result.Canvas.Brush.Color := clWindow;
  Result.Canvas.FillRect(0, 0, W, H);
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;

  Full := IntfToBitmap(Src);
  if Full = nil then Exit;
  try
    F := Min(W / Full.Width, H / Full.Height);
    DW := Max(1, Round(Full.Width * F));
    DH := Max(1, Round(Full.Height * F));
    Result.Canvas.AntialiasingMode := amOn;
    Result.Canvas.StretchDraw(
      Rect((W - DW) div 2, (H - DH) div 2, (W - DW) div 2 + DW,
      (H - DH) div 2 + DH), Full);
  finally
    Full.Free;
  end;
end;

function ReaderClassForExt(const Ext: string): TFPCustomImageReaderClass;
begin
  if SameText(Ext, '.jpg') or SameText(Ext, '.jpeg') then
    Result := TFPReaderJPEG
  else if SameText(Ext, '.png') then
    Result := TFPReaderPNG
  else if SameText(Ext, '.bmp') then
    Result := TFPReaderBMP
  else if SameText(Ext, '.gif') then
    Result := TFPReaderGIF
  else
    Result := nil;
end;

function StreamToIntfImage(Stream: TStream;
  ReaderClass: TFPCustomImageReaderClass): TLazIntfImage;
var
  Reader: TFPCustomImageReader;
  Desc: TRawImageDescription;
begin
  Result := nil;
  if (Stream = nil) or (ReaderClass = nil) then Exit;

  Reader := ReaderClass.Create;
  try
    { Idioma canonico LCL: si crea vuota e si assegna la DataDescription,
      lasciando che sia la TLazIntfImage a gestire il proprio buffer. }
    Desc.Init_BPP32_B8G8R8A8_BIO_TTB(0, 0);
    Result := TLazIntfImage.Create(0, 0);
    try
      Result.DataDescription := Desc;
      Stream.Position := 0;
      Result.LoadFromStream(Stream, Reader);
    except
      FreeAndNil(Result);
    end;
  finally
    Reader.Free;
  end;
end;

function FileToIntfImage(const FileName: string;
  ReaderClass: TFPCustomImageReaderClass): TLazIntfImage;
var
  FS: TFileStream;
begin
  Result := nil;
  if not FileExists(FileName) then Exit;
  try
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      Result := StreamToIntfImage(FS, ReaderClass);
    finally
      FS.Free;
    end;
  except
    FreeAndNil(Result);
  end;
end;

function IntfToBitmap(Src: TLazIntfImage): TBitmap;
var
  BmpHandle, MaskHandle: HBitmap;
begin
  Result := nil;
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  Result := TBitmap.Create;
  try
    Src.CreateBitmaps(BmpHandle, MaskHandle, False);
    Result.Handle := BmpHandle;
    Result.MaskHandle := MaskHandle;
  except
    FreeAndNil(Result);
  end;
end;

end.
