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

const
  COMICINFO_XML = 'ComicInfo.xml';

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

type
  { Per-image validation result. }
  TImageCheck = record
    EntryName: string;
    Valid: boolean;
    ErrorMsg: string;
  end;
  TImageChecks = array of TImageCheck;

{ Deep-validate a CBZ: tries to decode every image entry.
  Returns the number of readable images and an array of per-entry results.
  Non-image entries (ComicInfo.xml etc.) are skipped, not reported. }
function ValidateCBZImages(const FileName: string;
  out ImageResults: TImageChecks): integer;

{ Legge TUTTE le entry di un CBZ in memoria (senza decodificare le immagini).
  Il chiamante diventa proprietario degli stream e deve liberarli. }
function CollectZipEntries(const FileName: string): TZipEntries;

{ Writes a ZIP file to disk from in-memory entries using DEFLATE compression
  (method 8). Produces smaller output, matching Python reference behaviour. }
procedure WriteZipFromEntriesDeflated(const FileName: string;
  const Entries: TZipEntries);

{ Libera gli stream contenuti in un array TZipEntries. }
procedure FreeZipEntries(var Entries: TZipEntries);

{ Merge di piu' file CBZ in un unico CBZ con pagine rinumerate.
  Filtra ComicInfo.xml. Tutto in RAM. Restituisce le entry del volume. }
function MergeIntoVolume(const SourceFiles: TStringArray;
  const ADir: string): TZipEntries;

