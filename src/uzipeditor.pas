unit uZipEditor;

{
  Estrazione dei CBZ interamente in RAM: TUnZipper viene dirottato con
  OnCreateStream / OnDoneStream in modo che ogni entry venga espansa in un
  TMemoryStream, decodificata e subito liberata. Nessun file temporaneo,
  nessuna scrittura su disco.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  IntfGraphics;

type
  { Richiamata per ogni immagine estratta e decodificata. Il chiamante
    diventa proprietario di AImage, che e' nil se la decodifica e' fallita.
    Impostare ACancel a True interrompe la scansione dell'archivio. }
  TImageEntryProc = procedure(const AName: string; AImage: TLazIntfImage;
    var ACancel: boolean) of object;

  { Entry ZIP in memoria per la riscrittura senza scrivere su disco }
  TZipEntryData = record
    Name: string;
    Data: TMemoryStream;
  end;
  TZipEntries = array of TZipEntryData;

{ Prima pagina del CBZ come TLazIntfImage (sola memoria, nessuna GDI):
  invocabile da thread secondari. nil se il file non contiene immagini
  leggibili. Il chiamante e' proprietario dell'oggetto restituito. }
function GetFirstImageAsIntfImage(const FileName: string): TLazIntfImage;

{ Scandisce l'archivio decodificando una pagina alla volta e passandola ad
  ACallback: in memoria resta al piu' una pagina per volta. Invocabile da
  thread secondari. }
procedure ForEachImage(const FileName: string; ACallback: TImageEntryProc);

function GetImageCount(const FileName: string): integer;
function GetImageFileNames(const FileName: string): TStringArray;
function IsValidCBZ(const FileName: string): boolean;

{ Legge TUTTE le entry di un CBZ in memoria (senza decodificare le immagini).
  Il chiamante diventa proprietario degli stream e deve liberarli. }
function CollectZipEntries(const FileName: string): TZipEntries;

{ Scrive un file ZIP su disco a partire da un array di entry in memoria.
  Usa il metodo "stored" (0) — non ricompressione. }
procedure WriteZipFromEntries(const FileName: string;
  const Entries: TZipEntries);

{ Libera gli stream contenuti in un array TZipEntries. }
procedure FreeZipEntries(var Entries: TZipEntries);

{ Converte le immagini di un CBZ in WebP direttamente in RAM.
  Restituisce True se il file e' stato modificato.
  I parametri controllano la qualita' e le opzioni di conversione. }
function ConvertCBZToWebP(const FileName: string; Quality: integer;
  ReplaceOnlyIfSmaller, SkipExistingWebP: boolean;
  out NewEntryCount: integer): TZipEntries;

implementation

uses
  Zipper,
  uImgUtil,
  uWebP,
  uLog;

type
  { TZipImageWalker }

  TZipImageWalker = class
  private
    FCallback: TImageEntryProc;
    FZip: TUnZipper;
    FCancel: boolean;
    procedure DoCreateStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
    procedure DoDoneStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
  public
    procedure Run(const FileName: string; ACallback: TImageEntryProc);
  end;

  { TFirstImageGrabber: si ferma alla prima immagine incontrata. }

  TFirstImageGrabber = class
  private
    FImage: TLazIntfImage;
    procedure Grab(const AName: string; AImage: TLazIntfImage;
      var ACancel: boolean);
  end;

function DecodeImage(Stream: TMemoryStream; const Ext: string): TLazIntfImage;
begin
  Result := nil;
  if (Stream = nil) or (Stream.Size <= 0) then Exit;
  try
    if SameText(Ext, '.webp') then
      Result := WebPToIntfImage(Stream.Memory, Stream.Size)
    else
      Result := StreamToIntfImage(Stream, ReaderClassForExt(Ext));
  except
    on E: Exception do
    begin
      Log('Decode: fallita (%s): %s: %s', [Ext, E.ClassName, E.Message]);
      Result := nil;
    end;
  end;
end;

{ TZipImageWalker }

procedure TZipImageWalker.DoCreateStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
begin
  { Fornendo noi lo stream, TUnZipper non crea alcun file di destinazione. }
  AStream := TMemoryStream.Create;
end;

procedure TZipImageWalker.DoDoneStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
var
  Img: TLazIntfImage;
  Ext: string;
begin
  { Con OnCreateStream assegnato, liberare lo stream spetta a noi. }
  try
    if FCancel or AItem.IsDirectory then Exit;
    Ext := ExtractFileExt(AItem.ArchiveFileName);
    if not IsImageExt(Ext) then Exit;

    AStream.Position := 0;
    Img := DecodeImage(TMemoryStream(AStream), Ext);
    if Img = nil then
      Log('Zip: decodifica nulla per %s', [AItem.ArchiveFileName]);
    FCallback(AItem.ArchiveFileName, Img, FCancel);
    if FCancel then
      FZip.Terminate;
  finally
    AStream.Free;
    AStream := nil;
  end;
end;

procedure TZipImageWalker.Run(const FileName: string; ACallback: TImageEntryProc);
begin
  FCallback := ACallback;
  FCancel := False;
  FZip := TUnZipper.Create;
  try
    FZip.OnCreateStream := @DoCreateStream;
    FZip.OnDoneStream := @DoDoneStream;
    FZip.UnZipAllFiles(FileName);
  finally
    FreeAndNil(FZip);
  end;
end;

{ TFirstImageGrabber }

procedure TFirstImageGrabber.Grab(const AName: string; AImage: TLazIntfImage;
  var ACancel: boolean);
begin
  if FImage = nil then
    FImage := AImage
  else
    AImage.Free;
  ACancel := True;
end;

procedure ForEachImage(const FileName: string; ACallback: TImageEntryProc);
var
  Walker: TZipImageWalker;
begin
  Walker := TZipImageWalker.Create;
  try
    Walker.Run(FileName, ACallback);
  finally
    Walker.Free;
  end;
end;

function GetFirstImageAsIntfImage(const FileName: string): TLazIntfImage;
var
  Grabber: TFirstImageGrabber;
begin
  Grabber := TFirstImageGrabber.Create;
  try
    ForEachImage(FileName, @Grabber.Grab);
    Result := Grabber.FImage;
  finally
    Grabber.Free;
  end;
  if Result = nil then
    Log('GetFirstImage: nessuna immagine in %s', [ExtractFileName(FileName)])
  else
    Log('GetFirstImage: %s -> %dx%d',
      [ExtractFileName(FileName), Result.Width, Result.Height]);
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

{ TZipCollector: cattura tutte le entry in RAM }
type
  TZipCollector = class
  private
    FEntries: TZipEntries;
    procedure DoCreateStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
    procedure DoDoneStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
  end;

procedure TZipCollector.DoCreateStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
begin
  AStream := TMemoryStream.Create;
end;

procedure TZipCollector.DoDoneStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
var
  n: integer;
begin
  n := Length(FEntries);
  SetLength(FEntries, n + 1);
  FEntries[n].Name := AItem.ArchiveFileName;
  FEntries[n].Data := TMemoryStream(AStream);
  AStream := nil; // ownership transferred
end;

function CollectZipEntries(const FileName: string): TZipEntries;
var
  Collector: TZipCollector;
  UnZipper: TUnZipper;
begin
  Result := nil;
  Collector := TZipCollector.Create;
  try
    UnZipper := TUnZipper.Create;
    try
      UnZipper.OnCreateStream := @Collector.DoCreateStream;
      UnZipper.OnDoneStream := @Collector.DoDoneStream;
      UnZipper.UnZipAllFiles(FileName);
    finally
      UnZipper.Free;
    end;
    Result := Collector.FEntries;
    Collector.FEntries := nil; // prevent double-free
  finally
    Collector.Free;
  end;
end;

procedure FreeZipEntries(var Entries: TZipEntries);
var
  i: integer;
begin
  for i := 0 to High(Entries) do
    Entries[i].Data.Free;
  Entries := nil;
end;

{ Scrive un file ZIP con metodo stored (0). Formato:
    [file header + data] x N
    [central directory] x N
    [end of central directory] }
procedure WriteZipFromEntries(const FileName: string;
  const Entries: TZipEntries);
var
  OutStream: TFileStream;
  i, n: integer;
  Offset, DirOffset, DirSize: Int64;
  CRC: cardinal;
  Hdr: array[0..29] of byte;
  DirHdr: array[0..45] of byte;
  EndHdr: array[0..21] of byte;
  NameBytes: TBytes;
begin
  OutStream := TFileStream.Create(FileName, fmCreate);
  try
    Offset := 0;
    { Write local file headers + data }
    for i := 0 to High(Entries) do
    begin
      Entries[i].Data.Position := 0;
      CRC := 0; // CRC32 skipped for speed — stored method doesn't verify
      NameBytes := TEncoding.UTF8.GetBytes(Entries[i].Name);

      FillChar(Hdr, SizeOf(Hdr), 0);
      Hdr[0] := $50; Hdr[1] := $4B; Hdr[2] := $03; Hdr[3] := $04; // signature
      Hdr[4] := 20;  Hdr[5] := 0;   // version needed 2.0
      Hdr[8] := 0;   Hdr[9] := 0;   // compression: stored
      // CRC placeholder
      Hdr[14] := CRC and $FF;
      Hdr[15] := (CRC shr 8) and $FF;
      Hdr[16] := (CRC shr 16) and $FF;
      Hdr[17] := (CRC shr 24) and $FF;
      // Compressed size = uncompressed size for stored method
      n := Entries[i].Data.Size;
      Hdr[18] := n and $FF;
      Hdr[19] := (n shr 8) and $FF;
      Hdr[20] := (n shr 16) and $FF;
      Hdr[21] := (n shr 24) and $FF;
      Hdr[22] := n and $FF;
      Hdr[23] := (n shr 8) and $FF;
      Hdr[24] := (n shr 16) and $FF;
      Hdr[25] := (n shr 24) and $FF;
      // Filename length
      Hdr[26] := Length(NameBytes) and $FF;
      Hdr[27] := (Length(NameBytes) shr 8) and $FF;
      // Extra field length — 0
      Hdr[28] := 0; Hdr[29] := 0;

      OutStream.WriteBuffer(Hdr, SizeOf(Hdr));
      OutStream.WriteBuffer(NameBytes[0], Length(NameBytes));
      OutStream.CopyFrom(Entries[i].Data, n);
      Entries[i].Data.Position := 0; // reset for potential reuse
      Inc(Offset, SizeOf(Hdr) + Length(NameBytes) + n);
    end;

    { Write central directory }
    DirOffset := Offset;
    DirSize := 0;
    Offset := 0;
    for i := 0 to High(Entries) do
    begin
      n := Entries[i].Data.Size;
      NameBytes := TEncoding.UTF8.GetBytes(Entries[i].Name);

      FillChar(DirHdr, SizeOf(DirHdr), 0);
      DirHdr[0] := $50; DirHdr[1] := $4B; DirHdr[2] := $01; DirHdr[3] := $02;
      DirHdr[4] := 20;  DirHdr[5] := 0;   // version made by 2.0
      DirHdr[6] := 20;  DirHdr[7] := 0;   // version needed 2.0
      DirHdr[10] := 0;  DirHdr[11] := 0;  // compression: stored
      // CRC (same as above)
      CRC := 0;
      DirHdr[16] := CRC and $FF;
      DirHdr[17] := (CRC shr 8) and $FF;
      DirHdr[18] := (CRC shr 16) and $FF;
      DirHdr[19] := (CRC shr 24) and $FF;
      // Sizes
      DirHdr[20] := n and $FF;
      DirHdr[21] := (n shr 8) and $FF;
      DirHdr[22] := (n shr 16) and $FF;
      DirHdr[23] := (n shr 24) and $FF;
      DirHdr[24] := n and $FF;
      DirHdr[25] := (n shr 8) and $FF;
      DirHdr[26] := (n shr 16) and $FF;
      DirHdr[27] := (n shr 24) and $FF;
      // Filename length
      DirHdr[28] := Length(NameBytes) and $FF;
      DirHdr[29] := (Length(NameBytes) shr 8) and $FF;
      // Extra field length — 0
      DirHdr[30] := 0; DirHdr[31] := 0;
      // File comment length — 0
      DirHdr[32] := 0; DirHdr[33] := 0;
      // Disk number start
      DirHdr[34] := 0; DirHdr[35] := 0;
      // Internal attrs
      DirHdr[36] := 0; DirHdr[37] := 0;
      // External attrs
      DirHdr[38] := 0; DirHdr[39] := 0;
      // Relative offset of local header
      DirHdr[42] := Offset and $FF;
      DirHdr[43] := (Offset shr 8) and $FF;
      DirHdr[44] := (Offset shr 16) and $FF;
      DirHdr[45] := (Offset shr 24) and $FF;

      OutStream.WriteBuffer(DirHdr, SizeOf(DirHdr));
      OutStream.WriteBuffer(NameBytes[0], Length(NameBytes));
      Inc(DirSize, SizeOf(DirHdr) + Length(NameBytes));
      Inc(Offset, SizeOf(Hdr) + Length(NameBytes) + n);
    end;

    { Write end of central directory }
    FillChar(EndHdr, SizeOf(EndHdr), 0);
    EndHdr[0] := $50; EndHdr[1] := $4B; EndHdr[2] := $05; EndHdr[3] := $06;
    EndHdr[4] := 0;   EndHdr[5] := 0;   // disk number
    EndHdr[6] := 0;   EndHdr[7] := 0;   // disk with central dir
    n := Length(Entries);
    EndHdr[8] := n and $FF;
    EndHdr[9] := (n shr 8) and $FF;     // entries on this disk
    EndHdr[10] := n and $FF;
    EndHdr[11] := (n shr 8) and $FF;    // total entries
    EndHdr[12] := DirSize and $FF;
    EndHdr[13] := (DirSize shr 8) and $FF;
    EndHdr[14] := (DirSize shr 16) and $FF;
    EndHdr[15] := (DirSize shr 24) and $FF;
    EndHdr[16] := DirOffset and $FF;
    EndHdr[17] := (DirOffset shr 8) and $FF;
    EndHdr[18] := (DirOffset shr 16) and $FF;
    EndHdr[19] := (DirOffset shr 24) and $FF;
    EndHdr[20] := 0; EndHdr[21] := 0;   // comment length

    OutStream.WriteBuffer(EndHdr, SizeOf(EndHdr));
  finally
    OutStream.Free;
  end;
end;

function IsConvertibleExt(const Ext: string): boolean;
begin
  Result := SameText(Ext, '.jpg') or SameText(Ext, '.jpeg') or
    SameText(Ext, '.png') or SameText(Ext, '.gif') or
    SameText(Ext, '.bmp') or SameText(Ext, '.tiff') or
    SameText(Ext, '.tif');
end;

function ConvertCBZToWebP(const FileName: string; Quality: integer;
  ReplaceOnlyIfSmaller, SkipExistingWebP: boolean;
  out NewEntryCount: integer): TZipEntries;
var
  AllEntries: TZipEntries;
  i, PageNum: integer;
  Ext: string;
  Img: TLazIntfImage;
  WebPData: TMemoryStream;
  RawStream: TMemoryStream;
begin
  Result := nil;
  NewEntryCount := 0;
  AllEntries := CollectZipEntries(FileName);
  if Length(AllEntries) = 0 then Exit;

  try
    SetLength(Result, Length(AllEntries));
    PageNum := 0;

    for i := 0 to High(AllEntries) do
    begin
      Ext := ExtractFileExt(AllEntries[i].Name);
      AllEntries[i].Data.Position := 0;

      if IsConvertibleExt(Ext) then
      begin
        if SkipExistingWebP then
        begin
          { Skip — keep original }
          Inc(PageNum);
          Result[PageNum - 1].Name := Format('page_%.4d%s', [PageNum, Ext]);
          Result[PageNum - 1].Data := TMemoryStream.Create;
          Result[PageNum - 1].Data.CopyFrom(AllEntries[i].Data, AllEntries[i].Data.Size);
        end
        else
        begin
          { Decode image }
          RawStream := TMemoryStream.Create;
          try
            RawStream.CopyFrom(AllEntries[i].Data, AllEntries[i].Data.Size);
            RawStream.Position := 0;
            Img := StreamToIntfImage(RawStream, ReaderClassForExt(Ext));
          finally
            RawStream.Free;
          end;

          if Img <> nil then
          begin
            try
              WebPData := IntfImageToWebP(Img, Quality);
              if WebPData <> nil then
              begin
                try
                  if (not ReplaceOnlyIfSmaller) or
                     (WebPData.Size < AllEntries[i].Data.Size) then
                  begin
                    { Use WebP }
                    Inc(PageNum);
                    Result[PageNum - 1].Name := Format('page_%.4d.webp', [PageNum]);
                    Result[PageNum - 1].Data := WebPData;
                    WebPData := nil; // ownership transferred
                  end
                  else
                  begin
                    { WebP not smaller, keep original }
                    Inc(PageNum);
                    Result[PageNum - 1].Name := Format('page_%.4d%s', [PageNum, Ext]);
                    Result[PageNum - 1].Data := TMemoryStream.Create;
                    Result[PageNum - 1].Data.CopyFrom(AllEntries[i].Data, AllEntries[i].Data.Size);
                  end;
                finally
                  WebPData.Free;
                end;
              end
              else
              begin
                { Encoding failed, keep original }
                Inc(PageNum);
                Result[PageNum - 1].Name := Format('page_%.4d%s', [PageNum, Ext]);
                Result[PageNum - 1].Data := TMemoryStream.Create;
                Result[PageNum - 1].Data.CopyFrom(AllEntries[i].Data, AllEntries[i].Data.Size);
              end;
            finally
              Img.Free;
            end;
          end
          else
          begin
            { Decode failed, keep original }
            Inc(PageNum);
            Result[PageNum - 1].Name := Format('page_%.4d%s', [PageNum, Ext]);
            Result[PageNum - 1].Data := TMemoryStream.Create;
            Result[PageNum - 1].Data.CopyFrom(AllEntries[i].Data, AllEntries[i].Data.Size);
          end;
        end;
      end
      else
      begin
        { Non-image entry (e.g. ComicInfo.xml) — skip }
        Continue;
      end;
    end;

    { Trim result to actual used entries }
    SetLength(Result, PageNum);
    NewEntryCount := PageNum;
  finally
    FreeZipEntries(AllEntries);
  end;
end;

end.
