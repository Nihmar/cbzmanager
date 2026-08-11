unit uZipEditor;

{
  CBZ extraction entirely in RAM: TUnZipper is diverted with
  OnCreateStream / OnDoneStream so that every entry is expanded into a
  TMemoryStream, decoded and immediately freed. No temporary files,
  no disk writes.
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
  { Callback invoked for every image entry of a CBZ.
    AIndex is the entry's rank when all image entries are sorted by name
    (CompareStr, matching the Python reference's sorted(namelist())); -1
    when the order is unknown. }
  TImageEntryProc = procedure(const AName: string; AImage: TLazIntfImage;
    AIndex: integer; var ACancel: boolean) of object;

{
  First page of the CBZ as a TLazIntfImage (memory only, no GDI):
  callable from worker threads. nil if the file contains no readable
  images. The caller owns the returned object. }
function GetFirstImageAsIntfImage(const FileName: string): TLazIntfImage;

{
  Like GetFirstImageAsIntfImage, but in a single pass over the file: it
  also reports whether the CBZ contains ComicInfo.xml (for the thumbnail
  badge) and decodes at reduced resolution when AMaxW/AMaxH > 0 (JPEG DCT
  scaling). The chosen page is the first by alphabetical name order (like
  page 0 of the viewer), not the first archive entry. True if the image
  was decoded. }
function GetFirstImageInfo(const FileName: string; out AImage: TLazIntfImage;
  out AHasComicInfo: boolean; AMaxW, AMaxH: integer): boolean;

{
  Decodes a single named image entry of a CBZ at full resolution.
  The central directory is scanned for the exact entry name, then only
  that one entry is decompressed (no temp files).  Returns nil when the
  entry does not exist, is not an image, or fails to decode.  The caller
  owns the returned object.  Callable from worker threads. }
function GetImageAsIntfImage(const FileName, EntryName: string): TLazIntfImage;

{ Decodes raw image bytes held in a TMemoryStream into a TLazIntfImage.
  Parameters:
    Stream – the uncompressed image data positioned at offset 0.
    Ext    – lowercased extension (e.g. '.webp', '.jpg') used to select
             the correct decoder class.
    MaxW/MaxH – when both > 0, JPEG entries are decoded at reduced
             resolution (DCT scaling, see StreamToIntfImage). 0 = full size.
  Returns a new TLazIntfImage (caller owns it) or nil on failure.
  Exceptions during decoding are caught and logged; nil is returned. }
function DecodeImage(Stream: TMemoryStream; const Ext: string;
  MaxW: integer = 0; MaxH: integer = 0): TLazIntfImage;

{ ---------------------------------------------------------------------------
  CBR (RAR) archives — read via libarchive (uarchive.pas), entirely in RAM.

  RAR has no central directory, so the walkers scan the archive twice:
  once for the entry names (data skipped) and once for the data.  The
  source file is only ever opened read-only; everything decompressed lands
  in memory.  Raise behaviour mirrors the ZIP equivalents.
  --------------------------------------------------------------------------- }

{ Reads every entry of a CBR into memory (parity with CollectZipEntries).
  RAR has no central directory, so a fast counting pass precedes the data
  pass; AOnProgress (optional) receives (percent, message) per entry with
  0–100 within the file (the caller folds it into batch progress). }
function CollectCbrEntries(const FileName: string;
  AOnProgress: TServiceProgressEvent = nil): TZipEntries;

{ Scans a CBR decoding one page at a time and passing it to ACallback
  (parity with ForEachImage).  AMaxW/AMaxH > 0 decode JPEG pages at
  reduced resolution.  The callback receives each page's alphabetical
  rank via AIndex (0 = first page in reading order).  Raises when the
  archive cannot be read; the caller is expected to catch. }
procedure ForEachCbrImage(const FileName: string; ACallback: TImageEntryProc;
  AMaxW: integer = 0; AMaxH: integer = 0);

{ First page (by alphabetical name order) of a CBR as a TLazIntfImage,
  plus ComicInfo.xml presence for the thumbnail badge.  Parity with
  GetFirstImageInfo.  False (and AImage = nil) when libarchive is missing,
  the archive is unreadable, or it contains no readable images. }
function GetCbrFirstImageInfo(const FileName: string; out AImage: TLazIntfImage;
  out AHasComicInfo: boolean; AMaxW, AMaxH: integer): boolean;

{ Decodes a single named entry of a CBR at full resolution (parity with
  GetImageAsIntfImage).  nil when libarchive is missing, the entry does
  not exist, or the decode fails.  The caller owns the result. }
function GetCbrImageAsIntfImage(const FileName, EntryName: string): TLazIntfImage;

{ Converts a CBR to CBZ entries entirely in RAM: strips ComicInfo.xml and
  non-image entries, renumbers the survivors page_NNNN.* (padding via
  PagePaddingFor).  The caller writes the result with
  WriteZipFromEntriesDeflated and frees it with FreeZipEntries.  The
  source .cbr is never modified.  Raises on unreadable archives.
  AOnProgress (optional) is forwarded to CollectCbrEntries (per entry,
  0–100 within the file). }
function ConvertCbrToCbz(const SourceFile: string;
  AOnProgress: TServiceProgressEvent = nil): TZipEntries;

{
  Scans the archive decoding one page at a time and passing it to
  ACallback: at most one page stays in memory at a time. Callable from
  worker threads. When AMaxW/AMaxH > 0, JPEG pages are decoded at reduced
  resolution (see StreamToIntfImage). Pages are passed in archive order,
  but ACallback receives in AIndex the position the page occupies in the
  alphabetical ordering of the names. }
procedure ForEachImage(const FileName: string; ACallback: TImageEntryProc;
  AMaxW: integer = 0; AMaxH: integer = 0);

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
  Non-image entries (ComicInfo.xml etc.) are skipped, not reported.
  AThreads controls decode parallelism: 0 = automatic (CPU count, capped
  at 8), 1 = sequential.  Every worker holds one full-resolution image in
  RAM.  The per-entry results are deterministic regardless of AThreads —
  they are assembled in archive order after the pool joins. }
function ValidateCBZImages(const FileName: string;
  out ImageResults: TImageChecks; AThreads: integer = 0): integer;

{
  Merges multiple CBZ files into a single CBZ with renumbered pages.
  Filters out ComicInfo.xml. Everything in RAM. Returns the volume entries.
  AOnProgress (optional) receives (percent, message) per processed chapter. }
function MergeIntoVolume(const SourceFiles: TStringArray; const ADir: string;
  AOnProgress: TServiceProgressEvent = nil): TZipEntries;

{
  Converts the images of a CBZ to WebP directly in RAM.
  Returns True if the file was modified.
  The parameters control the quality and the conversion options.
  SkipExistingWebP: if True, pages already in .webp format are left
  intact; if False they are decoded and re-encoded at the chosen quality.
  AThreads controls decode/encode parallelism: 0 = automatic (CPU count,
  capped at 8), 1 = sequential.  Every worker holds one full-resolution
  image in RAM, so the pool multiplies the peak memory of a single page.
  The result is deterministic regardless of AThreads: pages are written
  back in archive order.
  AOnProgress (optional) receives (percent, message) per archive entry —
  the WebP encode of a large page is the slowest step, so every entry
  (skips included) reports activity.  Percent is 0–100 WITHIN the file;
  the caller folds it into the batch's global progress. }
function ConvertCBZToWebP(const FileName: string; Quality: integer;
  ReplaceOnlyIfSmaller, SkipExistingWebP, RemoveComicInfo, RenumberPages: boolean;
  out NewEntryCount: integer; out AConvertedCount: integer;
  out AModified: boolean; AOnProgress: TServiceProgressEvent = nil;
  AThreads: integer = 0): TZipEntries;

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
  uLog,
  uarchive;

type
  { One conversion slot per source entry, filled by a pool worker and read
    by the sequential compaction pass.  Slot[i] corresponds to entry i of
    the archive; the worker writes only its own slot (each work index is
    claimed exactly once), so no locking is needed on the slot writes. }
  TConvertSlot = record
    { Decoded+re-encoded WebP stream, or nil when decode/encode failed
      (the original entry is then kept).  Owned by the slot. }
    Data: TMemoryStream;
  end;
  TConvertSlots = array of TConvertSlot;

  { Shared state of a WebP conversion pool: the job list, the slots, the
    claim counter and the progress callback.  All mutable fields are
    guarded by Lock; the pool owner creates it and frees it after join. }
  TConvertPoolState = class
    Lock: TRTLCriticalSection;
    Entries: TZipEntries;        { read-only source data }
    Slots: TConvertSlots;        { one writer per index }
    Work: array of integer;      { indices of convertible entries }
    Next: integer;               { next index into Work (under Lock) }
    Completed: integer;          { finished jobs (under Lock) }
    Quality: integer;
    BaseName: string;            { ExtractFileName(FileName), for messages }
    OnProgress: TServiceProgressEvent;
    Error: string;               { first worker exception (under Lock) }
    constructor Create;
    destructor Destroy; override;
  end;

  { Pool worker: claims convertible entry indices under the shared lock and
    decodes + WebP-encodes each one into its own slot.  DecodeImage and
    IntfImageToWebP are stateless per call, so workers never share mutable
    state except the pool fields above.  Progress is reported per finished
    job, serialized by the lock (a callback may itself block, e.g. the
    service thread's Synchronize). }
  TWebPConvertWorker = class(TThread)
  private
    FPool: TConvertPoolState;
  protected
    procedure Execute; override;
  public
    constructor Create(APool: TConvertPoolState);
  end;

type
  { TZipImageWalker – streams a CBZ entry by entry through a callback.
  OnCreateStream / OnDoneStream redirect TUnZipper output into memory
  streams.  Each image entry is decoded and handed to FCallback; the
  stream is freed immediately afterwards.  No temporary files are used.
  The archive is scanned once (central directory) so each image entry's
  alphabetical rank can be passed to the callback. }

  TZipImageWalker = class
  private
    FCallback: TImageEntryProc;
    FZip: TUnZipper;
    FCancel: boolean;
    FMaxW: integer;
    FMaxH: integer;
    { Image entry names sorted with CompareStr; FSortedNames[i] has rank i. }
    FSortedNames: TStringList;
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
    procedure Run(const FileName: string; ACallback: TImageEntryProc;
      AMaxW: integer = 0; AMaxH: integer = 0);
  end;

  { TFirstImageGrabber – keeps only the first successfully decoded image,
    frees any others, and flags ComicInfo presence.  Used with a single-entry
    extraction pass so only the first image entry is decompressed. }

  TFirstImageGrabber = class
  private
    FImage: TLazIntfImage;
    FMaxW: integer;
    FMaxH: integer;
    { Saves the first non-nil image and signals cancellation. }
    procedure Grab(const AName: string; AImage: TLazIntfImage;
      AIndex: integer; var ACancel: boolean);
    { Allocates a TMemoryStream to receive the decompressed entry data. }
    procedure DoCreateStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
    { Decodes the just-decompressed entry into Grab.  Frees the stream. }
    procedure DoDoneStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
  public
    constructor Create(AMaxW, AMaxH: integer);
  end;

  { TEntryImageGrabber – keeps only the image decoded from the entry whose
    name exactly matches FEntryName, frees every other decoded image, and
    signals cancellation once it was found.  Used with a selective
    UnZipFiles pass so only the target entry is decompressed. }

  TEntryImageGrabber = class
  private
    FEntryName: string;
    FImage: TLazIntfImage;
    procedure Grab(const AName: string; AImage: TLazIntfImage;
      AIndex: integer; var ACancel: boolean);
    procedure DoCreateStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
    procedure DoDoneStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
  public
    constructor Create(const AEntryName: string);
  end;

function DecodeImage(Stream: TMemoryStream; const Ext: string;
  MaxW: integer = 0; MaxH: integer = 0): TLazIntfImage;
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
      Result := StreamToIntfImage(Stream, ReaderClassForExt(FmtExt), MaxW, MaxH);
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
  { By providing the stream ourselves, TUnZipper creates no destination file. }
  AStream := TMemoryStream.Create;
end;

{ Binary search for S in a CompareStr-sorted list.  Returns the rank or -1. }
function SortedRank(List: TStringList; const S: string): integer;
var
  L, R, M, C: integer;
begin
  L := 0;
  R := List.Count - 1;
  while L <= R do
  begin
    M := (L + R) div 2;
    C := CompareStr(S, List[M]);
    if C = 0 then Exit(M);
    if C > 0 then
      L := M + 1
    else
      R := M - 1;
  end;
  Result := -1;
end;

{ Compare two list entries byte-wise (Python sorted() order), independent of
  the locale collation used by TStringList.Sort. }
function CompareNames(List: TStringList; Index1, Index2: integer): integer;
begin
  Result := CompareStr(List[Index1], List[Index2]);
end;

procedure TZipImageWalker.DoDoneStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
var
  Img: TLazIntfImage;
  Ext: string;
  Idx: integer;
begin
  { With OnCreateStream assigned, freeing the stream is up to us. }
  try
    if FCancel or AItem.IsDirectory then Exit;
    Ext := ExtractFileExt(AItem.ArchiveFileName);
    if not IsImageExt(Ext) then Exit;

    AStream.Position := 0;
    Img := DecodeImage(TMemoryStream(AStream), Ext, FMaxW, FMaxH);
    if Img = nil then
      Log('Zip: null decode for %s', [AItem.ArchiveFileName]);
    FCallback(AItem.ArchiveFileName, Img, SortedRank(FSortedNames,
      AItem.ArchiveFileName), FCancel);
    if FCancel then
      FZip.Terminate;
  finally
    AStream.Free;
    AStream := nil;
  end;
end;

procedure TZipImageWalker.Run(const FileName: string; ACallback: TImageEntryProc;
  AMaxW: integer; AMaxH: integer);
var
  i: integer;
begin
  FCallback := ACallback;
  FCancel := False;
  FMaxW := AMaxW;
  FMaxH := AMaxH;
  FZip := TUnZipper.Create;
  FSortedNames := TStringList.Create;
  try
    FZip.OnCreateStream := @DoCreateStream;
    FZip.OnDoneStream := @DoDoneStream;
    FZip.FileName := FileName;
    { Read the central directory once and collect the image entry names so
      every page can be tagged with its alphabetical rank.  Extraction then
      stays a single decompression pass in archive order; consumers use the
      rank to display pages in sorted order (Python reference semantics). }
    FZip.Examine;
    for i := 0 to FZip.Entries.Count - 1 do
      if not FZip.Entries[i].IsDirectory and
        IsImageExt(ExtractFileExt(FZip.Entries[i].ArchiveFileName)) then
        FSortedNames.Add(FZip.Entries[i].ArchiveFileName);
    FSortedNames.CustomSort(@CompareNames);
    FZip.UnZipAllFiles;
  finally
    FSortedNames.Free;
    FreeAndNil(FZip);
  end;
end;

{ TFirstImageGrabber }

constructor TFirstImageGrabber.Create(AMaxW, AMaxH: integer);
begin
  FMaxW := AMaxW;
  FMaxH := AMaxH;
end;

procedure TFirstImageGrabber.DoCreateStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
begin
  AStream := TMemoryStream.Create;
end;

procedure TFirstImageGrabber.DoDoneStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
var
  Img: TLazIntfImage;
  Ext: string;
  Cancel: boolean;
begin
  try
    if AItem.IsDirectory then Exit;
    Ext := ExtractFileExt(AItem.ArchiveFileName);
    if not IsImageExt(Ext) then Exit;
    AStream.Position := 0;
    Img := DecodeImage(TMemoryStream(AStream), Ext, FMaxW, FMaxH);
    Cancel := False;
    Grab(AItem.ArchiveFileName, Img, -1, Cancel);
  finally
    AStream.Free;
    AStream := nil;
  end;
end;

procedure TFirstImageGrabber.Grab(const AName: string; AImage: TLazIntfImage;
  AIndex: integer; var ACancel: boolean);
begin
  if FImage = nil then
    FImage := AImage
  else
    AImage.Free;
  ACancel := True;
end;

{ TEntryImageGrabber }

constructor TEntryImageGrabber.Create(const AEntryName: string);
begin
  FEntryName := AEntryName;
end;

procedure TEntryImageGrabber.DoCreateStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
begin
  AStream := TMemoryStream.Create;
end;

procedure TEntryImageGrabber.DoDoneStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
var
  Img: TLazIntfImage;
  Ext: string;
  Cancel: boolean;
begin
  try
    if AItem.IsDirectory then Exit;
    Ext := ExtractFileExt(AItem.ArchiveFileName);
    if not IsImageExt(Ext) then Exit;
    AStream.Position := 0;
    Img := DecodeImage(TMemoryStream(AStream), Ext);
    Cancel := False;
    Grab(AItem.ArchiveFileName, Img, -1, Cancel);
  finally
    AStream.Free;
    AStream := nil;
  end;
end;

procedure TEntryImageGrabber.Grab(const AName: string; AImage: TLazIntfImage;
  AIndex: integer; var ACancel: boolean);
begin
  if (FImage = nil) and (CompareStr(AName, FEntryName) = 0) then
    FImage := AImage
  else
    AImage.Free;
  ACancel := FImage <> nil;
end;

procedure ForEachImage(const FileName: string; ACallback: TImageEntryProc;
  AMaxW: integer; AMaxH: integer);
var
  Walker: TZipImageWalker;
begin
  Walker := TZipImageWalker.Create;
  try
    Walker.Run(FileName, ACallback, AMaxW, AMaxH);
  finally
    Walker.Free;
  end;
end;

{ Single ZIP pass: reads the central directory once, scans it for
  ComicInfo.xml and the first image entry by alphabetical name order, then
  decompresses only that one entry.  Saves a second file open +
  central-directory parse per thumbnail compared to
  GetFirstImageAsIntfImage + HasComicInfoFast. }
function GetFirstImageInfo(const FileName: string; out AImage: TLazIntfImage;
  out AHasComicInfo: boolean; AMaxW, AMaxH: integer): boolean;
var
  UnZipper: TUnZipper;
  Grabber: TFirstImageGrabber;
  Files: TStringList;
  i, FirstIdx: integer;
  FirstName: string;
begin
  AImage := nil;
  AHasComicInfo := False;
  Result := False;
  Grabber := TFirstImageGrabber.Create(AMaxW, AMaxH);
  UnZipper := TUnZipper.Create;
  Files := TStringList.Create;
  try
    UnZipper.OnCreateStream := @Grabber.DoCreateStream;
    UnZipper.OnDoneStream := @Grabber.DoDoneStream;
    UnZipper.FileName := FileName;
    UnZipper.Examine;
    { The thumbnail must match page 0 of the preview (sorted entry names):
      some archives store pages in a scrambled order. }
    FirstIdx := -1;
    FirstName := '';
    for i := 0 to UnZipper.Entries.Count - 1 do
    begin
      if UnZipper.Entries[i].IsDirectory then Continue;
      if SameText(UnZipper.Entries[i].ArchiveFileName, COMICINFO_XML) then
      begin
        AHasComicInfo := True;
        Continue;
      end;
      if IsImageExt(ExtractFileExt(UnZipper.Entries[i].ArchiveFileName)) and
        ((FirstIdx < 0) or
        (CompareStr(UnZipper.Entries[i].ArchiveFileName, FirstName) < 0)) then
      begin
        FirstIdx := i;
        FirstName := UnZipper.Entries[i].ArchiveFileName;
      end;
    end;
    if FirstIdx >= 0 then
    begin
      { UnZipFiles extracts only the entries whose ArchiveFileName is in
        the list — one entry, one decompression pass. }
      Files.Add(UnZipper.Entries[FirstIdx].ArchiveFileName);
      UnZipper.UnZipFiles(Files);
      AImage := Grabber.FImage;
      Grabber.FImage := nil;
      Result := AImage <> nil;
    end;
  finally
    Files.Free;
    UnZipper.Free;
    Grabber.Free;
  end;
end;

function GetFirstImageAsIntfImage(const FileName: string): TLazIntfImage;
var
  HasComicInfo: boolean;
begin
  GetFirstImageInfo(FileName, Result, HasComicInfo, 0, 0);
  if Result = nil then
    Log('GetFirstImage: no image in %s', [ExtractFileName(FileName)])
  else
    Log('GetFirstImage: %s -> %dx%d',
      [ExtractFileName(FileName), Result.Width, Result.Height]);
end;

{ Targeted extraction: reads the central directory, looks up the exact
  entry name, and decompresses only that one entry at full resolution. }
function GetImageAsIntfImage(const FileName, EntryName: string): TLazIntfImage;
var
  UnZipper: TUnZipper;
  Grabber: TEntryImageGrabber;
  Files: TStringList;
  i: integer;
  Found: boolean;
begin
  Result := nil;
  Grabber := TEntryImageGrabber.Create(EntryName);
  UnZipper := TUnZipper.Create;
  Files := TStringList.Create;
  try
    UnZipper.OnCreateStream := @Grabber.DoCreateStream;
    UnZipper.OnDoneStream := @Grabber.DoDoneStream;
    UnZipper.FileName := FileName;
    UnZipper.Examine;
    Found := False;
    for i := 0 to UnZipper.Entries.Count - 1 do
      if not UnZipper.Entries[i].IsDirectory and
        (CompareStr(UnZipper.Entries[i].ArchiveFileName, EntryName) = 0) then
      begin
        Found := True;
        Break;
      end;
    if Found then
    begin
      { UnZipFiles extracts only the listed entries — one decompression pass. }
      Files.Add(EntryName);
      UnZipper.UnZipFiles(Files);
      Result := Grabber.FImage;
      Grabber.FImage := nil;
    end;
  finally
    Files.Free;
    UnZipper.Free;
    Grabber.Free;
  end;
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

{ Shared state of a validation pool: the source entries, per-source-index
  check slots and the claim counter.  Mutable fields are guarded by Lock;
  each worker writes only Checks[Idx] with the Idx it claimed, so slot
  writes need no lock. }
type
  TValidatePoolState = class
  Lock: TRTLCriticalSection;
  Entries: TZipEntries;        { read-only source data }
  Checks: TImageChecks;        { per-source-index results }
  Work: array of integer;      { indices of image entries }
  Next: integer;               { next index into Work (under Lock) }
  Completed: integer;          { finished entries (under Lock) }
  BaseName: string;            { ExtractFileName(FileName), for messages }
  OnProgress: TServiceProgressEvent;
  constructor Create;
  destructor Destroy; override;
end;

{ Pool worker: claims the next image-entry index under the lock, decodes
  it and writes the TImageCheck into its own slot.  DecodeImage is
  stateless per call and never raises (failures become Valid=False
  checks), so workers share nothing but the pool fields. }
TValidateWorker = class(TThread)
private
  FPool: TValidatePoolState;
protected
  procedure Execute; override;
public
  constructor Create(APool: TValidatePoolState);
end;

constructor TValidatePoolState.Create;
begin
  inherited Create;
  InitCriticalSection(Lock);
end;

destructor TValidatePoolState.Destroy;
begin
  DoneCriticalSection(Lock);
  inherited Destroy;
end;

constructor TValidateWorker.Create(APool: TValidatePoolState);
begin
  { Created suspended: the caller Start()s every worker before joining. }
  inherited Create(True);
  FPool := APool;
end;

{ TValidateWorker.Execute

  Claims the next image-entry index under the pool lock, decodes the entry
  (DecodeImage never raises — a failed decode is a Valid=False check) and
  writes the result into its own slot.  Progress is reported per finished
  entry, serialized by the lock, monotonic via the completed counter. }
procedure TValidateWorker.Execute;
var
  Idx: integer;
  Img: TLazIntfImage;
begin
  while True do
  begin
    EnterCriticalSection(FPool.Lock);
    try
      if FPool.Next >= Length(FPool.Work) then Exit;
      Idx := FPool.Work[FPool.Next];
      Inc(FPool.Next);
    finally
      LeaveCriticalSection(FPool.Lock);
    end;

    FPool.Checks[Idx].EntryName := FPool.Entries[Idx].Name;
    Img := DecodeImage(FPool.Entries[Idx].Data,
      ExtractFileExt(FPool.Entries[Idx].Name));
    FPool.Checks[Idx].Valid := Img <> nil;
    if Img <> nil then
    begin
      FPool.Checks[Idx].ErrorMsg := '';
      Img.Free;
    end
    else
      FPool.Checks[Idx].ErrorMsg := 'Image decode failed';

    EnterCriticalSection(FPool.Lock);
    try
      Inc(FPool.Completed);
      if Assigned(FPool.OnProgress) then
        FPool.OnProgress((FPool.Completed * 100) div Length(FPool.Work),
          Format('%s — entry %d/%d (%s)', [FPool.BaseName, Idx + 1,
            Length(FPool.Entries), FPool.Entries[Idx].Name]));
    finally
      LeaveCriticalSection(FPool.Lock);
    end;
  end;
end;

function ValidateCBZImages(const FileName: string;
  out ImageResults: TImageChecks; AThreads: integer = 0): integer;
var
  AllEntries: TZipEntries;
  i, j, Idx, Count, ValidCount, ThreadCount: integer;
  Img: TLazIntfImage;
  Pool: TValidatePoolState;
  Checks: TImageChecks;
  Workers: array of TValidateWorker;
  Started: boolean;
begin
  ImageResults := nil;
  Result := 0;
  try
    AllEntries := CollectZipEntries(FileName);
  except
    on E: Exception do
    begin
      { File-level error: return it as a single pseudo-entry }
      SetLength(ImageResults, 1);
      ImageResults[0].EntryName := ExtractFileName(FileName);
      ImageResults[0].Valid := False;
      ImageResults[0].ErrorMsg := E.Message;
      Exit;
    end;
  end;

  try
    if Length(AllEntries) = 0 then
    begin
      { Empty archive: report a single invalid pseudo-entry (parity with
        the historical streaming walker, which raised on empty zips). }
      SetLength(ImageResults, 1);
      ImageResults[0].EntryName := ExtractFileName(FileName);
      ImageResults[0].Valid := False;
      ImageResults[0].ErrorMsg := 'No images found';
      Exit;
    end;

    { Phase 1 — decode every image entry into its slot, in parallel. }
    Pool := TValidatePoolState.Create;
    Workers := nil;
    Started := False;
    try
      Pool.Entries := AllEntries;
      Pool.BaseName := ExtractFileName(FileName);
      for i := 0 to High(AllEntries) do
        if IsImageExt(ExtractFileExt(AllEntries[i].Name)) then
        begin
          SetLength(Pool.Work, Length(Pool.Work) + 1);
          Pool.Work[High(Pool.Work)] := i;
        end;

      { Allocate the slots up front — phase 2 indexes them by source entry
        even when no entry is an image. }
      SetLength(Pool.Checks, Length(AllEntries));
      if Length(Pool.Work) > 0 then
      begin
        ThreadCount := AThreads;
        if ThreadCount <= 0 then
          ThreadCount := Min(OnlineCpuCount, MAX_WEBP_CONVERT_THREADS);
        ThreadCount := Min(ThreadCount, Length(Pool.Work));

        if ThreadCount > 1 then
        begin
          SetLength(Workers, ThreadCount);
          for i := 0 to ThreadCount - 1 do
            Workers[i] := TValidateWorker.Create(Pool);
          Started := True;
          for i := 0 to ThreadCount - 1 do
            Workers[i].Start;
        end
        else
        begin
          { Single entry (or explicitly sequential): claim and decode
            inline — same slot semantics as the pool path. }
          while Pool.Next < Length(Pool.Work) do
          begin
            Idx := Pool.Work[Pool.Next];
            Inc(Pool.Next);
            Pool.Checks[Idx].EntryName := AllEntries[Idx].Name;
            Img := DecodeImage(AllEntries[Idx].Data,
              ExtractFileExt(AllEntries[Idx].Name));
            Pool.Checks[Idx].Valid := Img <> nil;
            if Img <> nil then
            begin
              Pool.Checks[Idx].ErrorMsg := '';
              Img.Free;
            end
            else
              Pool.Checks[Idx].ErrorMsg := 'Image decode failed';
            Inc(Pool.Completed);
            if Assigned(Pool.OnProgress) then
              Pool.OnProgress((Pool.Completed * 100) div Length(Pool.Work),
                Format('%s — entry %d/%d (%s)', [Pool.BaseName, Idx + 1,
                  Length(AllEntries), AllEntries[Idx].Name]));
          end;
        end;
      end;
    finally
      { Join and free the workers here — also covers a mid-spawn failure,
        where only the created (started) workers must be waited for. }
      if Started then
        for i := 0 to High(Workers) do
          Workers[i].WaitFor;
      for i := 0 to High(Workers) do
        if Workers[i] <> nil then
          Workers[i].Free;
      { Keep a refcounted reference to the check slots: phase 2 reads them
        after the pool object itself is freed. }
      Checks := Pool.Checks;
      Pool.Free;
    end;

    { Phase 2 — assemble the per-entry checks in archive order
      (deterministic regardless of the thread count). }
    Count := 0;
    for i := 0 to High(AllEntries) do
      if Checks[i].EntryName <> '' then Inc(Count);
    SetLength(ImageResults, Count);
    j := 0;
    ValidCount := 0;
    for i := 0 to High(AllEntries) do
      if Checks[i].EntryName <> '' then
      begin
        ImageResults[j] := Checks[i];
        if ImageResults[j].Valid then Inc(ValidCount);
        Inc(j);
      end;
    Result := ValidCount;
  finally
    FreeZipEntries(AllEntries);
  end;
end;

{ Returns True when Ext belongs to a raster format that can be re-encoded
  as WebP (JPEG, PNG, GIF, BMP, TIFF).  Extensions already matching .webp
  are NOT convertible – they are already in the target format. }
function IsConvertibleExt(const Ext: string): boolean;
begin
  Result := ExtInList(Ext, CONVERTIBLE_EXTS);
end;

{ Decode + WebP-encode a single entry's data.  Returns the WebP stream, or
  nil when the decode or the encode fails (the caller then keeps the
  original entry).  Stateless per call — DecodeImage and IntfImageToWebP
  keep no shared mutable state, so pool workers can run it concurrently. }
function EncodeEntryAsWebP(const Source: TZipEntryData; const Ext: string;
  Quality: integer): TMemoryStream;
var
  RawStream: TMemoryStream;
  Img: TLazIntfImage;
begin
  Result := nil;
  RawStream := TMemoryStream.Create;
  try
    Source.Data.Position := 0;
    RawStream.CopyFrom(Source.Data, Source.Data.Size);
    RawStream.Position := 0;
    { Reuse the shared decoder (magic-byte detection + reader selection +
      logging) instead of duplicating it here. }
    Img := DecodeImage(RawStream, Ext);
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

constructor TConvertPoolState.Create;
begin
  inherited Create;
  InitCriticalSection(Lock);
end;

destructor TConvertPoolState.Destroy;
begin
  DoneCriticalSection(Lock);
  inherited Destroy;
end;

constructor TWebPConvertWorker.Create(APool: TConvertPoolState);
begin
  { Created suspended: the caller Start()s every worker before joining. }
  inherited Create(True);
  FPool := APool;
end;

{ TWebPConvertWorker.Execute

  Claims the next convertible entry index under the pool lock, then
  decodes + WebP-encodes it into its own slot (each index is claimed
  exactly once, so the slot write needs no lock).  Progress is reported
  per finished job, serialized by the lock — the callback may itself
  block (e.g. TServiceThread.Progress uses a blocking Synchronize), so it
  must never be entered concurrently.  The reported percentage derives
  from the completed-job counter, which makes the sequence monotonic even
  though jobs finish out of order.

  When any job raises, the first error is recorded and every worker stops
  claiming new work: the file fails as a whole, mirroring the sequential
  path's exception propagation. }
procedure TWebPConvertWorker.Execute;
var
  Idx: integer;
  Stream: TMemoryStream;
begin
  while True do
  begin
    EnterCriticalSection(FPool.Lock);
    try
      if FPool.Error <> '' then Exit;
      if FPool.Next >= Length(FPool.Work) then Exit;
      Idx := FPool.Work[FPool.Next];
      Inc(FPool.Next);
    finally
      LeaveCriticalSection(FPool.Lock);
    end;

    try
      Stream := EncodeEntryAsWebP(FPool.Entries[Idx],
        ExtractFileExt(FPool.Entries[Idx].Name), FPool.Quality);
      FPool.Slots[Idx].Data := Stream;
    except
      on E: Exception do
      begin
        EnterCriticalSection(FPool.Lock);
        try
          if FPool.Error = '' then
            FPool.Error := Format('%s: %s', [FPool.Entries[Idx].Name, E.Message]);
        finally
          LeaveCriticalSection(FPool.Lock);
        end;
        Exit;
      end;
    end;

    EnterCriticalSection(FPool.Lock);
    try
      Inc(FPool.Completed);
      if Assigned(FPool.OnProgress) then
        FPool.OnProgress((FPool.Completed * 100) div Length(FPool.Work),
          Format('%s — entry %d/%d (%s)', [FPool.BaseName, Idx + 1,
            Length(FPool.Entries), FPool.Entries[Idx].Name]));
    finally
      LeaveCriticalSection(FPool.Lock);
    end;
  end;
end;

function ConvertCBZToWebP(const FileName: string; Quality: integer;
  ReplaceOnlyIfSmaller, SkipExistingWebP, RemoveComicInfo, RenumberPages: boolean;
  out NewEntryCount: integer; out AConvertedCount: integer;
  out AModified: boolean; AOnProgress: TServiceProgressEvent = nil;
  AThreads: integer = 0): TZipEntries;

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

var
  AllEntries: TZipEntries;
  i, PageNum, WorkCount, ThreadCount: integer;
  Ext, BaseName: string;
  WebPData: TMemoryStream;
  Pool: TConvertPoolState;
  Slots: TConvertSlots;
  Workers: array of TWebPConvertWorker;
  Started: boolean;
begin
  Result := nil;
  NewEntryCount := 0;
  AConvertedCount := 0;
  AModified := False;
  AllEntries := CollectZipEntries(FileName);
  if Length(AllEntries) = 0 then Exit;

  try
    { Phase 1 — decode + WebP-encode every convertible entry into its slot.
      Convertible means: a known raster format, or an existing .webp that
      must be re-encoded because SkipExistingWebP is off. }
    Pool := TConvertPoolState.Create;
    Workers := nil;
    Started := False;
    try
      Pool.Entries := AllEntries;
      Pool.Quality := Quality;
      Pool.OnProgress := AOnProgress;
      Pool.BaseName := ExtractFileName(FileName);
      BaseName := Pool.BaseName;
      Slots := nil;
      for i := 0 to High(AllEntries) do
      begin
        Ext := ExtractFileExt(AllEntries[i].Name);
        if SameText(Ext, EXT_WEBP) then
        begin
          if not SkipExistingWebP then
          begin
            SetLength(Pool.Work, Length(Pool.Work) + 1);
            Pool.Work[High(Pool.Work)] := i;
          end;
        end
        else if IsConvertibleExt(Ext) then
        begin
          SetLength(Pool.Work, Length(Pool.Work) + 1);
          Pool.Work[High(Pool.Work)] := i;
        end;
      end;

      WorkCount := Length(Pool.Work);
      if WorkCount > 0 then
      begin
        SetLength(Pool.Slots, Length(AllEntries));
        ThreadCount := AThreads;
        if ThreadCount <= 0 then
          ThreadCount := Min(OnlineCpuCount, MAX_WEBP_CONVERT_THREADS);
        ThreadCount := Min(ThreadCount, WorkCount);

        if ThreadCount > 1 then
        begin
          SetLength(Workers, ThreadCount);
          for i := 0 to ThreadCount - 1 do
            Workers[i] := TWebPConvertWorker.Create(Pool);
          Started := True;
          for i := 0 to ThreadCount - 1 do
            Workers[i].Start;
        end
        else
        begin
          { Single job (or explicitly sequential): claim and encode inline.
            Same slot semantics and progress shape as the pool path, no
            thread creation. }
          while Pool.Next < Length(Pool.Work) do
          begin
            i := Pool.Work[Pool.Next];
            Inc(Pool.Next);
            try
              Pool.Slots[i].Data := EncodeEntryAsWebP(AllEntries[i],
                ExtractFileExt(AllEntries[i].Name), Quality);
            except
              on E: Exception do
                Pool.Error := Format('%s: %s', [AllEntries[i].Name, E.Message]);
            end;
            if Pool.Error <> '' then Break;
            Inc(Pool.Completed);
            if Assigned(AOnProgress) then
              AOnProgress((Pool.Completed * 100) div WorkCount,
                Format('%s — entry %d/%d (%s)', [Pool.BaseName, i + 1,
                  Length(AllEntries), AllEntries[i].Name]));
          end;
        end;
      end;

      { A worker failure fails the whole file, exactly like the sequential
        path's exception propagation.  Free the already-encoded streams
        before raising. }
      if Pool.Error <> '' then
      begin
        for i := 0 to High(Pool.Slots) do
          FreeAndNil(Pool.Slots[i].Data);
        raise Exception.Create(Pool.Error);
      end;
    finally
      { Join and free the workers here — also covers a mid-spawn failure,
        where only the created (started) workers must be waited for. }
      if Started then
        for i := 0 to High(Workers) do
          Workers[i].WaitFor;
      for i := 0 to High(Workers) do
        if Workers[i] <> nil then
          Workers[i].Free;
      { Keep a refcounted reference to the slot array: phase 2 reads the
        encoded streams after the pool object itself is freed. }
      Slots := Pool.Slots;
      Pool.Free;
    end;

    { Phase 2 — sequential compaction and naming.  Deterministic: slots are
      read in archive order, so the output is byte-identical regardless of
      the thread count.  Progress for the cheap branches (ComicInfo, skips,
      non-convertible formats) is reported here; convertible entries were
      already reported by phase 1, so every entry ticks exactly once. }
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
          if Assigned(AOnProgress) then
            AOnProgress((i * 100) div Length(AllEntries),
              Format('%s — entry %d/%d (%s)',
                [BaseName, i + 1, Length(AllEntries),
                 AllEntries[i].Name]));
          FreeAndNil(AllEntries[i].Data);
          Continue;
        end;

        { --- Existing .webp: keep as-is when skipping, otherwise the slot
              holds the re-encoded stream. --- }
        if SameText(Ext, EXT_WEBP) then
        begin
          if SkipExistingWebP then
          begin
            KeepOriginal(Result, PageNum, AllEntries[i], Ext);
            if Assigned(AOnProgress) then
              AOnProgress((i * 100) div Length(AllEntries),
                Format('%s — entry %d/%d (%s)',
                  [BaseName, i + 1, Length(AllEntries),
                   AllEntries[i].Name]));
            FreeAndNil(AllEntries[i].Data);
            Continue;
          end;
        end
        { --- Other non-convertible formats: always keep as-is --- }
        else if not IsConvertibleExt(Ext) then
        begin
          KeepOriginal(Result, PageNum, AllEntries[i], Ext);
          if Assigned(AOnProgress) then
            AOnProgress((i * 100) div Length(AllEntries),
              Format('%s — entry %d/%d (%s)',
                [BaseName, i + 1, Length(AllEntries),
                 AllEntries[i].Name]));
          FreeAndNil(AllEntries[i].Data);
          Continue;
        end;

        { --- Use the phase-1 result --- }
        WebPData := Slots[i].Data;
        Slots[i].Data := nil;

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
      { Free the streams still waiting in their slots: consumed ones were
        either adopted into Result (freed below) or already freed. }
      for i := 0 to High(Slots) do
        FreeAndNil(Slots[i].Data);
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
  i, j, k, PageNum, Padding: integer;
  SrcPath, Ext: string;
  Entries: TZipEntries;
  Key: TZipEntryData;
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
        { Sort entries by name (ordinal, case-sensitive) before filtering,
          matching the Python reference's sorted(namelist()): the archive's
          internal storage order must not decide page order.  Insertion
          sort is stable — equal names keep archive order. }
        for j := 1 to High(Entries) do
        begin
          Key := Entries[j];
          k := j - 1;
          while (k >= 0) and (CompareStr(Entries[k].Name, Key.Name) > 0) do
          begin
            Entries[k + 1] := Entries[k];
            Dec(k);
          end;
          Entries[k + 1] := Key;
        end;

        for j := 0 to High(Entries) do
        begin
          if SameText(Entries[j].Name, COMICINFO_XML) then
            Continue;
          { Skip non-image entries (credits.txt, .nfo, Thumbs.db, …) so they
            are not renumbered into the page sequence — mirrors the filter in
            ConvertCBZToWebP and FilterPagesFromCBZ. }
          Ext := LowerCase(ExtractFileExt(Entries[j].Name));
          if not IsImageExt(Ext) then Continue;
          SetLength(Result, PageNum + 1);
          Result[PageNum].Name := Ext;  { temp carrier; renamed below }
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

{ ---------------------------------------------------------------------------
  CBR (RAR) support — implemented on top of uarchive's TCbrReader.
  --------------------------------------------------------------------------- }

type
  { TUnRarWalker – streams a CBR entry by entry through a callback via
    libarchive.  RAR has no central directory, so Run scans the archive
    twice: once collecting the image entry names (data skipped) so every
    entry can be tagged with its alphabetical rank, then again decoding
    the pages.  Data always lands in memory streams — no temp files. }

  TUnRarWalker = class
  private
    FCallback: TImageEntryProc;
    FCancel: boolean;
    FMaxW: integer;
    FMaxH: integer;
    FSortedNames: TStringList;
    { Decodes the current entry (already positioned by the reader) and
      passes it to the callback with its alphabetical rank. }
    procedure HandleEntry(AR: TCbrReader; const AInfo: TCbrEntryInfo);
  public
    procedure Run(const FileName: string; ACallback: TImageEntryProc;
      AMaxW: integer = 0; AMaxH: integer = 0);
  end;

{ Raises with the reader's last error message. }
procedure CbrReadError(AR: TCbrReader);
begin
  if AR.Error <> '' then
    raise Exception.Create('CBR: ' + AR.Error)
  else
    raise Exception.Create('CBR: unreadable archive');
end;

procedure TUnRarWalker.HandleEntry(AR: TCbrReader; const AInfo: TCbrEntryInfo);
var
  Data: TMemoryStream;
  Img: TLazIntfImage;
  Rank: integer;
begin
  if FCancel or AInfo.IsDirectory then Exit;
  if not IsImageExt(ExtractFileExt(AInfo.Name)) then Exit;

  Data := TMemoryStream.Create;
  try
    if not AR.ReadData(Data) then
      CbrReadError(AR);
    Data.Position := 0;
    Img := DecodeImage(Data, ExtractFileExt(AInfo.Name), FMaxW, FMaxH);
  finally
    Data.Free;
  end;
  Rank := SortedRank(FSortedNames, AInfo.Name);
  FCallback(AInfo.Name, Img, Rank, FCancel);
end;

procedure TUnRarWalker.Run(const FileName: string; ACallback: TImageEntryProc;
  AMaxW: integer; AMaxH: integer);
var
  Reader: TCbrReader;
  Info: TCbrEntryInfo;
begin
  FCallback := ACallback;
  FCancel := False;
  FMaxW := AMaxW;
  FMaxH := AMaxH;
  FSortedNames := TStringList.Create;
  Reader := TCbrReader.Create(FileName);
  try
    if Reader.Error <> '' then
      CbrReadError(Reader);

    { Pass 1: collect the image entry names (data skipped) so every page
      can be tagged with its alphabetical rank later. }
    while Reader.NextEntry(Info) do
    begin
      if Info.IsDirectory then Continue;   { directories carry no data }
      if IsImageExt(ExtractFileExt(Info.Name)) then
        FSortedNames.Add(Info.Name);
      if not Reader.SkipData then
        CbrReadError(Reader);
    end;
    if Reader.Error <> '' then
      CbrReadError(Reader);
    FSortedNames.CustomSort(@CompareNames);

    { Pass 2: decode every image entry in reading order. }
    Reader.Free;
    Reader := TCbrReader.Create(FileName);
    if Reader.Error <> '' then
      CbrReadError(Reader);
    while not FCancel and Reader.NextEntry(Info) do
    begin
      if Info.IsDirectory then Continue;
      if IsImageExt(ExtractFileExt(Info.Name)) then
        HandleEntry(Reader, Info)
      else if not Reader.SkipData then
        CbrReadError(Reader);
    end;
  finally
    Reader.Free;
    FSortedNames.Free;
  end;
end;

procedure ForEachCbrImage(const FileName: string; ACallback: TImageEntryProc;
  AMaxW: integer; AMaxH: integer);
var
  Walker: TUnRarWalker;
begin
  Walker := TUnRarWalker.Create;
  try
    Walker.Run(FileName, ACallback, AMaxW, AMaxH);
  finally
    Walker.Free;
  end;
end;

function CollectCbrEntries(const FileName: string;
  AOnProgress: TServiceProgressEvent): TZipEntries;
var
  Reader: TCbrReader;
  Info: TCbrEntryInfo;
  Data: TMemoryStream;
  Count, Total: integer;
begin
  Result := nil;
  Count := 0;
  Reader := TCbrReader.Create(FileName);
  try
    if Reader.Error <> '' then
      CbrReadError(Reader);

    { RAR has no central directory: a fast counting pass (data skipped)
      gives the total entry count so the read pass can report meaningful
      percentages. }
    if Assigned(AOnProgress) then
    begin
      Total := 0;
      while Reader.NextEntry(Info) do
      begin
        if Info.IsDirectory then Continue;
        Inc(Total);
        if not Reader.SkipData then
          CbrReadError(Reader);
      end;
      if Reader.Error <> '' then
        CbrReadError(Reader);
      Reader.Free;
      Reader := TCbrReader.Create(FileName);
      if Reader.Error <> '' then
        CbrReadError(Reader);
    end
    else
      Total := 0;

    while Reader.NextEntry(Info) do
    begin
      if Info.IsDirectory then Continue;
      if Assigned(AOnProgress) then
        AOnProgress((Count * 100) div Max(1, Total),
          Format('%s — entry %d/%d (%s)',
            [ExtractFileName(FileName), Count + 1, Total, Info.Name]));
      Data := TMemoryStream.Create;
      try
        if not Reader.ReadData(Data) then
          CbrReadError(Reader);
        { Ownership of Data transfers into the result array. }
        SetLength(Result, Count + 1);
        Result[Count].Name := Info.Name;
        Result[Count].Data := Data;
        Data := nil;
        Inc(Count);
      finally
        Data.Free;   { no-op when ownership was transferred }
      end;
    end;
    if Reader.Error <> '' then
    begin
      FreeZipEntries(Result);
      CbrReadError(Reader);
    end;
  finally
    Reader.Free;
  end;
end;

function GetCbrImageAsIntfImage(const FileName, EntryName: string): TLazIntfImage;
var
  Reader: TCbrReader;
  Info: TCbrEntryInfo;
  Data: TMemoryStream;
begin
  Result := nil;
  Reader := TCbrReader.Create(FileName);
  try
    if Reader.Error <> '' then Exit;
    while Reader.NextEntry(Info) do
    begin
      if Info.IsDirectory then Continue;
      if CompareStr(Info.Name, EntryName) = 0 then
      begin
        Data := TMemoryStream.Create;
        try
          if Reader.ReadData(Data) then
          begin
            Data.Position := 0;
            Result := DecodeImage(Data, ExtractFileExt(Info.Name));
          end;
        finally
          Data.Free;
        end;
        Exit;
      end;
      if not Reader.SkipData then Break;
    end;
  finally
    Reader.Free;
  end;
end;

function GetCbrFirstImageInfo(const FileName: string; out AImage: TLazIntfImage;
  out AHasComicInfo: boolean; AMaxW, AMaxH: integer): boolean;
var
  Reader: TCbrReader;
  Info: TCbrEntryInfo;
  Names: TStringList;
  FirstName: string;
  Data: TMemoryStream;
begin
  AImage := nil;
  AHasComicInfo := False;
  Result := False;
  Names := TStringList.Create;
  Reader := TCbrReader.Create(FileName);
  try
    if Reader.Error <> '' then Exit;   { degraded: treated as no thumbnail }
    { Pass 1: collect image names (for the alphabetical first page) and
      the ComicInfo.xml presence (thumbnail badge). }
    while Reader.NextEntry(Info) do
    begin
      if Info.IsDirectory then Continue;
      if SameText(Info.Name, COMICINFO_XML) then
      begin
        AHasComicInfo := True;
        if not Reader.SkipData then Exit;
        Continue;
      end;
      if IsImageExt(ExtractFileExt(Info.Name)) then
        Names.Add(Info.Name);
      if not Reader.SkipData then Exit;
    end;
    if (Reader.Error <> '') or (Names.Count = 0) then Exit;
    Names.CustomSort(@CompareNames);
    FirstName := Names[0];

    { Pass 2: decode only the alphabetically first page. }
    Reader.Free;
    Reader := TCbrReader.Create(FileName);
    if Reader.Error <> '' then Exit;
    while Reader.NextEntry(Info) do
    begin
      if Info.IsDirectory then Continue;
      if CompareStr(Info.Name, FirstName) = 0 then
      begin
        Data := TMemoryStream.Create;
        try
          if Reader.ReadData(Data) then
          begin
            Data.Position := 0;
            AImage := DecodeImage(Data, ExtractFileExt(Info.Name), AMaxW, AMaxH);
            Result := AImage <> nil;
          end;
        finally
          Data.Free;
        end;
        Break;
      end;
      if not Reader.SkipData then Break;
    end;
  finally
    Reader.Free;
    Names.Free;
  end;
end;

function ConvertCbrToCbz(const SourceFile: string;
  AOnProgress: TServiceProgressEvent): TZipEntries;
var
  All: TZipEntries;
  i, PageNum, Padding: integer;
  Ext: string;
begin
  Result := nil;
  All := CollectCbrEntries(SourceFile, AOnProgress);
  try
    try
      PageNum := 0;
      SetLength(Result, Length(All));
      for i := 0 to High(All) do
      begin
        { House policy (same as the WebP conversion): strip ComicInfo.xml
          and non-image entries, renumber the survivors page_NNNN.*. }
        if SameText(All[i].Name, COMICINFO_XML) then
        begin
          FreeAndNil(All[i].Data);
          Continue;
        end;
        Ext := LowerCase(ExtractFileExt(All[i].Name));
        if not IsImageExt(Ext) then
        begin
          FreeAndNil(All[i].Data);
          Continue;
        end;
        Result[PageNum].Data := All[i].Data;
        Result[PageNum].Name := Ext;   { temp carrier; renamed below }
        All[i].Data := nil;
        Inc(PageNum);
      end;
      SetLength(Result, PageNum);
      Padding := PagePaddingFor(PageNum);
      for i := 0 to PageNum - 1 do
        Result[i].Name := FormatPageName(i + 1, Padding, Result[i].Name);
    except
      FreeZipEntries(Result);
      raise;
    end;
  finally
    FreeZipEntries(All);
  end;
end;

end.
