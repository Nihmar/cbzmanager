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
  IntfGraphics,
  uzipcore,
  uservicebase;

type
  TImageEntryProc = procedure(const AName: string; AImage: TLazIntfImage;
    var ACancel: boolean) of object;

{ Prima pagina del CBZ come TLazIntfImage (sola memoria, nessuna GDI):
  invocabile da thread secondari. nil se il file non contiene immagini
  leggibili. Il chiamante e' proprietario dell'oggetto restituito. }
function GetFirstImageAsIntfImage(const FileName: string): TLazIntfImage;

{ Scandisce l'archivio decodificando una pagina alla volta e passandola ad
  ACallback: in memoria resta al piu' una pagina per volta. Invocabile da
  thread secondari. }
procedure ForEachImage(const FileName: string; ACallback: TImageEntryProc);

{ Returns the number of image entries found in a CBZ archive.
  Directories and non-image files (e.g. ComicInfo.xml) are not counted.
  Returns 0 if the archive is unreadable or contains no images. }
function GetImageCount(const FileName: string): integer;

{ Returns the file names of all image entries inside the CBZ, in the order
  they appear in the archive.  Returns nil for invalid or empty archives. }
function GetImageFileNames(const FileName: string): TStringArray;

{ Quick validity check: returns True when the CBZ contains at least one
  entry whose extension is recognised as an image format. }
function IsValidCBZ(const FileName: string): boolean;

{ Lightweight check: uses TUnZipper.Examine (central-directory-only scan,
  no decompression) to detect whether the CBZ contains a ComicInfo.xml
  entry.  Returns True on first match, False if none found or archive
  is unreadable. }
function HasComicInfoFast(const FileName: string): boolean;

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

{ Merge di piu' file CBZ in un unico CBZ con pagine rinumerate.
  Filtra ComicInfo.xml. Tutto in RAM. Restituisce le entry del volume.
  AOnProgress (optional) riceve (percent, message) per ogni capitolo processato. }
function MergeIntoVolume(const SourceFiles: TStringArray; const ADir: string;
  AOnProgress: TServiceProgressEvent = nil): TZipEntries;

{ Converte le immagini di un CBZ in WebP direttamente in RAM.
  Restituisce True se il file e' stato modificato.
  I parametri controllano la qualita' e le opzioni di conversione.
  SkipExistingWebP: se True le pagine gia' in formato .webp vengono lasciate
  intatte; se False vengono decodificate e ri-codificate alla qualita' scelta.
  AOnProgress (reserved): non piu' chiamato internamente; il progresso viene
  riportato dal chiamante (TConvertService.Convert) a livello di file. }
function ConvertCBZToWebP(const FileName: string; Quality: integer;
  ReplaceOnlyIfSmaller, SkipExistingWebP, RemoveComicInfo, RenumberPages: boolean;
  out NewEntryCount: integer; out AConvertedCount: integer;
  out AModified: boolean; AOnProgress: TServiceProgressEvent = nil): TZipEntries;

{ Filter pages from a CBZ by 1-indexed position.
  PagesToDelete: a boolean array where True = delete this page (1-indexed).
  Removes ComicInfo.xml unconditionally, filters pages by position,
  renumbers survivors as page_NNNN.ext, returns the new entries.
  Caller must FreeZipEntries the result and write via WriteZipFromEntriesDeflated. }
function FilterPagesFromCBZ(const FileName: string;
  const PagesToDelete: array of boolean; Renumber: boolean): TZipEntries;

implementation

uses
  Zipper,
  Math,
  uImgUtil,
  uWebP,
  uLog;

