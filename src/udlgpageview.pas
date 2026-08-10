unit udlgpageview;

{$mode ObjFPC}{$H+}

{
  Non-modal floating window showing one full-resolution page extracted from
  a CBZ, with the same wheel interactions as the sequence builder preview:

    - Ctrl+wheel   zoom in/out (1.0..5.0), anchored at the viewport centre
    - wheel        pan vertically (top to bottom)
    - shift+wheel  pan horizontally (left/right)

  Opening the window and pressing Escape hides it again (the instance is
  kept so a later reuse is instant).  Each LoadPage replaces the page
  content; the image is decoded on a background TSingleImageLoader thread.
}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  IntfGraphics, upreviewloader, Types;

type
  TdlgPageView = class(TForm)
    LblTitle: TLabel;
    ScrollBoxPreview: TScrollBox;
    ImgPreview: TImage;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure PreviewMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
  private
    FLoader: TSingleImageLoader;
    FImage: TLazIntfImage;
    FLoaded: boolean;
    FZoomLevel: double;
    procedure LoaderTerminated(Sender: TObject);
    procedure ApplyZoom(const AOldZoom: double);
    procedure StopLoader;
    procedure ShowImage;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Extracts the named entry of AFile at full resolution in the background
      and fits it to the viewport.  ACaption is shown in the title bar. }
    procedure LoadPage(const AFile, AEntryName, ACaption: string);
  end;

implementation

{$R *.lfm}

uses
  LCLType,
  uimgutil,
  uLog;

const
  { Wheel-delta divisor for preview panning (~40 px per notch) — same
    feel as the sequence builder preview. }
  PreviewScrollStep = 3;
  ZOOM_STEP = 0.15;
  ZOOM_MIN = 1.0;
  ZOOM_MAX = 5.0;

{ TdlgPageView }

constructor TdlgPageView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FImage := nil;
  FLoaded := False;
  FLoader := nil;
  FZoomLevel := 1.0;
  KeyPreview := True;
end;

destructor TdlgPageView.Destroy;
begin
  StopLoader;
  FImage.Free;
  inherited Destroy;
end;

{ Hides instead of closing so the instance can be reused; a running loader
  is stopped so its result can never touch a hidden window. }
procedure TdlgPageView.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  StopLoader;
  CloseAction := caHide;
end;

procedure TdlgPageView.FormKeyDown(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    Close;
    Key := 0;
  end;
end;

procedure TdlgPageView.StopLoader;
begin
  if FLoader <> nil then
  begin
    FLoader.Terminate;
    FLoader := nil;
  end;
end;

procedure TdlgPageView.LoadPage(const AFile, AEntryName, ACaption: string);
begin
  StopLoader;
  FreeAndNil(FImage);
  FLoaded := False;
  FZoomLevel := 1.0;
  LblTitle.Caption := ACaption;
  ImgPreview.Picture.Clear;
  ScrollBoxPreview.HorzScrollBar.Position := 0;
  ScrollBoxPreview.VertScrollBar.Position := 0;

  FLoader := TSingleImageLoader.Create(AFile, AEntryName);
  FLoader.OnTerminate := @LoaderTerminated;
  FLoader.Start;
end;

procedure TdlgPageView.LoaderTerminated(Sender: TObject);
begin
  { Only the CURRENT loader may update the preview; a superseded loader
    (replaced by another LoadPage, or stopped on close) must not touch the
    window.  The thread frees itself (FreeOnTerminate). }
  if Sender <> FLoader then Exit;

  if FLoader.FatalException <> nil then
    Log('PageView load failed: %s: %s',
      [FLoader.FatalException.ClassName,
       Exception(FLoader.FatalException).Message]);

  FImage := FLoader.ExtractImage;
  FLoader := nil;

  if FImage = nil then
  begin
    LblTitle.Caption := 'No image';
    ImgPreview.Picture.Clear;
    Exit;
  end;

  ShowImage;
end;

procedure TdlgPageView.ShowImage;
var
  Bmp: TBitmap;
begin
  if FImage = nil then Exit;
  Bmp := IntfToBitmap(FImage);
  if Bmp <> nil then
  begin
    try
      ImgPreview.Picture.Assign(Bmp);
    finally
      Bmp.Free;
    end;
  end;
  FLoaded := True;
  FZoomLevel := 1.0;
  ApplyZoom(1.0);
end;

procedure TdlgPageView.PreviewMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
var
  OldZoom: double;
begin
  if not (ssCtrl in Shift) then
  begin
    { Plain wheel pans the preview vertically (top to bottom);
      shift+wheel pans horizontally (left/right). }
    if not FLoaded then Exit;
    Handled := True;
    if ssShift in Shift then
      ScrollBoxPreview.HorzScrollBar.Position :=
        ScrollBoxPreview.HorzScrollBar.Position - WheelDelta div PreviewScrollStep
    else
      ScrollBoxPreview.VertScrollBar.Position :=
        ScrollBoxPreview.VertScrollBar.Position - WheelDelta div PreviewScrollStep;
    Exit;
  end;

  if not FLoaded then Exit;
  OldZoom := FZoomLevel;
  if WheelDelta > 0 then
    FZoomLevel := FZoomLevel + ZOOM_STEP
  else
    FZoomLevel := FZoomLevel - ZOOM_STEP;
  if FZoomLevel < ZOOM_MIN then FZoomLevel := ZOOM_MIN;
  if FZoomLevel > ZOOM_MAX then FZoomLevel := ZOOM_MAX;
  ApplyZoom(OldZoom);
  Handled := True;
end;

procedure TdlgPageView.ApplyZoom(const AOldZoom: double);
var
  SrcW, SrcH, AreaW, AreaH, OldCX, OldCY: integer;
  Ratio: double;
begin
  if FImage = nil then Exit;
  if FZoomLevel <= 1.0 then
  begin
    ImgPreview.Align := alClient;
    ImgPreview.Stretch := True;
    ImgPreview.Proportional := True;
    ImgPreview.Center := True;
    ScrollBoxPreview.HorzScrollBar.Position := 0;
    ScrollBoxPreview.VertScrollBar.Position := 0;
  end
  else
  begin
    SrcW := FImage.Width;
    SrcH := FImage.Height;
    AreaW := ScrollBoxPreview.ClientWidth;
    AreaH := ScrollBoxPreview.ClientHeight;
    if (SrcW = 0) or (SrcH = 0) then Exit;
    Ratio := AreaW / SrcW;
    if AreaH / SrcH < Ratio then
      Ratio := AreaH / SrcH;

    { Anchor the zoom at the viewport centre: capture the content point
      under the centre, then keep it stationary while the image scales
      from the top-left. }
    OldCX := ScrollBoxPreview.HorzScrollBar.Position + AreaW div 2;
    OldCY := ScrollBoxPreview.VertScrollBar.Position + AreaH div 2;

    ImgPreview.Align := alNone;
    ImgPreview.Stretch := True;
    ImgPreview.Proportional := False;
    ImgPreview.Center := False;
    ImgPreview.Left := 0;
    ImgPreview.Top := 0;
    ImgPreview.Width := Round(SrcW * Ratio * FZoomLevel);
    ImgPreview.Height := Round(SrcH * Ratio * FZoomLevel);

    ScrollBoxPreview.HorzScrollBar.Position :=
      CenterAnchorScrollPos(OldCX, AOldZoom, FZoomLevel, AreaW, ImgPreview.Width);
    ScrollBoxPreview.VertScrollBar.Position :=
      CenterAnchorScrollPos(OldCY, AOldZoom, FZoomLevel, AreaH, ImgPreview.Height);
  end;
end;

end.