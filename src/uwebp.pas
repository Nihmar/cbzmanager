unit uWebP;

{
  uWebP — Decodifica e codifica WebP via libwebp caricata dinamicamente.
  ---------------------------------------------------------------------------
  Cross-platform: Windows / Linux / macOS (usa DynLibs invece di dl).

  La libreria non è richiesta a compile-time: se manca a runtime, le
  funzioni restituiscono nil e WebPAvailable ritorna False.
  L'applicazione può quindi funzionare comunque, semplicemente senza
  anteprima per i CBZ in formato WebP.

  Su Windows libwebp.dll (con la sua libsharpyuv.dll) va posata accanto
  all'eseguibile: la cartella dell'exe è la prima in cui Windows cerca
  sia la libreria sia le sue dipendenze.

  Tutte le operazioni lavorano in memoria e non toccano il widgetset LCL:
  sono quindi invocabili anche da thread secondari.
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
  Quality: 0..100 (default DEFAULT_WEBP_QUALITY). Richiede libwebp con encode support. }
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
  { Firma di WebPGetInfo: legge larghezza e altezza da un buffer WebP.
    Restituisce 0 se l'intestazione non è valida. }
  TWebPGetInfo = function(Data: pbyte; data_size: PtrUInt;
    Width, Height: PInteger): integer; cdecl;
  { Firma di WebPDecodeBGRA: decodifica in buffer BGRA (8 bit per canale).
    Il chiamante deve liberare il puntatore restituito con WebPFree. }
  TWebPDecodeBGRA = function(Data: pbyte; data_size: PtrUInt;
    Width, Height: PInteger): pbyte; cdecl;
  { Firma di WebPFree: libera un puntatore allocato da libwebp.
    Assente prima di libwebp 0.5 — in tal caso usiamo FreeMemory. }
  TWebPFree = procedure(ptr: Pointer); cdecl;
  { Firma di WebPEncodeBGRA: codifica pixel BGRA in formato WebP.
    Restituisce la dimensione in byte del buffer allocato in output.
    Disponibile solo nella libwebp completa, non nel decoder-only. }
  TWebPEncodeBGRA = function(bgra: pbyte; Width, Height, stride: integer;
    quality: single; var output: pbyte): PtrUInt; cdecl;

var
  { Serializza l'inizializzazione lazy della libreria. }
  LibLock: TRTLCriticalSection;
  { Handle della libreria dinamica; NilHandle se non caricata. }
  hLib: TLibHandle = NilHandle;
  { True dopo il primo tentativo di caricamento (evita retry ripetuti). }
  LibTried: boolean = False;
  { Nome del file di libreria effettivamente caricato. }
  LibName: string = '';
  { Puntatori alle funzioni esportate da libwebp, risolti dinamicamente. }
  _WebPGetInfo: TWebPGetInfo = nil;
  _WebPDecodeBGRA: TWebPDecodeBGRA = nil;
  _WebPFree: TWebPFree = nil;   { assente prima di libwebp 0.5: opzionale }
  _WebPEncodeBGRA: TWebPEncodeBGRA = nil; { encode può essere assente }

{ Inizializzazione lazy e thread-safe: cerca libwebp tra i nomi noti,
  carica la prima trovata e risolve i simboli necessari.
  Se la libreria esiste ma mancano le funzioni di decodifica, la scarta.
  Logga il risultato (successo o fallimento) via uLog. }
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

{ Restituisce True se libwebp è stata trovata e caricata con successo.
  Il primo utilizzo innesca la ricerca (lazy init). }
function WebPAvailable: boolean;
begin
  InitLib;
  Result := hLib <> NilHandle;
end;

{ Restituisce il nome del file di libreria effettivamente caricato,
  oppure stringa vuota se nessuna libreria è disponibile. }
function WebPLibraryName: string;
begin
  InitLib;
  Result := LibName;
end;

{ Decodifica un buffer WebP in memoria e restituisce una TLazIntfImage
  in formato BGRA a 32 bit. Non tocca il widgetset: invocabile da thread.
  Parametri:
    Data     — puntatore al buffer contenente l'immagine WebP
    DataSize — dimensione del buffer in byte
  Restituisce nil in caso di errore (libreria assente, intestazione non
  valida, decodifica fallita). Il chiamante è proprietario del risultato. }
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

  { Interroga l'intestazione WebP per ottenere le dimensioni reali. }
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
    { Costruisce un TRawImage con lo stesso layout di memoria BGRA.
      Init_BPP32_B8G8R8A8_BIO_TTB = 32 bpp, Blue-Green-Red-Alpha,
      Bottom-Up (BIO = righe invertite), Top-To-Bottom. }
    RawImg.Init;
    RawImg.Description.Init_BPP32_B8G8R8A8_BIO_TTB(W, H);
    RawImg.CreateData(False);

    SrcStride := PtrUInt(W) * 4;
    { Copia le righe dalla sorgente al buffer raw. Entrambi usano lo
      stesso layout BGRA e orientamento bottom-up, quindi è un Move(). }
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

{ Codifica una TLazIntfImage in formato WebP lossy.
  Parametri:
    Img     — immagine sorgente in formato TLazIntfImage (qualsiasi layout)
    Quality — qualità 0..100 (default 75); 0 = massima compressione
  Restituisce un TMemoryStream contenente i bytes codificati, oppure nil
  se la codifica fallisce o libwebp encode non è disponibile.
  Il chiamante è proprietario del TMemoryStream restituito.
  Richiede libwebp con supporto encode (non il decoder-only). }
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
    Log('WebP: libwebp non disponibile');
    Exit;
  end;
  if not Assigned(_WebPEncodeBGRA) then
  begin
    Log('WebP: encode non disponibile');
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
    Log('WebP: formato pixel non supportato (BPP=%d, BytesPerLine=%d)',
      [Img.DataDescription.BitsPerPixel, SrcBytesPerLine]);
    Exit;
  end;

  Stride := W * 4; // BGRA = 4 bytes per pixel

  { TLazIntfImage è bottom-up (BIO). Per la codifica dobbiamo passare
    le righe in ordine top-down: invertiamo l'ordine durante la copia. }
  Buf := GetMem(PtrUInt(Stride) * PtrUInt(H));
  if Buf = nil then Exit;
  try
    for y := 0 to H - 1 do
    begin
      SrcLine := Img.GetDataLineStart(H - 1 - y);  { riga dal basso }
      DstLine := Buf + PtrUInt(y) * PtrUInt(Stride); { riga in alto }
      Move(SrcLine^, DstLine^, Stride);
    end;

    OutPtr := nil;
    OutSize := _WebPEncodeBGRA(Buf, W, H, Stride, Quality, OutPtr);
    if (OutSize > 0) and (OutPtr <> nil) then
    begin
      Result := TMemoryStream.Create;
      Result.Write(OutPtr^, OutSize);
      { Libera il buffer allocato da libwebp. }
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
