unit uWebP;

{
  Decodifica WebP tramite caricamento dinamico di libwebp.
  Cross-platform: Windows / Linux / macOS (usa DynLibs invece di dl).

  La libreria non e' richiesta a compile-time: se manca, le funzioni
  restituiscono nil e WebPAvailable ritorna False.

  Su Windows libwebp.dll (con la sua libsharpyuv.dll) va posata accanto
  all'eseguibile: la cartella dell'exe e' la prima in cui Windows cerca
  sia la libreria sia le sue dipendenze.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, IntfGraphics;

{ True se libwebp e' stata trovata e caricata correttamente. }
function WebPAvailable: boolean;

{ Nome del file di libreria effettivamente caricato (stringa vuota se nessuno). }
function WebPLibraryName: string;

{ Decodifica un buffer WebP in memoria. Restituisce nil in caso di errore.
  Non tocca il widgetset: invocabile anche da thread secondari.
  Il chiamante e' proprietario della TLazIntfImage restituita. }
function WebPToIntfImage(const Data: Pointer; DataSize: SizeInt): TLazIntfImage;

{ Codifica una TLazIntfImage in formato WebP. Restituisce i bytes codificati
  in un TMemoryStream (proprieta' del chiamante). nil se la codifica fallisce.
  Quality: 0..100 (default 75). Richiede libwebp con encode support. }
function IntfImageToWebP(const Img: TLazIntfImage; Quality: integer = 75): TMemoryStream;

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
  TWebPGetInfo = function(Data: pbyte; data_size: PtrUInt;
    Width, Height: PInteger): integer; cdecl;
  TWebPDecodeBGRA = function(Data: pbyte; data_size: PtrUInt;
    Width, Height: PInteger): pbyte; cdecl;
  TWebPFree = procedure(ptr: Pointer); cdecl;
  TWebPEncodeBGRA = function(bgra: pbyte; width, height, stride: integer;
    quality: single; var output: pbyte): PtrUInt; cdecl;

var
  LibLock: TRTLCriticalSection;
  hLib: TLibHandle = NilHandle;
  LibTried: boolean = False;
  LibName: string = '';
  _WebPGetInfo: TWebPGetInfo = nil;
  _WebPDecodeBGRA: TWebPDecodeBGRA = nil;
  _WebPFree: TWebPFree = nil;   { assente prima di libwebp 0.5: opzionale }
  _WebPEncodeBGRA: TWebPEncodeBGRA = nil; { encode puo' essere assente }

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
      Log('InitLib: libwebp NON trovata: i CBZ in formato WebP non ' +
        'avranno anteprima');
      Exit;
    end;

    Pointer(_WebPGetInfo) := GetProcedureAddress(hLib, 'WebPGetInfo');
    Pointer(_WebPDecodeBGRA) := GetProcedureAddress(hLib, 'WebPDecodeBGRA');
    Pointer(_WebPFree) := GetProcedureAddress(hLib, 'WebPFree');
    Pointer(_WebPEncodeBGRA) := GetProcedureAddress(hLib, 'WebPEncodeBGRA');

    if not (Assigned(_WebPGetInfo) and Assigned(_WebPDecodeBGRA)) then
    begin
      Log('InitLib: %s caricata ma priva delle funzioni di decodifica', [LibName]);
      UnloadLibrary(hLib);
      hLib := NilHandle;
      LibName := '';
      _WebPGetInfo := nil;
      _WebPDecodeBGRA := nil;
      _WebPFree := nil;
      Exit;
    end;

    Log('InitLib: caricata %s (WebPFree %s)',
      [LibName, BoolToStr(Assigned(_WebPFree), 'presente', 'assente')]);
  finally
    LeaveCriticalSection(LibLock);
  end;
end;

function WebPAvailable: boolean;
begin
  InitLib;
  Result := hLib <> NilHandle;
end;

function WebPLibraryName: string;
begin
  InitLib;
  Result := LibName;
end;

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

  W := 0;
  H := 0;
  if _WebPGetInfo(pbyte(Data), PtrUInt(DataSize), @W, @H) = 0 then
  begin
    Log('WebP: intestazione non valida');
    Exit;
  end;
  if (W <= 0) or (H <= 0) then Exit;

  { BGRA = stesso ordine dei byte usato dalla LCL: nessuna conversione per pixel }
  Buf := _WebPDecodeBGRA(pbyte(Data), PtrUInt(DataSize), @W, @H);
  if Buf = nil then
  begin
    Log('WebP: decodifica fallita (%dx%d)', [W, H]);
    Exit;
  end;

  try
    RawImg.Init;
    RawImg.Description.Init_BPP32_B8G8R8A8_BIO_TTB(W, H);
    RawImg.CreateData(False);

    SrcStride := PtrUInt(W) * 4;
    for y := 0 to H - 1 do
      Move((Buf + PtrUInt(y) * SrcStride)^,
        (RawImg.Data + PtrUInt(y) * RawImg.Description.BytesPerLine)^,
        SrcStride);

    { True: TLazIntfImage diventa proprietaria di RawImg.Data }
    Result := TLazIntfImage.Create(RawImg, True);
  finally
    if Assigned(_WebPFree) then
      _WebPFree(Buf);
  end;
end;

function IntfImageToWebP(const Img: TLazIntfImage; Quality: integer): TMemoryStream;
var
  W, H, Stride, y: integer;
  Buf: pbyte;
  OutPtr: pbyte;
  OutSize: PtrUInt;
  SrcLine, DstLine: pbyte;
begin
  Result := nil;
  if (Img = nil) or (Img.Width <= 0) or (Img.Height <= 0) then Exit;
  if not Assigned(_WebPEncodeBGRA) then
  begin
    Log('WebP: encode non disponibile');
    Exit;
  end;

  W := Img.Width;
  H := Img.Height;
  Stride := W * 4; // BGRA = 4 bytes per pixel

  { TLazIntfImage is bottom-up (BIO). Copy rows in top-down order. }
  Buf := GetMem(Stride * H);
  try
    for y := 0 to H - 1 do
    begin
      SrcLine := Img.GetDataLineStart(H - 1 - y);
      DstLine := Buf + PtrUInt(y) * PtrUInt(Stride);
      Move(SrcLine^, DstLine^, Stride);
    end;

    OutPtr := nil;
    OutSize := _WebPEncodeBGRA(Buf, W, H, Stride, Quality, OutPtr);
    if (OutSize > 0) and (OutPtr <> nil) then
    begin
      Result := TMemoryStream.Create;
      Result.Write(OutPtr^, OutSize);
      if Assigned(_WebPFree) then
        _WebPFree(OutPtr);
    end
    else
      Log('WebP: codifica fallita (%dx%d, q=%d)', [W, H, Quality]);
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
