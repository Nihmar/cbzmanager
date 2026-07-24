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

{ Riduce l'immagine perche' entri in MaxW x MaxH mantenendo le proporzioni.
  Non ingrandisce mai. Sola memoria (nessuna GDI): invocabile da thread
  secondari. nil se Src e' nil o vuota; il chiamante e' proprietario del
  risultato. }
function ScaleIntfImage(Src: TLazIntfImage; MaxW, MaxH: integer): TLazIntfImage;

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

function ScaleIntfImage(Src: TLazIntfImage; MaxW, MaxH: integer): TLazIntfImage;
const
  { Campioni per lato: tiene il costo entro 16 letture per pixel di
    destinazione, indipendentemente da quanto e' grande l'originale. }
  MaxSamples = 4;
var
  Desc: TRawImageDescription;
  F: double;
  DW, DH, x, y, ix, iy: integer;
  sx0, sx1, sy0, sy1, StepX, StepY, N: integer;
  R, G, B, A: cardinal;
  C: TFPColor;
begin
  Result := nil;
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  if (MaxW <= 0) or (MaxH <= 0) then Exit;

  F := Min(Min(MaxW / Src.Width, MaxH / Src.Height), 1.0);
  DW := Max(1, Round(Src.Width * F));
  DH := Max(1, Round(Src.Height * F));

  Desc.Init_BPP32_B8G8R8A8_BIO_TTB(DW, DH);
  Result := TLazIntfImage.Create(0, 0);
  try
    Result.DataDescription := Desc;
    for y := 0 to DH - 1 do
    begin
      { Riquadro dei pixel originali che confluiscono nella riga y }
      sy0 := (y * Src.Height) div DH;
      sy1 := ((y + 1) * Src.Height) div DH;
      if sy1 <= sy0 then sy1 := sy0 + 1;
      StepY := Max(1, (sy1 - sy0 + MaxSamples - 1) div MaxSamples);

      for x := 0 to DW - 1 do
      begin
        sx0 := (x * Src.Width) div DW;
        sx1 := ((x + 1) * Src.Width) div DW;
        if sx1 <= sx0 then sx1 := sx0 + 1;
        StepX := Max(1, (sx1 - sx0 + MaxSamples - 1) div MaxSamples);

        R := 0;
        G := 0;
        B := 0;
        A := 0;
        N := 0;
        iy := sy0;
        while iy < sy1 do
        begin
          ix := sx0;
          while ix < sx1 do
          begin
            C := Src.Colors[ix, iy];
            Inc(R, C.Red);
            Inc(G, C.Green);
            Inc(B, C.Blue);
            Inc(A, C.Alpha);
            Inc(N);
            Inc(ix, StepX);
          end;
          Inc(iy, StepY);
        end;
        if N = 0 then Continue;

        C.Red := R div N;
        C.Green := G div N;
        C.Blue := B div N;
        C.Alpha := A div N;
        Result.Colors[x, y] := C;
      end;
    end;
  except
    FreeAndNil(Result);
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
