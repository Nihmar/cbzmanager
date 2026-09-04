unit upreviewloader;

{$mode ObjFPC}{$H+}

{ Background loaders for preview panes: TPreviewLoader decodes all pages of
  an archive into thumbnail-sized TLazIntfImages (sequence builder preview);
  TSingleImageLoader decodes one named entry at full resolution (floating
  page-view dialog). }

interface

uses
  Classes, SysUtils, IntfGraphics, uzipcore, uloaderthread;

type
  TPreviewLoader = class(TThread)
  private
    FFile: string;
    FThreads: integer;
    FPages: TLazIntfImageList;
    { Pages collected by alphabetical rank (0 = first page); flushed into
      FPages in order once the archive has been fully decoded. }
    FByRank: array of TLazIntfImage;
    { Pool state: the collected entries (read-only source), the job list
      (entry indices of image pages) and the rank per job position. }
    FEntries: TZipEntries;
    FJobs: array of integer;
    FJobRanks: array of integer;
    FJobCursor: integer;
    procedure HandlePage(const AName: string; AImage: TLazIntfImage;
      AIndex: integer; var ACancel: boolean);
    { Next job position in FJobs, or -1 when exhausted.  Thread-safe:
      workers compete on an atomic cursor. }
    function NextJob: integer;
    procedure ProduceSequential;
    procedure ProduceParallel(AThreadCount: integer);
  protected
    procedure Execute; override;
  public
    { AThreads selects the page-decode pool size: 0 = automatic (CPU count
      capped at 4), 1 = sequential streaming (one page in RAM at a time). }
    constructor Create(const AFile: string; AThreads: integer = 0);
    destructor Destroy; override;
    function ExtractPages: TLazIntfImageList;
    property Pages: TLazIntfImageList read FPages;
  end;

  { Pool worker of TPreviewLoader: claims job positions and decodes +
    scales each page into its own rank slot (each rank is written exactly
    once, so slot writes need no lock). }
  TPreviewPageWorker = class(TThread)
  private
    FLoader: TPreviewLoader;
  protected
    procedure Execute; override;
  public
    constructor Create(ALoader: TPreviewLoader);
  end;

  { Decodes the single named entry of an archive at full resolution off the
    main thread.  On success ExtractImage transfers ownership of the decoded
    image (nil when the entry is missing or undecodable).  Failed runs leave
    a message in TThread.FatalException, like the seqbuilder's loader. }
  TSingleImageLoader = class(TThread)
  private
    FFile: string;
    FEntryName: string;
    FImage: TLazIntfImage;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFile, AEntryName: string);
    destructor Destroy; override;
    function ExtractImage: TLazIntfImage;
  end;

implementation

uses
  Math, uimgutil, uzipeditor, uservicebase;

{ Number of concurrent page-decode workers: at most four, regardless of
  core count — every worker holds a full-resolution page in RAM while the
  collected entries stay alive for the whole run. }
function PreviewWorkerCount: integer;
begin
  Result := Min(4, Max(1, OnlineCpuCount));
end;

{ Binary search for S in a CompareStr-sorted list.  Returns the rank or -1.
  (Local copy of the uzipeditor helper, which is not exported.) }
function PreviewRank(List: TStringList; const S: string): integer;
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

function PreviewCompareNames(List: TStringList; Index1, Index2: integer): integer;
begin
  Result := CompareStr(List[Index1], List[Index2]);
end;

{ TPreviewPageWorker }

constructor TPreviewPageWorker.Create(ALoader: TPreviewLoader);
begin
  { Created suspended: the loader Start()s every worker before joining.
    FreeOnTerminate stays False — the loader frees the workers after the
    join. }
  inherited Create(True);
  FLoader := ALoader;
end;

procedure TPreviewPageWorker.Execute;
var
  JobPos, EntryIdx, Rank: integer;
  Img, Small: TLazIntfImage;
begin
  while True do
  begin
    if Terminated or FLoader.Terminated then Exit;
    JobPos := FLoader.NextJob;
    if JobPos < 0 then Exit;
    EntryIdx := FLoader.FJobs[JobPos];
    Rank := FLoader.FJobRanks[JobPos];
    { DecodeImage never raises (failures become nil); ScaleIntfImage is
      nil-safe.  Undecodable pages leave a nil slot, skipped by the flush
      — like the sequential HandlePage. }
    Img := DecodeImage(FLoader.FEntries[EntryIdx].Data,
      ExtractFileExt(FLoader.FEntries[EntryIdx].Name), CacheW, CacheH);
    Small := ScaleIntfImage(Img, CacheW, CacheH);
    Img.Free;
    if (Rank >= 0) and (Rank < Length(FLoader.FByRank)) then
      FLoader.FByRank[Rank] := Small
    else
      Small.Free;
  end;
end;

{ TPreviewLoader }

