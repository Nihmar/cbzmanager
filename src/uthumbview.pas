unit uthumbview;

{
  uthumbview – thumbnail rendering and zoom for the two TListView panes.

  TThumbnailStrip owns the "rebuild a TImageList at width N" logic for one
  list: from a decoded-image cache (the file grid) or from the in-memory page
  model (the preview pane, skipping Gone pages and leaving the rows alone).

  TZoomController owns the debounced zoom slider: a track change only
  restarts the timer, and the OnApply callback receives the new width once the
  user stops dragging.  The form wires the LCL events to it and supplies the
  callback, so both classes stay free of form state and are unit-testable.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, ComCtrls, Controls, StdCtrls, ExtCtrls, IntfGraphics, uloaderthread,
  upageeditmodel;

const
  { Zoom / thumbnail sizing.  The zoom value is the thumbnail width in
    pixels; height is derived from PAGE_ASPECT_RATIO via ThumbHeight. }
  THUMB_DEFAULT_SIZE = 128;   // initial width and default zoom
  THUMB_MIN_SIZE = 48;        // smallest width the zoom slider allows
  THUMB_RENDER_FLOOR = 16;    // absolute lower bound when rendering thumbs
  ZOOM_STEP = 32;             // width change per zoom-in / zoom-out step

type
  { Width delivered to the form once the zoom debounce elapses. }
  TZoomApplyEvent = procedure(ASize: integer) of object;

  { Thumbnail rendering for one TListView + TImageList pair. }
  TThumbnailStrip = class
  private
    FList: TListView;
    FImages: TImageList;
    { Detach/clear/resize/reattach; callers use it under their own update. }
    procedure PrepareUnlocked(ASize: integer);
  public
    constructor Create(AList: TListView; AImages: TImageList;
      AInitialSize: integer = THUMB_DEFAULT_SIZE);
    { Width actually rendered: never below THUMB_RENDER_FLOOR. }
    class function ClampSize(ASize: integer): integer;
    { Clears and resizes the image list.  The preview pane uses it before the
      loader threads publish rows (they append to the same image list). }
    procedure Prepare(ASize: integer);
    { Rebuilds the image list from a decoded-image cache (the file grid). }
    procedure LoadFromCache(ACache: TLazIntfImageList; ASize: integer);
    { Rebuilds the image list from the page model, skipping Gone pages.  The
      rows and their Data are untouched; BuildRows keeps ImageIndex in sync
      (visible page n -> image index n). }
    procedure LoadFromModel(const APages: TPageStates; ASize: integer);
    property List: TListView read FList;
    property Images: TImageList read FImages;
  end;

  { Debounced zoom slider. }
  TZoomController = class
  private
    FTrack: TTrackBar;
    FLabel: TLabel;
    FTimer: TTimer;
    FOnApply: TZoomApplyEvent;
    procedure UpdateLabel;
    function GetPosition: integer;
  public
    constructor Create(ATrack: TTrackBar; ALabel: TLabel; ATimer: TTimer;
      AOnApply: TZoomApplyEvent);
    { Initial range and position (widths). }
    procedure Setup(AMax, ADefault: integer);
    { Slider moved: the label updates immediately, the rebuild is deferred. }
    procedure OnTrackChange;
    { Debounce elapsed: apply the current width through OnApply. }
    procedure OnTimer;
    { Mouse wheel over the slider: steps by the track's Frequency. }
    procedure OnWheel(AWheelDelta: integer);
    { Zoom-in/zoom-out menu step, clamped to the track range. }
    procedure StepBy(ADelta: integer);
    { Width the strips should render at (floored). }
    function RenderedSize: integer;
    property Position: integer read GetPosition;
  end;

implementation

uses
  SysUtils, Math, uImgUtil;

{ TThumbnailStrip }

constructor TThumbnailStrip.Create(AList: TListView; AImages: TImageList;
  AInitialSize: integer);
begin
  inherited Create;
  FList := AList;
  FImages := AImages;
  Prepare(AInitialSize);
end;

class function TThumbnailStrip.ClampSize(ASize: integer): integer;
begin
  Result := Max(THUMB_RENDER_FLOOR, ASize);
end;

procedure TThumbnailStrip.PrepareUnlocked(ASize: integer);
begin
  { The image list refuses to clear while it is assigned to the list view. }
  FList.LargeImages := nil;
  FImages.Clear;
  FImages.Width := ClampSize(ASize);
  FImages.Height := ThumbHeight(FImages.Width);
  FList.LargeImages := FImages;
end;

procedure TThumbnailStrip.Prepare(ASize: integer);
begin
  FList.BeginUpdate;
  try
    PrepareUnlocked(ASize);
  finally
    FList.EndUpdate;
  end;
end;

procedure TThumbnailStrip.LoadFromCache(ACache: TLazIntfImageList;
  ASize: integer);
var
  i: integer;
begin
  FList.BeginUpdate;
  try
    PrepareUnlocked(ASize);
    for i := 0 to ACache.Count - 1 do
      AppendThumb(FImages, ACache[i]);
  finally
    FList.EndUpdate;
  end;
end;

procedure TThumbnailStrip.LoadFromModel(const APages: TPageStates;
  ASize: integer);
var
  i, idx: integer;
begin
  FList.BeginUpdate;
  try
    PrepareUnlocked(ASize);
    idx := 0;
    for i := 0 to High(APages) do
    begin
      if APages[i].Gone then Continue;
      AppendThumb(FImages, APages[i].Image);
      Inc(idx);
    end;
  finally
    FList.EndUpdate;
  end;
end;

{ TZoomController }

constructor TZoomController.Create(ATrack: TTrackBar; ALabel: TLabel;
  ATimer: TTimer; AOnApply: TZoomApplyEvent);
begin
  inherited Create;
  FTrack := ATrack;
  FLabel := ALabel;
  FTimer := ATimer;
  FOnApply := AOnApply;
end;

procedure TZoomController.Setup(AMax, ADefault: integer);
begin
  { Max before Min: TTrackBar clamps Min to the current Max (whose default is
    10), so raising Min first would silently leave the slider at 10. }
  FTrack.Max := AMax;
  FTrack.Min := THUMB_MIN_SIZE;
  FTrack.Position := ADefault;
  UpdateLabel;
end;

function TZoomController.GetPosition: integer;
begin
  Result := FTrack.Position;
end;

procedure TZoomController.UpdateLabel;
begin
  if FLabel <> nil then
    FLabel.Caption := IntToStr(FTrack.Position);
end;

procedure TZoomController.OnTrackChange;
begin
  { Debounce: restart on every change so only the final position triggers a
    rebuild, but update the label now for snappy feedback. }
  FTimer.Enabled := False;
  FTimer.Enabled := True;
  UpdateLabel;
end;

procedure TZoomController.OnTimer;
begin
  FTimer.Enabled := False;
  if Assigned(FOnApply) then
    FOnApply(RenderedSize);
  UpdateLabel;
end;

procedure TZoomController.OnWheel(AWheelDelta: integer);
begin
  if AWheelDelta > 0 then
    StepBy(FTrack.Frequency)
  else
    StepBy(-FTrack.Frequency);
end;

procedure TZoomController.StepBy(ADelta: integer);
begin
  FTrack.Position := Min(FTrack.Max, Max(FTrack.Min, FTrack.Position + ADelta));
  UpdateLabel;
end;

function TZoomController.RenderedSize: integer;
begin
  Result := TThumbnailStrip.ClampSize(FTrack.Position);
end;

end.