type
  { TZipImageWalker – streams a CBZ entry by entry through a callback.
  OnCreateStream / OnDoneStream redirect TUnZipper output into memory
  streams.  Each image entry is decoded and handed to FCallback; the
  stream is freed immediately afterwards.  No temporary files are used. }

  TZipImageWalker = class
  private
    FCallback: TImageEntryProc;
    FZip: TUnZipper;
    FCancel: boolean;
    { Allocates a TMemoryStream to receive the decompressed entry data. }
    procedure DoCreateStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
    { Decodes the just-decompressed entry and passes the result to the
      callback.  Frees the stream afterwards – ownership is never
      transferred to the caller. }
    procedure DoDoneStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
  public
    { Runs the full extraction/decoding loop for FileName, calling
      ACallback for every image entry found. }
    procedure Run(const FileName: string; ACallback: TImageEntryProc);
  end;

  { TFirstImageGrabber – keeps only the first successfully decoded image
    and immediately cancels further scanning.  Any subsequent images
    passed to Grab are freed on the spot. }

  TFirstImageGrabber = class
  private
    FImage: TLazIntfImage;
    { Saves the first non-nil image and signals cancellation. }
    procedure Grab(const AName: string; AImage: TLazIntfImage;
      var ACancel: boolean);
  end;

{ Decodes raw image bytes held in a TMemoryStream into a TLazIntfImage.
  Parameters:
    Stream – the uncompressed image data positioned at offset 0.
    Ext    – lowercased extension (e.g. '.webp', '.jpg') used to select
             the correct decoder class.
  Returns a new TLazIntfImage (caller owns it) or nil on failure.
  Exceptions during decoding are caught and logged; nil is returned. }
function DecodeImage(Stream: TMemoryStream; const Ext: string): TLazIntfImage;
var
  FmtExt: string;
begin
  Result := nil;
  if (Stream = nil) or (Stream.Size <= 0) then Exit;
  FmtExt := '';
  try
    { Detect actual format from magic bytes — files inside CBZ archives
      may have a misleading extension (e.g. JPEG data saved as .png). }
    FmtExt := DetectImageFormat(Stream);
    if FmtExt = '' then
      FmtExt := Ext;  { fall back to extension-based detection }
    if SameText(FmtExt, EXT_WEBP) then
      Result := WebPToIntfImage(Stream.Memory, Stream.Size)
    else
      Result := StreamToIntfImage(Stream, ReaderClassForExt(FmtExt));
  except
    on E: Exception do
    begin
      Log('Decode: fallita (ext=%s, detected=%s): %s: %s',
        [Ext, FmtExt, E.ClassName, E.Message]);
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

function HasComicInfoFast(const FileName: string): boolean;
var
  UnZipper: TUnZipper;
  i: integer;
begin
  Result := False;
  try
    UnZipper := TUnZipper.Create;
    try
      UnZipper.FileName := FileName;
      UnZipper.Examine;
      for i := 0 to UnZipper.Entries.Count - 1 do
        if SameText(UnZipper.Entries[i].ArchiveFileName, COMICINFO_XML) then
          Exit(True);
    finally
      UnZipper.Free;
    end;
  except
    { Invalid or empty ZIP — return False }
  end;
end;

{ TImageValidator – receives each decoded image from ForEachImage and
  builds a per-entry report (TImageCheck) recording success or the
  reason for failure. }

type
  TImageValidator = class
  private
    FResults: TImageChecks;
    FValidCount: integer;
    { Appends a TImageCheck for AName to FResults, incrementing
      FValidCount when AImage is valid (non-nil). }
    procedure CheckImage(const AName: string; AImage: TLazIntfImage;
      var ACancel: boolean);
  end;

procedure TImageValidator.CheckImage(const AName: string; AImage: TLazIntfImage;
  var ACancel: boolean);
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
    AImage.Free;
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

{ Returns True when Ext belongs to a raster format that can be re-encoded
  as WebP (JPEG, PNG, GIF, BMP, TIFF).  Extensions already matching .webp
  are NOT convertible – they are already in the target format. }
function IsConvertibleExt(const Ext: string): boolean;
begin
  Result := ExtInList(Ext, CONVERTIBLE_EXTS);
end;

