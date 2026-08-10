unit upreviewloader;

{$mode ObjFPC}{$H+}

{ Background loaders for preview panes: TPreviewLoader decodes all pages of
  an archive into thumbnail-sized TLazIntfImages (sequence builder preview);
  TSingleImageLoader decodes one named entry at full resolution (floating
  page-view dialog). }

interface

uses
  Classes, SysUtils, IntfGraphics, uloaderthread;

type
  TPreviewLoader = class(TThread)
  private
    FFile: string;
    FPages: TLazIntfImageList;
    { Pages collected by alphabetical rank (0 = first page); flushed into
      FPages in order once the archive has been fully decoded. }
    FByRank: array of TLazIntfImage;
    procedure HandlePage(const AName: string; AImage: TLazIntfImage;
      AIndex: integer; var ACancel: boolean);
  protected
    procedure Execute; override;
  public
    constructor Create(const AFile: string);
    destructor Destroy; override;
    function ExtractPages: TLazIntfImageList;
    property Pages: TLazIntfImageList read FPages;
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
  uimgutil, uzipeditor, uservicebase;

{ TPreviewLoader }

constructor TPreviewLoader.Create(const AFile: string);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FFile := AFile;
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

procedure TPreviewLoader.Execute;
var
  i: integer;
begin
  ForEachImage(FFile, @HandlePage, CacheW, CacheH);
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
