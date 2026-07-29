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
    procedure HandlePage(const AName: string; AImage: TLazIntfImage;
      var ACancel: boolean);
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
  FreeOnTerminate := False;
  FFile := AFile;
  FPages := TLazIntfImageList.Create(True);
end;

destructor TPreviewLoader.Destroy;
begin
  FPages.Free;
  inherited;
end;

function TPreviewLoader.ExtractPages: TLazIntfImageList;
begin
  Result := FPages;
  FPages := nil;
end;

procedure TPreviewLoader.Execute;
begin
  ForEachImage(FFile, @HandlePage);
end;

procedure TPreviewLoader.HandlePage(const AName: string; AImage: TLazIntfImage;
  var ACancel: boolean);
var
  Small: TLazIntfImage;
begin
  Small := ScaleIntfImage(AImage, CacheW, CacheH);
  AImage.Free;
  FPages.Add(Small);
  ACancel := Terminated;
end;

end.