{ Converte le immagini di un CBZ in WebP direttamente in RAM.
  Restituisce True se il file e' stato modificato.
  I parametri controllano la qualita' e le opzioni di conversione. }
function ConvertCBZToWebP(const FileName: string; Quality: integer;
  ReplaceOnlyIfSmaller, SkipExistingWebP,
  RemoveComicInfo, RenumberPages: boolean;
  out NewEntryCount: integer): TZipEntries;

{ Filter pages from a CBZ by 1-indexed position.
  PagesToDelete: a boolean array where True = delete this page (1-indexed).
  Removes ComicInfo.xml unconditionally, filters pages by position,
  renumbers survivors as page_NNNN.ext, returns the new entries.
  Caller must FreeZipEntries the result and write via WriteZipFromEntriesDeflated. }
function FilterPagesFromCBZ(const FileName: string;
  const PagesToDelete: array of boolean;
  Renumber: boolean): TZipEntries;

{ Format a page name with zero-padded number: page_NNNN.ext }
function FormatPageName(PageNum, Padding: integer; const Ext: string): string;

implementation

uses
  Zipper,
  zstream,
  Math,
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
  try
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
  except
    { Invalid or empty ZIP — return 0 }
    Result := 0;
  end;
end;

function GetImageFileNames(const FileName: string): TStringArray;
var
  UnZipper: TUnZipper;
  i, ImgCnt: integer;
begin
  Result := nil;
  try
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
  except
    { Invalid or empty ZIP — return nil }
    Result := nil;
  end;
end;

function IsValidCBZ(const FileName: string): boolean;
begin
  Result := GetImageCount(FileName) > 0;
end;

{ TImageValidator }

type
  TImageValidator = class
  private
    FResults: TImageChecks;
    FValidCount: integer;
    procedure CheckImage(const AName: string; AImage: TLazIntfImage;
      var ACancel: boolean);
  end;

procedure TImageValidator.CheckImage(const AName: string;
  AImage: TLazIntfImage; var ACancel: boolean);
var
  n: integer;
begin
  n := Length(FResults);
  SetLength(FResults, n + 1);
  FResults[n].EntryName := AName;
  if AImage <> nil then
  begin
    FResults[n].Valid := True;
    FResults[n].ErrorMsg := '';
    Inc(FValidCount);
  end
  else
  begin
    FResults[n].Valid := False;
    FResults[n].ErrorMsg := 'Image decode failed';
  end;
end;

function ValidateCBZImages(const FileName: string;
  out ImageResults: TImageChecks): integer;
var
  Validator: TImageValidator;
begin
  Validator := TImageValidator.Create;
  try
    Validator.FResults := nil;
    Validator.FValidCount := 0;
    try
      ForEachImage(FileName, @Validator.CheckImage);
    except
      on E: Exception do
      begin
        { File-level error: return it as a single pseudo-entry }
        SetLength(Validator.FResults, 1);
        Validator.FResults[0].EntryName := ExtractFileName(FileName);
        Validator.FResults[0].Valid := False;
        Validator.FResults[0].ErrorMsg := E.Message;
      end;
    end;
    ImageResults := Validator.FResults;
    Result := Validator.FValidCount;
  finally
    Validator.Free;
  end;
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

procedure WriteZipFromEntriesDeflated(const FileName: string;
  const Entries: TZipEntries);
var
  ZW: TZipper;
  ZEntries: TZipFileEntries;
  i: integer;
begin
  ZW := TZipper.Create;
  try
    ZEntries := TZipFileEntries.Create(TZipFileEntry);
    try
      for i := 0 to High(Entries) do
      begin
        Entries[i].Data.Position := 0;
        with ZEntries.AddFileEntry(Entries[i].Data, Entries[i].Name) do
          CompressionLevel := clmax;
      end;
      ZW.ZipFiles(FileName, ZEntries);
    finally
      ZEntries.Free;
    end;
  finally
    ZW.Free;
  end;
end;


function FormatPageName(PageNum, Padding: integer; const Ext: string): string;
var
  NumStr: string;
begin
  NumStr := IntToStr(PageNum);
  while Length(NumStr) < Padding do
    NumStr := '0' + NumStr;
  Result := 'page_' + NumStr + Ext;
end;

function IsConvertibleExt(const Ext: string): boolean;
begin
  Result := SameText(Ext, '.jpg') or SameText(Ext, '.jpeg') or
    SameText(Ext, '.png') or SameText(Ext, '.gif') or
    SameText(Ext, '.bmp') or SameText(Ext, '.tiff') or
    SameText(Ext, '.tif');
end;

function ConvertCBZToWebP(const FileName: string; Quality: integer;
  ReplaceOnlyIfSmaller, SkipExistingWebP,
  RemoveComicInfo, RenumberPages: boolean;
  out NewEntryCount: integer): TZipEntries;

{ Copy entry from source into Result[Count], increment Count }
procedure KeepEntry(var Result: TZipEntries; var Count: integer;
  const AName: string; const Source: TZipEntryData);
begin
  Inc(Count);
  Result[Count - 1].Name := AName;
  Result[Count - 1].Data := TMemoryStream.Create;
  Source.Data.Position := 0;
  Result[Count - 1].Data.CopyFrom(Source.Data, Source.Data.Size);
end;

{ Transfer ownership of AData into Result[Count], increment Count }
procedure AdoptEntry(var Result: TZipEntries; var Count: integer;
  const AName: string; AData: TMemoryStream);
begin
  Inc(Count);
  Result[Count - 1].Name := AName;
  Result[Count - 1].Data := AData;
end;

function PageName(ANum: integer; const AExt: string): string;
begin
  Result := Format('page_%.4d%s', [ANum, AExt]);
end;

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
      AllEntries[i].Data.Position := 0;
      Ext := ExtractFileExt(AllEntries[i].Name);

      { --- ComicInfo.xml: skip or keep --- }
      if SameText(AllEntries[i].Name, COMICINFO_XML) then
      begin
        if RemoveComicInfo then Continue;
        if RenumberPages then
          KeepEntry(Result, PageNum, PageName(PageNum + 1, '.xml'), AllEntries[i])
        else
          KeepEntry(Result, PageNum, AllEntries[i].Name, AllEntries[i]);
        Continue;
      end;

      { --- Non-convertible: keep as-is --- }
      if not IsConvertibleExt(Ext) then
      begin
        if RenumberPages then
          KeepEntry(Result, PageNum, PageName(PageNum + 1, Ext), AllEntries[i])
        else
          KeepEntry(Result, PageNum, AllEntries[i].Name, AllEntries[i]);
        Continue;
      end;

      { --- Skip existing WebP mode --- }
      if SkipExistingWebP then
      begin
        if RenumberPages then
          KeepEntry(Result, PageNum, PageName(PageNum + 1, Ext), AllEntries[i])
        else
          KeepEntry(Result, PageNum, AllEntries[i].Name, AllEntries[i]);
        Continue;
      end;

      { --- Attempt WebP conversion --- }
      RawStream := TMemoryStream.Create;
      try
        RawStream.CopyFrom(AllEntries[i].Data, AllEntries[i].Data.Size);
        RawStream.Position := 0;
        Img := StreamToIntfImage(RawStream, ReaderClassForExt(Ext));
      finally
        RawStream.Free;
      end;

      if Img = nil then
      begin
        { Decode failed, keep original }
        if RenumberPages then
          KeepEntry(Result, PageNum, PageName(PageNum + 1, Ext), AllEntries[i])
        else
          KeepEntry(Result, PageNum, AllEntries[i].Name, AllEntries[i]);
        Continue;
      end;

      WebPData := IntfImageToWebP(Img, Quality);
      Img.Free;

      if WebPData = nil then
      begin
        { Encoding failed, keep original }
        if RenumberPages then
          KeepEntry(Result, PageNum, PageName(PageNum + 1, Ext), AllEntries[i])
        else
          KeepEntry(Result, PageNum, AllEntries[i].Name, AllEntries[i]);
        Continue;
      end;

      { Decide: keep original or adopt WebP }
      if ReplaceOnlyIfSmaller and (WebPData.Size >= AllEntries[i].Data.Size) then
      begin
        { WebP not smaller, discard it }
        WebPData.Free;
        if RenumberPages then
          KeepEntry(Result, PageNum, PageName(PageNum + 1, Ext), AllEntries[i])
        else
          KeepEntry(Result, PageNum, AllEntries[i].Name, AllEntries[i]);
      end
      else
      begin
        { Use WebP }
        if RenumberPages then
          AdoptEntry(Result, PageNum, PageName(PageNum + 1, '.webp'), WebPData)
        else
          AdoptEntry(Result, PageNum, AllEntries[i].Name, WebPData);
      end;
    end;

    { Trim result to actual used entries }
    SetLength(Result, PageNum);
    NewEntryCount := PageNum;
  finally
    FreeZipEntries(AllEntries);
  end;
end;

function MergeIntoVolume(const SourceFiles: TStringArray;
  const ADir: string): TZipEntries;
var
  i, j, PageNum, TotalImages, Padding: integer;
  SrcPath: string;
  Entries: TZipEntries;
  Ext: string;
begin
  Result := nil;
  if Length(SourceFiles) = 0 then Exit;

  { Count total images across all sources }
  TotalImages := 0;
  for i := 0 to High(SourceFiles) do
  begin
    SrcPath := IncludeTrailingPathDelimiter(ADir) + SourceFiles[i];
    Entries := CollectZipEntries(SrcPath);
    for j := 0 to High(Entries) do
      if not SameText(Entries[j].Name, COMICINFO_XML) then
        Inc(TotalImages);
    FreeZipEntries(Entries);
  end;
  Padding := 3;
  if TotalImages > 999 then Padding := 4;
  if TotalImages > 9999 then Padding := 5;

  { Allocate result (worst case) }
  SetLength(Result, TotalImages);
  PageNum := 0;

  for i := 0 to High(SourceFiles) do
  begin
    SrcPath := IncludeTrailingPathDelimiter(ADir) + SourceFiles[i];
    Entries := CollectZipEntries(SrcPath);
    try
      for j := 0 to High(Entries) do
      begin
        if SameText(Entries[j].Name, COMICINFO_XML) then
          Continue;
        Ext := ExtractFileExt(Entries[j].Name);
        Inc(PageNum);
        Result[PageNum - 1].Name := FormatPageName(PageNum, Padding, Ext);
        Result[PageNum - 1].Data := TMemoryStream.Create;
        Entries[j].Data.Position := 0;
        Result[PageNum - 1].Data.CopyFrom(Entries[j].Data, Entries[j].Data.Size);
      end;
    finally
      FreeZipEntries(Entries);
    end;
  end;

  SetLength(Result, PageNum);
end;

function FilterPagesFromCBZ(const FileName: string;
  const PagesToDelete: array of boolean; Renumber: boolean): TZipEntries;
var
  AllEntries: TZipEntries;
  SrcIdx, PageNum, Padding, ImgCount: integer;
  Ext: string;
  DeleteIdx: integer;  // 0-indexed position among image entries only
begin
  Result := nil;
  AllEntries := CollectZipEntries(FileName);
  try
    { First pass: count image-only survivors and compute padding }
    ImgCount := 0;
    PageNum := 0;
    DeleteIdx := 0;
    for SrcIdx := 0 to High(AllEntries) do
    begin
      if SameText(AllEntries[SrcIdx].Name, COMICINFO_XML) then Continue;
      Ext := LowerCase(ExtractFileExt(AllEntries[SrcIdx].Name));
      if not IsImageExt(Ext) then Continue;
      Inc(ImgCount);
      if (DeleteIdx < Length(PagesToDelete)) and PagesToDelete[DeleteIdx] then
        Continue;
      Inc(PageNum);
    end;

    Padding := Max(3, Length(IntToStr(PageNum)));
    SetLength(Result, PageNum);
    PageNum := 0;

    { Second pass: copy survivors }
    DeleteIdx := 0;
    for SrcIdx := 0 to High(AllEntries) do
    begin
      if SameText(AllEntries[SrcIdx].Name, COMICINFO_XML) then Continue;
      Ext := LowerCase(ExtractFileExt(AllEntries[SrcIdx].Name));
      if not IsImageExt(Ext) then Continue;
      if (DeleteIdx < Length(PagesToDelete)) and PagesToDelete[DeleteIdx] then
      begin
        Inc(DeleteIdx);
        Continue;
      end;

      if Renumber then
        Inc(PageNum)
      else
        PageNum := DeleteIdx + 1;
      Result[PageNum - 1].Name := FormatPageName(PageNum, Padding, Ext);
      Result[PageNum - 1].Data := TMemoryStream.Create;
      AllEntries[SrcIdx].Data.Position := 0;
      Result[PageNum - 1].Data.CopyFrom(AllEntries[SrcIdx].Data,
        AllEntries[SrcIdx].Data.Size);
      Inc(DeleteIdx);
    end;
  finally
    FreeZipEntries(AllEntries);
  end;
end;

end.