function ConvertCBZToWebP(const FileName: string; Quality: integer;
  ReplaceOnlyIfSmaller, SkipExistingWebP, RemoveComicInfo, RenumberPages: boolean;
  out NewEntryCount: integer; out AConvertedCount: integer;
  out AModified: boolean; AOnProgress: TServiceProgressEvent = nil): TZipEntries;

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
    Result := FormatPageName(ANum, PAGE_PAD_DEFAULT, AExt);
  end;

  { Keep original entry, applying renumber when requested }
  procedure KeepOriginal(var Dest: TZipEntries; var Count: integer;
  const Source: TZipEntryData; const Ext: string);
  var
    NewName: string;
  begin
    if RenumberPages then
    begin
      NewName := PageName(Count + 1, Ext);
      if NewName <> Source.Name then AModified := True;
      KeepEntry(Dest, Count, NewName, Source);
    end
    else
      KeepEntry(Dest, Count, Source.Name, Source);
  end;

  { Try to decode image, encode as WebP, return WebP stream or nil.
    Existing .webp pages are decoded via uWebP (re-encoding at the chosen
    quality); other formats use the matching FPImage reader.
    Detects actual format from magic bytes — extension may be misleading. }
  function TryWebPEncode(const Source: TZipEntryData;
  const Ext: string): TMemoryStream;
  var
    RawStream: TMemoryStream;
    Img: TLazIntfImage;
    FmtExt: string;
  begin
    Result := nil;
    RawStream := TMemoryStream.Create;
    try
      RawStream.CopyFrom(Source.Data, Source.Data.Size);
      RawStream.Position := 0;
      FmtExt := DetectImageFormat(RawStream);
      if FmtExt = '' then
        FmtExt := Ext;  { fall back to extension }
      try
        if SameText(FmtExt, EXT_WEBP) then
          Img := WebPToIntfImage(RawStream.Memory, RawStream.Size)
        else
          Img := StreamToIntfImage(RawStream, ReaderClassForExt(FmtExt));
      except
        on E: Exception do
        begin
          Log('TryWebPEncode: decode failed for %s (%s): %s',
            [ExtractFileName(Ext), FmtExt, E.Message]);
          Img := nil;
        end;
      end;
    finally
      RawStream.Free;
    end;
    if Img = nil then Exit;
    try
      Result := IntfImageToWebP(Img, Quality);
    finally
      Img.Free;
    end;
  end;

var
  AllEntries: TZipEntries;
  i, PageNum: integer;
  Ext: string;
  WebPData: TMemoryStream;
begin
  Result := nil;
  NewEntryCount := 0;
  AConvertedCount := 0;
  AModified := False;
  AllEntries := CollectZipEntries(FileName);
  if Length(AllEntries) = 0 then Exit;

  try
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
          if RemoveComicInfo then
            AModified := True
          else
            KeepEntry(Result, PageNum, COMICINFO_XML, AllEntries[i]);
          FreeAndNil(AllEntries[i].Data);
          Continue;
        end;

        { --- Existing .webp: keep as-is when skipping, otherwise fall
              through to re-encode it at the chosen quality. --- }
        if SameText(Ext, EXT_WEBP) then
        begin
          if SkipExistingWebP then
          begin
            KeepOriginal(Result, PageNum, AllEntries[i], Ext);
            FreeAndNil(AllEntries[i].Data);
            Continue;
          end;
        end
        { --- Other non-convertible formats: always keep as-is --- }
        else if not IsConvertibleExt(Ext) then
        begin
          KeepOriginal(Result, PageNum, AllEntries[i], Ext);
          FreeAndNil(AllEntries[i].Data);
          Continue;
        end;

        { --- Attempt WebP conversion --- }
        WebPData := TryWebPEncode(AllEntries[i], Ext);

        if (WebPData = nil) or (ReplaceOnlyIfSmaller and
          (WebPData.Size >= AllEntries[i].Data.Size)) then
        begin
          WebPData.Free;
          KeepOriginal(Result, PageNum, AllEntries[i], Ext);
        end
        else
        begin
          AModified := True;
          Inc(AConvertedCount);
          if RenumberPages then
            AdoptEntry(Result, PageNum, PageName(PageNum + 1, EXT_WEBP), WebPData)
          else
            AdoptEntry(Result, PageNum, AllEntries[i].Name, WebPData);
        end;
        FreeAndNil(AllEntries[i].Data);
      end;

      { Trim result to actual used entries }
      SetLength(Result, PageNum);
      NewEntryCount := PageNum;
    except
      SetLength(Result, PageNum);
      FreeZipEntries(Result);
      raise;
    end;
  finally
    FreeZipEntries(AllEntries);
  end;
end;

