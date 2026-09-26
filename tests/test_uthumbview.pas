unit test_uthumbview;

{$mode objfpc}{$H+}

{ Tests for uthumbview: the thumbnail strips and the debounced zoom
  controller extracted from the main form. }

interface

uses
  fpcunit, testregistry,
  Classes, SysUtils, IntfGraphics;

type
  TThumbViewTest = class(TTestCase)
  private
    FAppInitialized: boolean;
    FCaptured: integer;
    procedure EnsureApp;
    { Zoom callback target: records the width the controller applies. }
    procedure Capture(ASize: integer);
  published
    procedure Strip_ClampSize_FloorsAtMinimum;
    procedure Strip_Prepare_ResizesWithoutImages;
    procedure Strip_LoadFromCache_ResizesAndAdds;
    procedure Strip_LoadFromModel_SkipsGonePages;
    procedure Zoom_SetupAndClampedSteps;
    procedure Zoom_TrackChange_DebouncesAndAppliesFlooredWidth;
    procedure Zoom_Wheel_StepsByFrequency;
  end;

implementation

uses
  Forms, ComCtrls, Controls, StdCtrls, ExtCtrls,
  uimgutil, uloaderthread, upageeditmodel, uzipeditor,
  uthumbview,
  test_helpers;

procedure TThumbViewTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

procedure TThumbViewTest.Capture(ASize: integer);
begin
  FCaptured := ASize;
end;

{ A decoded 1x1 image for the caches. }
function MakeImage: TLazIntfImage;
var
  Stream: TMemoryStream;
begin
  Stream := CreateMinimalPNGStream;
  try
    Result := DecodeImage(Stream, '.png');
  finally
    Stream.Free;
  end;
end;

procedure TThumbViewTest.Strip_ClampSize_FloorsAtMinimum;
begin
  AssertEquals('below the floor is raised',
    16, TThumbnailStrip.ClampSize(4));
  AssertEquals('normal width unchanged',
    96, TThumbnailStrip.ClampSize(96));
end;

procedure TThumbViewTest.Strip_Prepare_ResizesWithoutImages;
var
  LV: TListView;
  IL: TImageList;
  Strip: TThumbnailStrip;
begin
  EnsureApp;
  LV := TListView.Create(nil);
  IL := TImageList.Create(nil);
  Strip := TThumbnailStrip.Create(LV, IL);
  try
    Strip.Prepare(200);
    AssertEquals('no images added', 0, IL.Count);
    AssertEquals('width applied', 200, IL.Width);
    AssertEquals('height from aspect ratio', ThumbHeight(200), IL.Height);
    AssertTrue('image list stays attached', LV.LargeImages = IL);
  finally
    Strip.Free;
    IL.Free;
    LV.Free;
  end;
end;

procedure TThumbViewTest.Strip_LoadFromCache_ResizesAndAdds;
var
  LV: TListView;
  IL: TImageList;
  Cache: TLazIntfImageList;
  Strip: TThumbnailStrip;
begin
  EnsureApp;
  LV := TListView.Create(nil);
  IL := TImageList.Create(nil);
  Cache := TLazIntfImageList.Create(True);   { owns the images }
  try
    Cache.Add(MakeImage);
    Cache.Add(MakeImage);

    Strip := TThumbnailStrip.Create(LV, IL);
    try
      Strip.LoadFromCache(Cache, 96);
      AssertEquals('both cache images rendered', 2, IL.Count);
      AssertEquals('width applied', 96, IL.Width);
      AssertEquals('height from aspect ratio', ThumbHeight(96), IL.Height);
    finally
      Strip.Free;
    end;
  finally
    Cache.Free;
    IL.Free;
    LV.Free;
  end;
end;

procedure TThumbViewTest.Strip_LoadFromModel_SkipsGonePages;
var
  LV: TListView;
  IL: TImageList;
  Strip: TThumbnailStrip;
  Pages: TPageStates;
  Img1, Img2: TLazIntfImage;