constructor TPreviewLoader.Create(const AFile: string; AThreads: integer);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FFile := AFile;
  FThreads := AThreads;
  FPages := TLazIntfImageList.Create(True);
end;

destructor TPreviewLoader.Destroy;
var
  i: integer;
begin
  { Free any images that were never flushed into FPages (aborted run). }
  for i := 0 to High(FByRank) do
    FByRank[i].Free;
  FPages.Free;
  inherited;
end;

function TPreviewLoader.ExtractPages: TLazIntfImageList;
begin
  Result := FPages;
  FPages := nil;
end;

function TPreviewLoader.NextJob: integer;
begin
  Result := InterlockedIncrement(FJobCursor) - 1;
  if Result >= Length(FJobs) then
    Result := -1;
end;

procedure TPreviewLoader.ProduceSequential;
begin
  ForEachImage(FFile, @HandlePage, CacheW, CacheH);
end;

procedure TPreviewLoader.ProduceParallel(AThreadCount: integer);
var
  i, Rank: integer;
  Names: TStringList;
  Workers: array of TPreviewPageWorker;
begin
  FEntries := CollectZipEntries(FFile);
  try
    FJobs := nil;
    FJobRanks := nil;
    Names := TStringList.Create;
    try
      for i := 0 to High(FEntries) do
        if IsImageExt(ExtractFileExt(FEntries[i].Name)) then
          Names.Add(FEntries[i].Name);
      Names.CustomSort(@PreviewCompareNames);
      for i := 0 to High(FEntries) do
        if IsImageExt(ExtractFileExt(FEntries[i].Name)) then
        begin
          Rank := PreviewRank(Names, FEntries[i].Name);
          if Rank < 0 then Continue;
          SetLength(FJobs, Length(FJobs) + 1);
          FJobs[High(FJobs)] := i;
          SetLength(FJobRanks, Length(FJobRanks) + 1);
          FJobRanks[High(FJobRanks)] := Rank;
        end;
    finally
      Names.Free;
    end;
    if Length(FJobs) = 0 then Exit;
    { One slot per image page, indexed by alphabetical rank. }
    SetLength(FByRank, Length(FJobs));

    FJobCursor := 0;
    SetLength(Workers, Min(AThreadCount, Length(FJobs)));
    try
      for i := 0 to High(Workers) do
        Workers[i] := TPreviewPageWorker.Create(Self);
      for i := 0 to High(Workers) do
        Workers[i].Start;
      for i := 0 to High(Workers) do
        Workers[i].WaitFor;
    finally
      for i := 0 to High(Workers) do
        Workers[i].Free;
    end;
  finally
    FreeZipEntries(FEntries);
    FEntries := nil;
  end;
end;

procedure TPreviewLoader.Execute;
var
  i, ThreadCount: integer;
begin
  ThreadCount := FThreads;
  if ThreadCount <= 0 then
    ThreadCount := PreviewWorkerCount;
  if ThreadCount <= 1 then
    ProduceSequential
  else
    ProduceParallel(ThreadCount);
  { Flush in reading order (alphabetical rank), skipping undecodable pages. }
  for i := 0 to High(FByRank) do
    if FByRank[i] <> nil then
      FPages.Add(FByRank[i]);
  FByRank := nil;
end;

procedure TPreviewLoader.HandlePage(const AName: string; AImage: TLazIntfImage;
  AIndex: integer; var ACancel: boolean);
var
  Small: TLazIntfImage;
begin
  Small := ScaleIntfImage(AImage, CacheW, CacheH);
  AImage.Free;
  { Skip undecodable pages (Small = nil) instead of adding a phantom blank
    slot that would inflate the page count and show a stale frame. }
  if Small = nil then Exit;
  if AIndex < 0 then
    FPages.Add(Small)
  else
  begin
    if AIndex >= Length(FByRank) then
      SetLength(FByRank, AIndex + 1);
    FByRank[AIndex] := Small;
  end;
  ACancel := Terminated;
end;

{ TSingleImageLoader }

constructor TSingleImageLoader.Create(const AFile, AEntryName: string);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FFile := AFile;
  FEntryName := AEntryName;
end;

destructor TSingleImageLoader.Destroy;
begin
  { Frees the image when ExtractImage was never called (aborted run). }
  FImage.Free;
  inherited Destroy;
end;

function TSingleImageLoader.ExtractImage: TLazIntfImage;
begin
  Result := FImage;
  FImage := nil;
end;

procedure TSingleImageLoader.Execute;
begin
  { CBR archives (RAR) are read through libarchive. }
  if SameText(ExtractFileExt(FFile), CBR_EXT) then
    FImage := GetCbrImageAsIntfImage(FFile, FEntryName)
  else
    FImage := GetImageAsIntfImage(FFile, FEntryName);
end;

end.