function MergeIntoVolume(const SourceFiles: TStringArray; const ADir: string;
  AOnProgress: TServiceProgressEvent = nil): TZipEntries;
var
  i, j, PageNum, Padding: integer;
  SrcPath: string;
  Entries: TZipEntries;
begin
  Result := nil;
  if Length(SourceFiles) = 0 then Exit;

  try
    PageNum := 0;
    for i := 0 to High(SourceFiles) do
    begin
      if Assigned(AOnProgress) then
        AOnProgress((i * 100) div Length(SourceFiles),
          Format('  Adding %s (%d/%d)', [SourceFiles[i], i + 1, Length(SourceFiles)]));

      SrcPath := IncludeTrailingPathDelimiter(ADir) + SourceFiles[i];
      Entries := CollectZipEntries(SrcPath);
      try
        for j := 0 to High(Entries) do
        begin
          if SameText(Entries[j].Name, COMICINFO_XML) then
            Continue;
          SetLength(Result, PageNum + 1);
          Result[PageNum].Name := LowerCase(ExtractFileExt(Entries[j].Name));
          Result[PageNum].Data := Entries[j].Data;
          Entries[j].Data := nil;
          Inc(PageNum);
        end;
      finally
        FreeZipEntries(Entries);
      end;
    end;

    Padding := PagePaddingFor(PageNum);

    for i := 0 to PageNum - 1 do
      Result[i].Name := FormatPageName(i + 1, Padding, Result[i].Name);
  except
    FreeZipEntries(Result);
    raise;
  end;
end;

function FilterPagesFromCBZ(const FileName: string;
  const PagesToDelete: array of boolean; Renumber: boolean): TZipEntries;
var
  AllEntries: TZipEntries;
  SrcIdx, Padding, ImgCount, Survivors, OutIdx, NameNum: integer;
  Ext: string;
  DeleteIdx: integer;  // 0-indexed position among image entries only
begin
  Result := nil;
  AllEntries := CollectZipEntries(FileName);
  try
    try
      { First pass: count total images and surviving images.  DeleteIdx must
        advance once per image so it indexes PagesToDelete in lockstep with
        the second pass; without this the survivor count (and thus the
        Result allocation) is wrong. }
      ImgCount := 0;
      Survivors := 0;
      DeleteIdx := 0;
      for SrcIdx := 0 to High(AllEntries) do
      begin
        if SameText(AllEntries[SrcIdx].Name, COMICINFO_XML) then Continue;
        Ext := LowerCase(ExtractFileExt(AllEntries[SrcIdx].Name));
        if not IsImageExt(Ext) then Continue;
        Inc(ImgCount);
        if not ((DeleteIdx < Length(PagesToDelete)) and PagesToDelete[DeleteIdx]) then
          Inc(Survivors);
        Inc(DeleteIdx);
      end;

      { Padding: when renumbering, output names run 1..Survivors; when keeping
        the original numbers (with gaps) they run within 1..ImgCount, so pad
        for the larger space to keep one uniform width across the archive. }
      if Renumber then
        Padding := PagePaddingFor(Survivors)
      else
        Padding := PagePaddingFor(ImgCount);

      SetLength(Result, Survivors);

      { Second pass: copy survivors into compacted slots (OutIdx).  Each
        surviving page is named either by its new sequential number
        (Renumber) or by its original 1-based image position (keep the
        numbers, leaving gaps where pages were removed). }
      DeleteIdx := 0;
      OutIdx := 0;
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
          NameNum := OutIdx + 1
        else
          NameNum := DeleteIdx + 1;  { original 1-based position; gaps kept }

        Result[OutIdx].Name := FormatPageName(NameNum, Padding, Ext);
        Result[OutIdx].Data := TMemoryStream.Create;
        AllEntries[SrcIdx].Data.Position := 0;
        Result[OutIdx].Data.CopyFrom(AllEntries[SrcIdx].Data,
          AllEntries[SrcIdx].Data.Size);
        Inc(OutIdx);
        Inc(DeleteIdx);
      end;

      { Safety: trim to the slots actually written (equals Survivors). }
      SetLength(Result, OutIdx);
    except
      FreeZipEntries(Result);
      raise;
    end;
  finally
    FreeZipEntries(AllEntries);
  end;
end;

end.