begin
  EnsureApp;
  LV := TListView.Create(nil);
  IL := TImageList.Create(nil);
  Img1 := MakeImage;
  Img2 := MakeImage;
  try
    SetLength(Pages, 3);
    Pages[0].Name := 'page_0001.png';
    Pages[0].Image := Img1;
    Pages[0].Gone := False;
    Pages[1].Name := 'page_0002.png';
    Pages[1].Gone := True;
    Pages[2].Name := 'page_0003.png';
    Pages[2].Image := Img2;
    Pages[2].Gone := False;

    Strip := TThumbnailStrip.Create(LV, IL);
    try
      Strip.LoadFromModel(Pages, 64);
      AssertEquals('Gone page skipped', 2, IL.Count);
      AssertEquals('width applied', 64, IL.Width);
    finally
      Strip.Free;
    end;
  finally
    Img1.Free;
    Img2.Free;
    IL.Free;
    LV.Free;
  end;
end;

procedure TThumbViewTest.Zoom_SetupAndClampedSteps;
var
  Track: TTrackBar;
  Lbl: TLabel;
  Timer: TTimer;
  Zoom: TZoomController;
begin
  EnsureApp;
  Track := TTrackBar.Create(nil);
  Lbl := TLabel.Create(nil);
  Timer := TTimer.Create(nil);
  Zoom := TZoomController.Create(Track, Lbl, Timer, @Capture);
  try
    Zoom.Setup(320, 128);
    AssertEquals('minimum', 48, Track.Min);
    AssertEquals('maximum', 320, Track.Max);
    AssertEquals('initial position', 128, Track.Position);
    AssertEquals('label follows', '128', Lbl.Caption);

    Zoom.StepBy(32);
    AssertEquals('step up', 160, Track.Position);
    Zoom.StepBy(9999);
    AssertEquals('clamped to maximum', 320, Track.Position);
    Zoom.StepBy(-9999);
    AssertEquals('clamped to minimum', 48, Track.Position);
  finally
    Zoom.Free;
    Timer.Free;
    Lbl.Free;
    Track.Free;
  end;
end;

procedure TThumbViewTest.Zoom_TrackChange_DebouncesAndAppliesFlooredWidth;
var
  Track: TTrackBar;
  Lbl: TLabel;
  Timer: TTimer;
  Zoom: TZoomController;
begin
  EnsureApp;
  Track := TTrackBar.Create(nil);
  Lbl := TLabel.Create(nil);
  Timer := TTimer.Create(nil);
  Zoom := TZoomController.Create(Track, Lbl, Timer, @Capture);
  try
    Zoom.Setup(320, 128);

    Zoom.OnTrackChange;
    AssertTrue('timer armed', Timer.Enabled);
    AssertEquals('nothing applied before the debounce', 0, FCaptured);

    { A track whose range reaches below the render floor: the controller must
      still render at the floor. }
    Track.Min := 0;
    Track.Position := 10;
    Zoom.OnTimer;
    AssertFalse('timer disarmed after firing', Timer.Enabled);
    AssertEquals('floored width applied', 16, FCaptured);
    AssertEquals('label follows the track', '10', Lbl.Caption);
  finally
    Zoom.Free;
    Timer.Free;
    Lbl.Free;
    Track.Free;
  end;
end;

procedure TThumbViewTest.Zoom_Wheel_StepsByFrequency;
var
  Track: TTrackBar;
  Lbl: TLabel;
  Timer: TTimer;
  Zoom: TZoomController;
begin
  EnsureApp;
  Track := TTrackBar.Create(nil);
  Lbl := TLabel.Create(nil);
  Timer := TTimer.Create(nil);
  Zoom := TZoomController.Create(Track, Lbl, Timer, @Capture);
  try
    Zoom.Setup(320, 128);
    Track.Frequency := 20;
    Track.Position := 200;

    Zoom.OnWheel(120);
    AssertEquals('wheel up adds a frequency step', 220, Track.Position);
    Zoom.OnWheel(-120);
    AssertEquals('wheel down subtracts a frequency step', 200, Track.Position);
  finally
    Zoom.Free;
    Timer.Free;
    Lbl.Free;
    Track.Free;
  end;
end;

initialization
  RegisterTest(TThumbViewTest);
end.
