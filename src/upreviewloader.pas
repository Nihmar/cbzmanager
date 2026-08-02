unit upreviewloader;

{$mode ObjFPC}{$H+}

{ Background loader that decodes all pages of an archive into thumbnail-sized
  TLazIntfImages, used by the sequence builder preview pane. }

interface

uses
  Classes, IntfGraphics, uloaderthread;

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

implementation

uses
  uimgutil, uzipeditor;

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

end.
