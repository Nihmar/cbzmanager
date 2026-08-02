unit uImgUtil;

{
  uImgUtil — Image decoding, resizing and conversion.
  ---------------------------------------------------------------------------
  Provides load/manipulation primitives that work entirely in memory
  (TLazIntfImage), without any GDI/widgetset call. They can therefore be
  used from worker threads too, unlike TBitmap which requires the main
  thread.

  The only exception is IntfToBitmap (and by extension MakeThumb), which
  touches the LCL widgetset and must only be invoked from the main thread.

  Formats supported for reading: JPEG, PNG, BMP, GIF (via the FPRead*
  units). WebP is handled separately by the uWebP unit.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Controls,
  Graphics,
  FPImage,
  IntfGraphics,
  Math;

const
  { Thumbnail height-to-width ratio: comic pages are taller than wide, so a
    thumbnail of width W is given height ThumbHeight(W). }
  PAGE_ASPECT_RATIO = 1.25;

  { Image file extensions (leading dot included).  Single source of truth
    for extension literals used across the app. }
  EXT_JPG = '.jpg';
  EXT_JPEG = '.jpeg';
  EXT_PNG = '.png';
  EXT_BMP = '.bmp';
  EXT_GIF = '.gif';
  EXT_TIFF = '.tiff';
  EXT_TIF = '.tif';
  EXT_WEBP = '.webp';

  { Every raster format the app recognizes as a page image. }
  IMAGE_EXTS: array[0..7] of string =
    (EXT_PNG, EXT_JPG, EXT_JPEG, EXT_BMP, EXT_GIF, EXT_WEBP, EXT_TIFF, EXT_TIF);

  { Formats that can be re-encoded to WebP (i.e. every image format except
    WebP itself). }
  CONVERTIBLE_EXTS: array[0..6] of string =
    (EXT_JPG, EXT_JPEG, EXT_PNG, EXT_GIF, EXT_BMP, EXT_TIFF, EXT_TIF);

{ True if Ext (leading dot included) case-insensitively matches any entry
  of AList. }
function ExtInList(const Ext: string; const AList: array of string): boolean;

{ Returns the reader class matching the extension, nil if unhandled.
  WebP is not included: uWebP takes care of it. }
function ReaderClassForExt(const Ext: string): TFPCustomImageReaderClass;

{ Decodes the stream (from the start) in the given format. nil on failure. }
function StreamToIntfImage(Stream: TStream;
  ReaderClass: TFPCustomImageReaderClass): TLazIntfImage;

{
  As above, but asks the reader to decode at reduced resolution when the
  format supports it (e.g. JPEG DCT scaling via MinWidth/MinHeight): the
  result is at least about MaxW x MaxH. 0 = full resolution (the default
  behaviour). Formats without dedicated downscaling yield full resolution. }
function StreamToIntfImage(Stream: TStream;
  ReaderClass: TFPCustomImageReaderClass; MaxW, MaxH: integer): TLazIntfImage;

{ As above, reading from a file. }
function FileToIntfImage(const FileName: string;
  ReaderClass: TFPCustomImageReaderClass): TLazIntfImage;

{
  Shrinks the image to fit MaxW x MaxH while keeping the aspect ratio.
  Never enlarges. Memory only (no GDI): callable from worker threads.
  nil if Src is nil or empty; the caller owns the result. }
function ScaleIntfImage(Src: TLazIntfImage; MaxW, MaxH: integer): TLazIntfImage;

{ MAIN THREAD ONLY: creates a TBitmap from a TLazIntfImage. }
function IntfToBitmap(Src: TLazIntfImage): TBitmap;

{ MAIN THREAD ONLY: IntfToBitmap and Canvas touch the widgetset. }
function MakeThumb(Src: TLazIntfImage; W, H: integer): TBitmap;

{ Thumbnail height for a given width, per PAGE_ASPECT_RATIO. }
function ThumbHeight(AWidth: integer): integer;

{
  MAIN THREAD ONLY: builds a thumbnail of AImg sized to
  AIL.Width × AIL.Height, adds it to the image list, frees the
  intermediate bitmap and returns the index of the new image. }
function AppendThumb(AIL: TImageList; AImg: TLazIntfImage): integer;

function IsImageExt(const Ext: string): boolean;

{ Peeks at the first bytes of Stream to determine the actual image format
  regardless of file extension.  Returns the canonical extension (e.g.
  '.jpg', '.png') or '' if the format cannot be determined.
  The stream must be seekable; its position is restored on exit. }
function DetectImageFormat(Stream: TStream): string;

implementation

uses
  FPReadJPEG, FPReadPNG, FPReadBMP, FPReadGIF, FPReadTiff, GraphType, LCLType;

function ExtInList(const Ext: string; const AList: array of string): boolean;
var
  i: integer;
begin
  Result := False;
  for i := 0 to High(AList) do
    if SameText(Ext, AList[i]) then
      Exit(True);
end;

{ Restituisce True se l'estensione (incluso il punto) appartiene a un
  formato immagine riconosciuto dal programma (incluso WebP e TIFF). }
function IsImageExt(const Ext: string): boolean;
begin
  Result := ExtInList(Ext, IMAGE_EXTS);
end;

const
  { Number of bytes to read for magic-number detection. 12 is enough to
    cover RIFF…WEBP (the longest magic we check). }
  MAGIC_LEN = 12;

{ Peeks at the first bytes of Stream to determine the actual image format
  regardless of file extension.  Returns the canonical extension (e.g.
  '.jpg', '.png') or '' if the format cannot be detected.
  The stream must be seekable; its position is restored on exit. }
function DetectImageFormat(Stream: TStream): string;
var
  Magic: array[0..MAGIC_LEN - 1] of byte;
  OldPos, BytesRead: int64;
begin
  Result := '';
  if Stream = nil then Exit;
  OldPos := Stream.Position;
  try
    Stream.Position := 0;
    BytesRead := Stream.Read(Magic[0], MAGIC_LEN);
    if BytesRead < 4 then Exit;
    { JPEG: FF D8 FF }
    if (Magic[0] = $FF) and (Magic[1] = $D8) and (Magic[2] = $FF) then
      Result := EXT_JPG
    { PNG: 89 50 4E 47 }
    else if (Magic[0] = $89) and (Magic[1] = $50) and (Magic[2] = $4E) and
      (Magic[3] = $47) then
      Result := EXT_PNG
    { GIF: 47 49 46 38 }
    else if (Magic[0] = $47) and (Magic[1] = $49) and (Magic[2] = $46) and
      (Magic[3] = $38) then
      Result := EXT_GIF
    { BMP: 42 4D }
    else if (Magic[0] = $42) and (Magic[1] = $4D) then
      Result := EXT_BMP
    { WebP: RIFF....WEBP }
    else if (BytesRead >= 12) and (Magic[0] = $52) and
      (Magic[1] = $49) and (Magic[2] = $46) and (Magic[3] = $46) and
      (Magic[8] = $57) and (Magic[9] = $45) and (Magic[10] = $42) and
      (Magic[11] = $50) then
      Result := EXT_WEBP
    { TIFF: 49 49 2A 00 (little-endian) or 4D 4D 00 2A (big-endian) }
    else if ((Magic[0] = $49) and (Magic[1] = $49) and (Magic[2] = $2A) and
      (Magic[3] = $00)) or ((Magic[0] = $4D) and (Magic[1] = $4D) and
      (Magic[2] = $00) and (Magic[3] = $2A)) then
      Result := EXT_TIFF;
  finally
    Stream.Position := OldPos;
  end;
end;

{
  Creates a W×H thumbnail from a TLazIntfImage. The image is scaled
  proportionally to fill the rectangle and centered on a window-coloured
  background. Uses anti-aliasing via Canvas.
  MAIN THREAD ONLY: IntfToBitmap and Canvas touch the widgetset. }
function MakeThumb(Src: TLazIntfImage; W, H: integer): TBitmap;
var
  F: double;
  DW, DH: integer;
  Full: TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(W, H);
  { Uniform background for the areas not covered by the scaled image. }
  Result.Canvas.Brush.Color := clWindow;
  Result.Canvas.FillRect(0, 0, W, H);
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;

  { Converte in TBitmap una tantum per usare StretchDraw. }
  Full := IntfToBitmap(Src);
  if Full = nil then Exit;
  try
    { Scale factor: the smaller of the two ratios, so the image fits
      entirely inside the W×H rectangle without distortion. }
    F := Min(W / Full.Width, H / Full.Height);
    DW := Max(1, Round(Full.Width * F));
    DH := Max(1, Round(Full.Height * F));
    Result.Canvas.AntialiasingMode := amOn;
    { Centers the scaled image in the destination rectangle. }
    Result.Canvas.StretchDraw(
      Rect((W - DW) div 2, (H - DH) div 2, (W - DW) div 2 + DW,
      (H - DH) div 2 + DH), Full);
  finally
    Full.Free;
  end;
end;

function ThumbHeight(AWidth: integer): integer;
begin
  Result := Round(AWidth * PAGE_ASPECT_RATIO);
end;

function AppendThumb(AIL: TImageList; AImg: TLazIntfImage): integer;
var
  Thumb: TBitmap;
begin
  Thumb := MakeThumb(AImg, AIL.Width, AIL.Height);
  try
    Result := AIL.Add(Thumb, nil);
  finally
    Thumb.Free;
  end;
end;

{
  Shrinks Src to fit the MaxW×MaxH rectangle while keeping the aspect
  ratio. Never enlarges (the scale factor is capped at 1.0).
  Parameters:
    Src  — source image (TLazIntfImage, any pixel format)
    MaxW — maximum allowed width
    MaxH — maximum allowed height
  Returns a new 32-bit BGRA TLazIntfImage, or nil if Src is nil/empty or
  the maximum dimensions are ≤ 0.
  Works entirely in memory: callable from worker threads.
  The caller owns the result. }
function ScaleIntfImage(Src: TLazIntfImage; MaxW, MaxH: integer): TLazIntfImage;
const
  { Samples per side: keeps the cost within 16 reads per destination
    pixel, regardless of how large the original is. }
  MaxSamples = 4;

  { True if Img is 32-bit BGRA with 8 bits per channel, little-endian
    (B at byte 0, G at byte 1, R at byte 2, A at byte 3): the layout
    produced by all readers used by the app and by WebPToIntfImage. On
    such data the scaler can work on raw bytes. }
  function IsBGRA32(const Img: TLazIntfImage): boolean;
  var
    D: TRawImageDescription;
  begin
    D := Img.DataDescription;
    Result := (D.BitsPerPixel = 32) and (D.RedPrec = 8) and (D.GreenPrec = 8) and
      (D.BluePrec = 8) and (D.AlphaPrec = 8) and
      (D.RedShift = 16) and (D.GreenShift = 8) and (D.BlueShift = 0) and
      (D.AlphaShift = 24);
  end;

  { Box filter on raw bytes: same algorithm as the generic path, but it
    reads/writes scanlines directly via GetDataLineStart instead of going
    through the Colors property (virtual, high per-pixel cost). }
  procedure ScaleBGRA32(Src, Dst: TLazIntfImage; DW, DH: integer);
  var
    x, y, ix, iy: integer;
    sx0, sx1, sy0, sy1, StepX, StepY, N: integer;
    SrcLine, DstLine, P: pbyte;
    R, G, B, A: cardinal;
  begin
    for y := 0 to DH - 1 do
    begin
      sy0 := (y * Src.Height) div DH;
      sy1 := ((y + 1) * Src.Height) div DH;
      if sy1 <= sy0 then sy1 := sy0 + 1;
      StepY := Max(1, (sy1 - sy0 + MaxSamples - 1) div MaxSamples);
      DstLine := Dst.GetDataLineStart(y);
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
          SrcLine := Src.GetDataLineStart(iy);
          ix := sx0;
          while ix < sx1 do
          begin
            { The indices stay within the bounds by construction: sx1 <= W
              and sy1 <= H (see the comment in the generic path). }
            P := SrcLine + PtrUInt(ix) * 4;
            Inc(B, P[0]);
            Inc(G, P[1]);
            Inc(R, P[2]);
            Inc(A, P[3]);
            Inc(N);
            Inc(ix, StepX);
          end;
          Inc(iy, StepY);
        end;
        if N = 0 then Continue;
        P := DstLine + PtrUInt(x) * 4;
        P[0] := B div N;
        P[1] := G div N;
        P[2] := R div N;
        P[3] := A div N;
      end;
    end;
  end;

  { Generic path: the Colors property, suitable for any pixel format
    (grayscale JPEG, palettized PNG, etc.). }
  procedure ScaleGeneric(Src, Dst: TLazIntfImage; DW, DH: integer);
  var
    x, y, ix, iy: integer;
    sx0, sx1, sy0, sy1, StepX, StepY, N: integer;
    R, G, B, A: cardinal;
    C: TFPColor;
  begin
    for y := 0 to DH - 1 do
    begin
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
            { Belt-and-braces: never sample outside the source bounds, even
              if a source image description ever reports dimensions
              inconsistent with its data (would otherwise surface as a
              range-check error in debug builds with range checks on). }
            C := Src.Colors[Min(ix, Src.Width - 1), Min(iy, Src.Height - 1)];
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
        Dst.Colors[Min(x, DW - 1), Min(y, DH - 1)] := C;
      end;
    end;
  end;

var
  Desc: TRawImageDescription;
  F: double;
  DW, DH: integer;
begin
  Result := nil;
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  if (MaxW <= 0) or (MaxH <= 0) then Exit;

  { Scale factor: the smaller of the two ratios, but never > 1. }
  F := Min(Min(MaxW / Src.Width, MaxH / Src.Height), 1.0);
  DW := Max(1, Round(Src.Width * F));
  DH := Max(1, Round(Src.Height * F));

  { The scaled image is always 32-bit BGRA, top-to-bottom. }
  Desc.Init_BPP32_B8G8R8A8_BIO_TTB(DW, DH);
  Result := TLazIntfImage.Create(0, 0);
  try
    Result.DataDescription := Desc;
    if IsBGRA32(Src) then
      ScaleBGRA32(Src, Result, DW, DH)
    else
      ScaleGeneric(Src, Result, DW, DH);
  except
    FreeAndNil(Result);
  end;
end;

{
  Returns the appropriate FCL reader class for the given extension
  (e.g. '.png' → TFPReaderPNG). Case-insensitive.
  Returns nil for unhandled extensions (including WebP, handled
  separately by uWebP). }
function ReaderClassForExt(const Ext: string): TFPCustomImageReaderClass;
begin
  if SameText(Ext, EXT_JPG) or SameText(Ext, EXT_JPEG) then
    Result := TFPReaderJPEG
  else if SameText(Ext, EXT_PNG) then
    Result := TFPReaderPNG
  else if SameText(Ext, EXT_BMP) then
    Result := TFPReaderBMP
  else if SameText(Ext, EXT_GIF) then
    Result := TFPReaderGIF
  else if SameText(Ext, EXT_TIFF) or SameText(Ext, EXT_TIF) then
    Result := TFPReaderTiff
  else
    Result := nil;
end;

{
  Decodes a stream (read from the start) in the format indicated by
  ReaderClass. The resulting image is always 32-bit BGRA.
  Parameters:
    Stream      — stream positioned at the start of the image data
    ReaderClass — FCL reader class (e.g. TFPReaderJPEG)
  Returns a TLazIntfImage, or nil if the stream is unreadable.
  The caller owns the result.
  Memory only: callable from worker threads. }
function StreamToIntfImage(Stream: TStream;
  ReaderClass: TFPCustomImageReaderClass): TLazIntfImage;
begin
  Result := StreamToIntfImage(Stream, ReaderClass, 0, 0);
end;

{
  Like StreamToIntfImage, but with dedicated downscaling when available.
  TFPReaderJPEG exposes MinWidth/MinHeight: setting them before Load makes
  the JPEG decoder apply DCT scaling (half/quarter/eighth) and produce a
  reduced image directly — much faster than a full-resolution decode
  followed by ScaleIntfImage. }
function StreamToIntfImage(Stream: TStream;
  ReaderClass: TFPCustomImageReaderClass; MaxW, MaxH: integer): TLazIntfImage;
var
  Reader: TFPCustomImageReader;
  Desc: TRawImageDescription;
begin
  Result := nil;
  if (Stream = nil) or (ReaderClass = nil) then Exit;

  Reader := ReaderClass.Create;
  try
    if (MaxW > 0) and (MaxH > 0) and (Reader is TFPReaderJPEG) then
    begin
      TFPReaderJPEG(Reader).MinWidth := MaxW;
      TFPReaderJPEG(Reader).MinHeight := MaxH;
    end;
    { Canonical LCL idiom: an empty TLazIntfImage is created and given a
      DataDescription; LoadFromStream allocates and fills the raw buffer.
      Init_BPP32_B8G8R8A8_BIO_TTB forces 32-bit BGRA output. }
    Desc.Init_BPP32_B8G8R8A8_BIO_TTB(0, 0);
    Result := TLazIntfImage.Create(0, 0);
    try
      Result.DataDescription := Desc;
      Stream.Position := 0;
      Result.LoadFromStream(Stream, Reader);
    except
      FreeAndNil(Result);  { corrupt stream or mismatched format }
    end;
  finally
    Reader.Free;
  end;
end;

{
  Opens FileName and decodes its content with ReaderClass.
  A convenient wrapper around StreamToIntfImage.
  Returns nil if the file does not exist, is unreadable, or the format
  does not match the given ReaderClass. }
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
    FreeAndNil(Result);  { I/O error or corrupt file }
  end;
end;

{
  Converts a TLazIntfImage into a native LCL TBitmap.
  This is the only function of the module that touches the widgetset:
  it MUST be called from the main thread.
  Returns nil if Src is nil or empty, or if CreateBitmaps fails. }
function IntfToBitmap(Src: TLazIntfImage): TBitmap;
var
  BmpHandle, MaskHandle: HBitmap;
begin
  Result := nil;
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  Result := TBitmap.Create;
  try
    { CreateBitmaps asks the widgetset to allocate native OS handles for
      the bitmap and the mask from the raw data. }
    Src.CreateBitmaps(BmpHandle, MaskHandle, False);
    Result.Handle := BmpHandle;
    Result.MaskHandle := MaskHandle;
  except
    FreeAndNil(Result);
  end;
end;

end.
