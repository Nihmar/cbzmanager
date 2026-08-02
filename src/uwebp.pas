unit uWebP;

{
  uWebP — WebP decoding and encoding via dynamically loaded libwebp.
  ---------------------------------------------------------------------------
  Cross-platform: Windows / Linux / macOS (uses DynLibs instead of dl).

  The library is not required at compile time: if it is missing at runtime,
  the functions return nil and WebPAvailable returns False.
  The application can therefore still work, simply without previews for
  WebP-format CBZs.

  On Windows libwebp.dll (with its libsharpyuv.dll) must be placed next to
  the executable: the exe folder is the first place Windows looks for both
  the library and its dependencies.

  All operations work in memory and never touch the LCL widgetset:
  they can therefore be called from worker threads too.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, IntfGraphics;

const
  { WebP encode quality: valid range and default used across the app. }
  WEBP_QUALITY_MIN     = 30;
  WEBP_QUALITY_MAX     = 100;
  DEFAULT_WEBP_QUALITY = 75;

{ True if libwebp was found and loaded successfully. }
function WebPAvailable: boolean;

{ Name of the library file actually loaded (empty string if none). }
function WebPLibraryName: string;

{
  Decodes a WebP buffer in memory. Returns nil on error.
  Does not touch the widgetset: callable from worker threads too.
  The caller owns the returned TLazIntfImage. }
function WebPToIntfImage(const Data: Pointer; DataSize: SizeInt): TLazIntfImage;

{
  Encodes a TLazIntfImage as WebP. Returns the encoded bytes in a
  TMemoryStream (owned by the caller). nil if encoding fails.
  Quality: 0..100 (default DEFAULT_WEBP_QUALITY). Requires libwebp with
  encode support. }
function IntfImageToWebP(const Img: TLazIntfImage;
  Quality: integer = DEFAULT_WEBP_QUALITY): TMemoryStream;

implementation

uses
  DynLibs, GraphType, uLog;

const
  {$IF DEFINED(WINDOWS)}
  WEBP_LIB_NAMES: array[0..3] of string = (
    'libwebp.dll',
    'webp.dll',
    'libwebp-7.dll',
    'libwebpdecoder.dll'
  );
  {$ELSEIF DEFINED(DARWIN)}
  WEBP_LIB_NAMES: array[0..3] of string = (
    'libwebp.dylib',
    '/opt/homebrew/lib/libwebp.dylib',
    '/usr/local/lib/libwebp.dylib',
    'libwebpdecoder.dylib'
  );
  {$ELSE}
  WEBP_LIB_NAMES: array[0..5] of string = (
    'libwebp.so.7',
    'libwebp.so.6',
    'libwebp.so',
    'libwebpdecoder.so.3',
    'libwebpdecoder.so.2',
    'libwebpdecoder.so'
    );
  {$ENDIF}

type
  { Signature of WebPGetInfo: reads width and height from a WebP buffer.
    Returns 0 if the header is invalid. }
  TWebPGetInfo = function(Data: pbyte; data_size: PtrUInt;
    Width, Height: PInteger): integer; cdecl;
  { Signature of WebPDecodeBGRA: decodes into a BGRA buffer (8 bits per
    channel). The caller must free the returned pointer with WebPFree. }
  TWebPDecodeBGRA = function(Data: pbyte; data_size: PtrUInt;
    Width, Height: PInteger): pbyte; cdecl;
  { Signature of WebPFree: frees a pointer allocated by libwebp.
    Absent before libwebp 0.5 — in that case we use FreeMemory. }
  TWebPFree = procedure(ptr: Pointer); cdecl;
  { Signature of WebPEncodeBGRA: encodes BGRA pixels as WebP.
    Returns the size in bytes of the allocated output buffer.
    Only available in the full libwebp, not in the decoder-only build. }
  TWebPEncodeBGRA = function(bgra: pbyte; Width, Height, stride: integer;
    quality: single; var output: pbyte): PtrUInt; cdecl;

var
  { Serializes the lazy initialization of the library. }
  LibLock: TRTLCriticalSection;
  { Handle of the dynamic library; NilHandle if not loaded. }
  hLib: TLibHandle = NilHandle;
  { True after the first load attempt (avoids repeated retries). }
  LibTried: boolean = False;
  { Name of the library file actually loaded. }
  LibName: string = '';
  { Pointers to the functions exported by libwebp, resolved dynamically. }
  _WebPGetInfo: TWebPGetInfo = nil;
  _WebPDecodeBGRA: TWebPDecodeBGRA = nil;
  _WebPFree: TWebPFree = nil;   { absent before libwebp 0.5: optional }
  _WebPEncodeBGRA: TWebPEncodeBGRA = nil; { encode may be absent }

{
  Lazy, thread-safe initialization: searches libwebp among the known
  names, loads the first one found and resolves the needed symbols.
  If the library exists but lacks the decode functions, it is discarded.
  Logs the outcome (success or failure) via uLog. }
procedure InitLib;
var
  i: integer;
begin
  EnterCriticalSection(LibLock);
  try
    if LibTried then Exit;
    LibTried := True;

    for i := Low(WEBP_LIB_NAMES) to High(WEBP_LIB_NAMES) do
    begin
      hLib := LoadLibrary(WEBP_LIB_NAMES[i]);
      if hLib <> NilHandle then
      begin
        LibName := WEBP_LIB_NAMES[i];
        Break;
      end;
    end;
    if hLib = NilHandle then
    begin
      Log('InitLib: libwebp NOT found: WebP-format CBZs will not ' +
        'have previews');
      Exit;
    end;

    Pointer(_WebPGetInfo) := GetProcedureAddress(hLib, 'WebPGetInfo');
    Pointer(_WebPDecodeBGRA) := GetProcedureAddress(hLib, 'WebPDecodeBGRA');
    Pointer(_WebPFree) := GetProcedureAddress(hLib, 'WebPFree');
    Pointer(_WebPEncodeBGRA) := GetProcedureAddress(hLib, 'WebPEncodeBGRA');

    if not (Assigned(_WebPGetInfo) and Assigned(_WebPDecodeBGRA)) then
    begin
      Log('InitLib: %s loaded but missing the decode functions', [LibName]);
      UnloadLibrary(hLib);
      hLib := NilHandle;
      LibName := '';
      _WebPGetInfo := nil;
      _WebPDecodeBGRA := nil;
      _WebPFree := nil;
      Exit;
    end;

    Log('InitLib: loaded %s (WebPFree %s)',
      [LibName, BoolToStr(Assigned(_WebPFree), 'present', 'absent')]);
  finally
    LeaveCriticalSection(LibLock);
  end;
end;

{
  Returns True if libwebp was found and loaded successfully.
  The first use triggers the search (lazy init). }
function WebPAvailable: boolean;
begin
  InitLib;
  Result := hLib <> NilHandle;
end;

{
  Returns the name of the library file actually loaded,
  or an empty string if no library is available. }
function WebPLibraryName: string;
begin
  InitLib;
  Result := LibName;
end;

{
  Decodes a WebP buffer in memory and returns a 32-bit BGRA TLazIntfImage.
  Does not touch the widgetset: callable from threads.
  Parameters:
    Data     — pointer to the buffer containing the WebP image
    DataSize — size of the buffer in bytes
  Returns nil on error (library missing, invalid header, decode failure).
  The caller owns the result. }
function WebPToIntfImage(const Data: Pointer; DataSize: SizeInt): TLazIntfImage;
var
  W, H, y: integer;
  Buf: pbyte;
  RawImg: TRawImage;
  SrcStride: PtrUInt;
begin
  Result := nil;
  if (Data = nil) or (DataSize <= 0) then Exit;
  if not WebPAvailable then Exit;

  { Queries the WebP header for the real dimensions. }
  W := 0;
  H := 0;
  if _WebPGetInfo(pbyte(Data), PtrUInt(DataSize), @W, @H) = 0 then
  begin
    Log('WebP: invalid header');
    Exit;
  end;
  if (W <= 0) or (H <= 0) then Exit;

  { BGRA = same byte order used by the LCL: no per-pixel conversion }
  Buf := _WebPDecodeBGRA(pbyte(Data), PtrUInt(DataSize), @W, @H);
  if Buf = nil then
  begin
    Log('WebP: decode failed (%dx%d)', [W, H]);
    Exit;
  end;

  try
    { Builds a TRawImage with the same BGRA memory layout.
      Init_BPP32_B8G8R8A8_BIO_TTB = 32 bpp, Blue-Green-Red-Alpha, byte order
      LSB-first, rows top-to-bottom (LineOrder = riloTopToBottom). }
    RawImg.Init;
    RawImg.Description.Init_BPP32_B8G8R8A8_BIO_TTB(W, H);
    RawImg.CreateData(False);

    SrcStride := PtrUInt(W) * 4;
    { Copies the rows from the source to the raw buffer. Both use the same
      BGRA layout and the same row order (top-to-bottom),
      so it is a direct Move(). }
    for y := 0 to H - 1 do
      Move((Buf + PtrUInt(y) * SrcStride)^,
        (RawImg.Data + PtrUInt(y) * RawImg.Description.BytesPerLine)^,
        SrcStride);

    { True: TLazIntfImage becomes the owner of RawImg.Data }
    Result := TLazIntfImage.Create(RawImg, True);
  finally
    if Assigned(_WebPFree) then
      _WebPFree(Buf);
  end;
end;

{
  Encodes a TLazIntfImage as lossy WebP.
  Parameters:
    Img     — source image as TLazIntfImage (any layout)
    Quality — quality 0..100 (default 75); 0 = maximum compression
  Returns a TMemoryStream with the encoded bytes, or nil if encoding fails
  or libwebp encode is unavailable.
  The caller owns the returned TMemoryStream.
  Requires libwebp with encode support (not the decoder-only build). }
function IntfImageToWebP(const Img: TLazIntfImage; Quality: integer): TMemoryStream;
var
  W, H, Stride, y, SrcBytesPerLine: integer;
  Buf: pbyte;
  OutPtr: pbyte;
  OutSize: PtrUInt;
  SrcLine, DstLine: pbyte;
begin
  Result := nil;
  if (Img = nil) or (Img.Width <= 0) or (Img.Height <= 0) then Exit;

  { Ensure libwebp is loaded (InitLib is lazy and may not have been
    triggered if no WebP image was decoded before this point). }
  if not WebPAvailable then
  begin
    Log('WebP: libwebp unavailable');
    Exit;
  end;
  if not Assigned(_WebPEncodeBGRA) then
  begin
    Log('WebP: encode unavailable');
    Exit;
  end;

  W := Img.Width;
  H := Img.Height;
  SrcBytesPerLine := Img.DataDescription.BytesPerLine;

  { Require 32-bit BGRA/RGBA input — anything else is unsupported by the
    BGRA encode path below. }
  if (Img.DataDescription.BitsPerPixel <> 32) or
     (SrcBytesPerLine < W * 4) then
  begin
    Log('WebP: unsupported pixel format (BPP=%d, BytesPerLine=%d)',
      [Img.DataDescription.BitsPerPixel, SrcBytesPerLine]);
    Exit;
  end;

  Stride := W * 4; // BGRA = 4 bytes per pixel

  { The app's TLazIntfImages are top-to-bottom (Init_..._TTB sets
    LineOrder = riloTopToBottom): row 0 is already the top row, as
    WebPEncodeBGRA requires. We therefore copy in natural order —
    inverting the rows would produce an upside-down WebP. }
  Buf := GetMem(PtrUInt(Stride) * PtrUInt(H));
  if Buf = nil then Exit;
  try
    for y := 0 to H - 1 do
    begin
      SrcLine := Img.GetDataLineStart(y);
      DstLine := Buf + PtrUInt(y) * PtrUInt(Stride);
      Move(SrcLine^, DstLine^, Stride);
    end;

    OutPtr := nil;
    OutSize := _WebPEncodeBGRA(Buf, W, H, Stride, Quality, OutPtr);
    if (OutSize > 0) and (OutPtr <> nil) then
    begin
      Result := TMemoryStream.Create;
      Result.Write(OutPtr^, OutSize);
      { Frees the buffer allocated by libwebp. }
      if Assigned(_WebPFree) then
        _WebPFree(OutPtr);
    end
    else
      Log('WebP: encode failed (%dx%d, q=%d)', [W, H, Quality]);
  finally
    FreeMem(Buf);
  end;
end;

initialization
  InitCriticalSection(LibLock);

finalization
  if hLib <> NilHandle then
  begin
    UnloadLibrary(hLib);
    hLib := NilHandle;
  end;
  DoneCriticalSection(LibLock);

end.
