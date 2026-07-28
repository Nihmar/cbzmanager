unit uImgUtil;

{
  uImgUtil — Decodifica, ridimensionamento e conversione di immagini.
  ---------------------------------------------------------------------------
  Fornisce primitive di caricamento e manipolazione che lavorano
  interamente in memoria (TLazIntfImage), senza alcuna chiamata GDI/
  widgetset. Sono quindi utilizzabili anche da thread secondari,
  a differenza di TBitmap che richiede il thread principale.

  L'unica eccezione è IntfToBitmap (e di conseguenza MakeThumb), che
  tocca il widgetset LCL e va invocata esclusivamente dal main thread.

  Formati supportati in lettura: JPEG, PNG, BMP, GIF (via unità FPRead*).
  Il WebP è gestito separatamente dall'unità uWebP.
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
  EXT_JPG  = '.jpg';
  EXT_JPEG = '.jpeg';
  EXT_PNG  = '.png';
  EXT_BMP  = '.bmp';
  EXT_GIF  = '.gif';
  EXT_TIFF = '.tiff';
  EXT_TIF  = '.tif';
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

{ Altezza thumbnail per una data larghezza, secondo PAGE_ASPECT_RATIO. }
function ThumbHeight(AWidth: integer): integer;

{ SOLO MAIN THREAD: costruisce una thumbnail di AImg dimensionata a
  AIL.Width × AIL.Height, la aggiunge alla image list, libera il bitmap
  intermedio e restituisce l'indice della nuova immagine. }
function AppendThumb(AIL: TImageList; AImg: TLazIntfImage): integer;

function IsImageExt(const Ext: string): boolean;

implementation

uses
  FPReadJPEG, FPReadPNG, FPReadBMP, FPReadGIF, GraphType, LCLType;

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

{ Crea una thumbnail di dimensione W×H a partire da una TLazIntfImage.
  L'immagine viene ridotta proporzionalmente per riempire il rettangolo
  e centrata su sfondo color finestra. Usa anti-aliasing via Canvas.
  SOLO MAIN THREAD: IntfToBitmap e Canvas toccano il widgetset. }
function MakeThumb(Src: TLazIntfImage; W, H: integer): TBitmap;
var
  F: double;
  DW, DH: integer;
  Full: TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(W, H);
  { Sfondo uniforme per le aree non coperte dall'immagine scalata. }
  Result.Canvas.Brush.Color := clWindow;
  Result.Canvas.FillRect(0, 0, W, H);
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;

  { Converte in TBitmap una tantum per usare StretchDraw. }
  Full := IntfToBitmap(Src);
  if Full = nil then Exit;
  try
    { Fattore di scala: il minore dei due rapporti, così l'immagine
      sta tutta dentro il rettangolo W×H senza deformarsi. }
    F := Min(W / Full.Width, H / Full.Height);
    DW := Max(1, Round(Full.Width * F));
    DH := Max(1, Round(Full.Height * F));
    Result.Canvas.AntialiasingMode := amOn;
    { Centra l'immagine scalata nel rettangolo di destinazione. }
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

{ Riduce Src in modo che entri nel rettangolo MaxW×MaxH mantenendo le
  proporzioni. Non ingrandisce mai (il fattore di scala è capped a 1.0).
  Parametri:
    Src  — immagine sorgente (TLazIntfImage, qualsiasi formato di pixel)
    MaxW — larghezza massima consentita
    MaxH — altezza massima consentita
  Restituisce una nuova TLazIntfImage in formato BGRA 32-bit, oppure nil
  se Src è nil/vuota o le dimensioni massime sono ≤ 0.
  Lavora interamente in memoria: invocabile da thread secondari.
  Il chiamante è proprietario del risultato. }
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

  { Fattore di scala: il più piccolo tra i due rapporti, ma mai > 1. }
  F := Min(Min(MaxW / Src.Width, MaxH / Src.Height), 1.0);
  DW := Max(1, Round(Src.Width * F));
  DH := Max(1, Round(Src.Height * F));

  { L'immagine scalata è sempre BGRA 32-bit, bottom-up. }
  Desc.Init_BPP32_B8G8R8A8_BIO_TTB(DW, DH);
  Result := TLazIntfImage.Create(0, 0);
  try
    Result.DataDescription := Desc;

    { Per ogni pixel di destinazione, calcoliamo il rettangolo di pixel
      sorgente che vi contribuiscono e ne facciamo la media.
      Per evitare costi proibitivi su riduzioni estreme (es. 4000→100),
      campioniamo al massimo MaxSamples pixel per asse. }
    for y := 0 to DH - 1 do
    begin
      { Intervallo [sy0, sy1) delle righe sorgente che mappano sulla riga y. }
      sy0 := (y * Src.Height) div DH;
      sy1 := ((y + 1) * Src.Height) div DH;
      if sy1 <= sy0 then sy1 := sy0 + 1;  { almeno 1 riga }
      StepY := Max(1, (sy1 - sy0 + MaxSamples - 1) div MaxSamples);

      for x := 0 to DW - 1 do
      begin
        { Intervallo [sx0, sx1) delle colonne sorgente che mappano sul pixel x. }
        sx0 := (x * Src.Width) div DW;
        sx1 := ((x + 1) * Src.Width) div DW;
        if sx1 <= sx0 then sx1 := sx0 + 1;  { almeno 1 colonna }
        StepX := Max(1, (sx1 - sx0 + MaxSamples - 1) div MaxSamples);

        { Somma i canali dei pixel campionati. }
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
            Inc(ix, StepX);  { salta pixel intermedi per restare nel budget }
          end;
          Inc(iy, StepY);
        end;
        if N = 0 then Continue;

        { Media aritmetica dei campioni raccolti. }
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

{ Restituisce la classe reader FCL appropriata per l'estensione data
  (es. '.png' → TFPReaderPNG). Case-insensitive.
  Restituisce nil per estensioni non gestite (incluso WebP, gestito
  separatamente da uWebP). }
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
  else
    Result := nil;
end;

{ Decodifica uno stream (letto dall'inizio) nel formato indicato da
  ReaderClass. L'immagine risultante è sempre BGRA 32-bit.
  Parametri:
    Stream      — stream posizionato all'inizio dei dati immagine
    ReaderClass — classe reader FCL (es. TFPReaderJPEG)
  Restituisce una TLazIntfImage, oppure nil se lo stream è illeggibile.
  Il chiamante è proprietario del risultato.
  Solo memoria: invocabile da thread secondari. }
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
    { Idioma canonico LCL: si crea una TLazIntfImage vuota e le si assegna
      la DataDescription; LoadFromStream alloca e popola il buffer raw.
      Init_BPP32_B8G8R8A8_BIO_TTB forza l'output a 32-bit BGRA bottom-up. }
    Desc.Init_BPP32_B8G8R8A8_BIO_TTB(0, 0);
    Result := TLazIntfImage.Create(0, 0);
    try
      Result.DataDescription := Desc;
      Stream.Position := 0;
      Result.LoadFromStream(Stream, Reader);
    except
      FreeAndNil(Result);  { stream corrotto o formato non corrispondente }
    end;
  finally
    Reader.Free;
  end;
end;

{ Apre FileName e ne decodifica il contenuto con ReaderClass.
  Comodo wrapper attorno a StreamToIntfImage.
  Restituisce nil se il file non esiste, non è leggibile, o il formato
  non corrisponde al ReaderClass indicato. }
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
    FreeAndNil(Result);  { errore I/O o file corrotto }
  end;
end;

{ Converte una TLazIntfImage in TBitmap nativo della LCL.
  Questa è l'unica funzione del modulo che tocca il widgetset:
  DEVE essere chiamata dal thread principale.
  Restituisce nil se Src è nil o vuota, oppure se CreateBitmaps fallisce. }
function IntfToBitmap(Src: TLazIntfImage): TBitmap;
var
  BmpHandle, MaskHandle: HBitmap;
begin
  Result := nil;
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;
  Result := TBitmap.Create;
  try
    { CreateBitmaps chiede al widgetset di allocare handle OS nativi
      per il bitmap e la maschera a partire dai dati raw. }
    Src.CreateBitmaps(BmpHandle, MaskHandle, False);
    Result.Handle := BmpHandle;
    Result.MaskHandle := MaskHandle;
  except
    FreeAndNil(Result);
  end;
end;

end.
