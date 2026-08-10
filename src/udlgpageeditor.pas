unit udlgpageeditor;

{$mode ObjFPC}{$H+}

{
  Modal page-editor dialog for a single page of the open CBZ preview.

  The page is extracted at full resolution on a background
  TSingleImageLoader thread; the user then works on it with three tools:

    Resize  — new width/height in pixels (box-filter resample, enlarges and
              shrinks), optional aspect lock.
    Colors  — brightness, contrast, saturation, gamma, per-channel R/G/B
              balance, and one-click grayscale / sepia / invert.  The sliders
              drive a debounced live preview on a reduced-size copy; Apply
              runs the same pipeline on the full-resolution image.
    Split   — one or more parallel cut lines (horizontal = top/bottom,
              vertical = left/right) shown as draggable overlay lines on the
              preview; Apply cuts the page into N+1 pieces.

  Once a split is applied the dialog switches to split mode (Resize/Colors
  are disabled) and shows the pieces in reading order; OK then encodes every
  piece in the original page format.  Without a split, OK encodes the single
  edited image.  The dialog never touches the archive: main.pas stages the
  encoded streams into the page-editing model.

  Output format: the page's original extension is kept (JPEG/PNG/BMP/WebP);
  formats without an FPC writer (GIF/TIFF) map to PNG — see
  uimgutil.EncodeExtFor.
}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  ComCtrls, Spin, Dialogs, IntfGraphics, Math, Generics.Collections,
  upreviewloader, uimageedit, udlgbase;

type
  { One encoded split piece: the full-res image (for thumbnails, ownership
    transfers to the caller) plus the encoded archive bytes. }
  TPageEditSlice = record
    Image: TLazIntfImage;
    Stream: TMemoryStream;
    Ext: string;
  end;

  { Result handed to main.pas after OK.
    Split = False — replace mode: Image + Stream + Ext describe the single
    edited page.
    Split = True  — Image/Stream/Ext are unused; Slices holds the pieces in
    reading order (first piece replaces the original page, the rest are
    inserted after it). }
  TPageEditResult = record
    Split: boolean;
    Image: TLazIntfImage;
    Stream: TMemoryStream;
    Ext: string;
    Slices: array of TPageEditSlice;
  end;

  TdlgPageEditor = class(TForm)
  published
    { Wired from the .lfm — must be published for RTTI lookup. }
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
  private
    { Control panel }
    PanelControls: TPanel;
    PageControl: TPageControl;
    TabResize: TTabSheet;
    TabColors: TTabSheet;
    TabSplit: TTabSheet;
    LblResizeInfo: TLabel;
    LblResizeW: TLabel;
    SpinW: TSpinEdit;
    LblResizeH: TLabel;
    SpinH: TSpinEdit;
    CbKeepAspect: TCheckBox;
    BtnResizeApply: TButton;
    LblBrightnessVal: TLabel;
    TrackBrightness: TTrackBar;
    LblContrastVal: TLabel;
    TrackContrast: TTrackBar;
    LblSaturationVal: TLabel;
    TrackSaturation: TTrackBar;
    LblGammaVal: TLabel;
    TrackGamma: TTrackBar;
    LblRedVal: TLabel;
    TrackRed: TTrackBar;
    LblGreenVal: TLabel;
    TrackGreen: TTrackBar;
    LblBlueVal: TLabel;
    TrackBlue: TTrackBar;
    CbGray: TCheckBox;
    CbSepia: TCheckBox;
    CbInvert: TCheckBox;
    BtnColorApply: TButton;
    RgDirection: TRadioGroup;
    LblLines: TLabel;
    LBLines: TListBox;
    SpinLinePos: TSpinEdit;
    BtnAddLine: TButton;
    BtnRemoveLine: TButton;
    BtnSplitApply: TButton;
    PanelBottom: TPanel;
    BtnReset: TButton;
    BtnOk: TButton;
    BtnCancel: TButton;
    { Preview area }
    PanelPreview: TPanel;
    ImgPreview: TImage;
    PaintBoxLines: TPaintBox;
    ScrollBoxSlices: TScrollBox;
    SlicePanel: TPanel;
    TimerPreview: TTimer;
    { Editor state }
    FLoader: TSingleImageLoader;
    FFile: string;
    FEntryName: string;
    FEntryExt: string;
    FLoaded: boolean;
    { Working full-resolution image (mutated by Resize/Colors applies). }
    FFull: TLazIntfImage;
    { Preview-scale copy of FFull used as the base of the live colour
      preview. }
    FPreviewBase: TLazIntfImage;
    { The image currently shown in the preview pane. }
    FPreview: TLazIntfImage;
    { Split pieces (nil until a split is applied). }
    FSlices: TIntfImageArray;
    FModeSplit: boolean;
    { True once the user applied any edit (resize / colour / split): lets OK
      refuse to close when nothing was done instead of staging a pointless
      re-encode of the untouched original. }
    FModified: boolean;
    { Normalized cut-line positions in 0..1. }
    FLines: array of double;
    { Index of the line currently being dragged (-1 = none). }
    FDragIdx: integer;
    { Guards the W/H spin-feedback loop while keeping aspect. }
    FSyncing: boolean;
    { TImage widgets showing the split pieces. }
    FSliceImgs: specialize TObjectList<TImage>;
    { Height/width ratio of FFull (aspect lock). }
    FAspect: double;
    { Built and encoded by BtnOkClick; transferred out by ExtractResult. }
    FResult: TPageEditResult;
    procedure BuildResizeTab;
    procedure BuildColorsTab;
    procedure BuildSplitTab;
    { Behaviour }
    procedure StopLoader;
    procedure LoaderTerminated(Sender: TObject);
    procedure ResetToOriginal;
    function BuildAdj: TColorAdjust;
    procedure RefreshPreviewCopy;
    procedure UpdatePreviewImage;
    procedure RefreshLineList;
    procedure RefreshDimsLabel;
    procedure ShowSlices;
    procedure ClearSlicesView;
    procedure DiscardSlices;
    { Generates FSlices from FFull + FLines, switches to split mode and shows
      the pieces.  Returns False (with a dialog already shown) when there is
      nothing to split or the split fails. }
    function BuildSlices: boolean;
    { Maps a paintbox coordinate to the normalized position over the fitted
      image; False when outside the fitted image. }
    function PosToFrac(X, Y: integer; out AFrac: double): boolean;
    { The fitted (displayed) preview rect inside PaintBoxLines. }
    procedure FittedRect(out DW, DH, OX, OY: integer);
    { Event handlers }
    procedure BtnAddLineClick(Sender: TObject);
    procedure BtnRemoveLineClick(Sender: TObject);
    procedure BtnResetClick(Sender: TObject);
    procedure BtnSplitApplyClick(Sender: TObject);
    procedure BtnResizeApplyClick(Sender: TObject);
    procedure BtnColorApplyClick(Sender: TObject);
    procedure BtnOkClick(Sender: TObject);
    procedure CbKeepAspectChange(Sender: TObject);
    procedure PaintBoxLinesMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure PaintBoxLinesMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: integer);
    procedure PaintBoxLinesMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure PaintBoxLinesPaint(Sender: TObject);
    procedure RgDirectionClick(Sender: TObject);
    procedure SpinHChange(Sender: TObject);
    procedure SpinWChange(Sender: TObject);
    procedure TimerPreviewTimer(Sender: TObject);
    procedure TrackColorChange(Sender: TObject);
    procedure CheckboxColorChange(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Starts the background full-resolution extraction of AEntryName from
      AFile.  The dialog title is set to ACaption. }
    procedure LoadPage(const AFile, AEntryName, ACaption: string);
    { True once the page has been decoded and the tools are usable. }
    property Loaded: boolean read FLoaded;
    { Transfers the result (ownership) out of the dialog.  Call after
      ShowModal = mrOk. }
    function ExtractResult: TPageEditResult;
  end;

implementation

{$R *.lfm}

uses
  LCLType,
  uimgutil,
  uLog;

const
  { Preview width cap: the live colour preview runs on a copy at most this
    wide (height follows the aspect ratio), keeping slider feedback cheap. }
  PREVIEW_MAX_W = 600;

{ Creates a label inside ATab. }
function TabLabel(ATab: TWinControl; const ACaption: string;
  ALeft, ATop: integer; AWidth: integer = 300): TLabel;
begin
  Result := TLabel.Create(ATab.Owner);
  Result.Parent := ATab;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := AWidth;
  Result.Caption := ACaption;
end;

{ Creates a colour slider row: caption, trackbar, value label. }
function ColorSlider(ATab: TWinControl; const ACaption: string;
  AMin, AMax, AValue: integer; ALeft, ATop: integer;
  out AValLbl: TLabel): TTrackBar;
begin
  TabLabel(ATab, ACaption, ALeft, ATop + 6);
  Result := TTrackBar.Create(ATab.Owner);
  Result.Parent := ATab;
  Result.Left := ALeft + 80;
  Result.Top := ATop;
  Result.Width := 140;
  Result.Min := AMin;
  Result.Max := AMax;
  Result.Position := AValue;
  AValLbl := TLabel.Create(ATab.Owner);
  AValLbl.Parent := ATab;
  AValLbl.Left := ALeft + 232;
  AValLbl.Top := ATop + 6;
  AValLbl.Width := 40;
  AValLbl.Alignment := taRightJustify;
  AValLbl.Caption := IntToStr(AValue);
end;

{ TdlgPageEditor }

constructor TdlgPageEditor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLoader := nil;
  FLoaded := False;
  FFull := nil;
  FPreviewBase := nil;
  FPreview := nil;
  FSlices := nil;
  FModeSplit := False;
  FModified := False;
  FDragIdx := -1;
  FSyncing := False;
  FAspect := 1.0;
  FSliceImgs := specialize TObjectList<TImage>.Create(True);
end;

destructor TdlgPageEditor.Destroy;
var
  i: integer;
begin
  StopLoader;
  DiscardSlices;
  { Leftover result (failed OK, or OK never pressed after encoding): free
    the images and streams that were never transferred out. }
  FResult.Stream.Free;
  for i := 0 to High(FResult.Slices) do
  begin
    FResult.Slices[i].Stream.Free;
    FResult.Slices[i].Image.Free;
  end;
  FPreview.Free;
  FPreviewBase.Free;
  FFull.Free;
  FSliceImgs.Free;
  inherited Destroy;
end;

procedure TdlgPageEditor.FormCreate(Sender: TObject);
begin
  KeyPreview := True;
  Caption := 'Page editor';
  Width := 980;
  Height := 660;
  Position := poOwnerFormCenter;

  { Bottom button strip. }
  PanelBottom := CreateBottomPanel(Self, 46);
  BtnReset := CreateDialogButton(PanelBottom, '&Reset', 8, 8, mrNone, False,
    False);
  BtnReset.OnClick := @BtnResetClick;
  BtnReset.Enabled := False;
  BtnCancel := CreateDialogButton(PanelBottom, '&Cancel',
    PanelBottom.ClientWidth - DLG_BTN_WIDTH - 8, 8, mrCancel, False, True);
  BtnOk := CreateDialogButton(PanelBottom, '&OK',
    PanelBottom.ClientWidth - 2 * DLG_BTN_WIDTH - 16, 8, mrNone, True, False);
  BtnOk.OnClick := @BtnOkClick;
  BtnOk.Enabled := False;

  { Left control panel + right preview. }
  PanelControls := TPanel.Create(Self);
  PanelControls.Parent := Self;
  PanelControls.Align := alLeft;
  PanelControls.Width := 320;
  PanelControls.BevelOuter := bvNone;

  PanelPreview := TPanel.Create(Self);
  PanelPreview.Parent := Self;
  PanelPreview.Align := alClient;
  PanelPreview.BevelOuter := bvNone;
  PanelPreview.BorderSpacing.Left := 4;

  ImgPreview := TImage.Create(Self);
  ImgPreview.Parent := PanelPreview;
  ImgPreview.Align := alClient;
  ImgPreview.Stretch := True;
  ImgPreview.Proportional := True;
  ImgPreview.Center := True;

  { The paintbox sits on top of the image (created last = front) and draws
    the cut lines over the fitted picture. }
  PaintBoxLines := TPaintBox.Create(Self);
  PaintBoxLines.Parent := PanelPreview;
  PaintBoxLines.Align := alClient;
  PaintBoxLines.OnPaint := @PaintBoxLinesPaint;
  PaintBoxLines.OnMouseDown := @PaintBoxLinesMouseDown;
  PaintBoxLines.OnMouseMove := @PaintBoxLinesMouseMove;
  PaintBoxLines.OnMouseUp := @PaintBoxLinesMouseUp;

  ScrollBoxSlices := TScrollBox.Create(Self);
  ScrollBoxSlices.Parent := PanelPreview;
  ScrollBoxSlices.Align := alClient;
  ScrollBoxSlices.Visible := False;
  SlicePanel := TPanel.Create(Self);
  SlicePanel.Parent := ScrollBoxSlices;
  SlicePanel.Left := 0;
  SlicePanel.Top := 0;
  SlicePanel.Width := 200;
  SlicePanel.Height := 100;
  SlicePanel.BevelOuter := bvNone;

  { Tabs }
  PageControl := TPageControl.Create(Self);
  PageControl.Parent := PanelControls;
  PageControl.Align := alClient;
  PageControl.Enabled := False;  { tools usable only after the page loads }
  TabResize := PageControl.AddTabSheet;
  TabResize.Caption := 'Resize';
  TabColors := PageControl.AddTabSheet;
  TabColors.Caption := 'Colors';
  TabSplit := PageControl.AddTabSheet;
  TabSplit.Caption := 'Split';
  BuildResizeTab;
  BuildColorsTab;
  BuildSplitTab;

  TimerPreview := TTimer.Create(Self);
  TimerPreview.Interval := 80;
  TimerPreview.Enabled := False;
  TimerPreview.OnTimer := @TimerPreviewTimer;
end;

procedure TdlgPageEditor.BuildResizeTab;
begin
  LblResizeInfo := TabLabel(TabResize, 'Loading...', 8, 10);
  LblResizeInfo.Font.Style := [fsBold];

  LblResizeW := TabLabel(TabResize, 'Width:', 8, 44);
  SpinW := TSpinEdit.Create(Self);
  SpinW.Parent := TabResize;
  SpinW.Left := 110;
  SpinW.Top := 40;
  SpinW.Width := 110;
  SpinW.MaxValue := 16384;
  SpinW.OnChange := @SpinWChange;

  LblResizeH := TabLabel(TabResize, 'Height:', 8, 76);
  SpinH := TSpinEdit.Create(Self);
  SpinH.Parent := TabResize;
  SpinH.Left := 110;
  SpinH.Top := 72;
  SpinH.Width := 110;
  SpinH.MaxValue := 16384;
  SpinH.OnChange := @SpinHChange;

  CbKeepAspect := TCheckBox.Create(Self);
  CbKeepAspect.Parent := TabResize;
  CbKeepAspect.Left := 8;
  CbKeepAspect.Top := 106;
  CbKeepAspect.Width := 200;
  CbKeepAspect.Caption := 'Keep aspect ratio';
  CbKeepAspect.Checked := True;
  CbKeepAspect.OnChange := @CbKeepAspectChange;

  BtnResizeApply := TButton.Create(Self);
  BtnResizeApply.Parent := TabResize;
  BtnResizeApply.Left := 8;
  BtnResizeApply.Top := 136;
  BtnResizeApply.Width := 100;
  BtnResizeApply.Caption := '&Apply';
  BtnResizeApply.OnClick := @BtnResizeApplyClick;
end;

procedure TdlgPageEditor.BuildColorsTab;
var
  Y: integer;
begin
  Y := 8;
  TrackBrightness := ColorSlider(TabColors, 'Brightness', -100, 100, 0,
    8, Y, LblBrightnessVal);
  TrackBrightness.OnChange := @TrackColorChange;
  Inc(Y, 34);

  TrackContrast := ColorSlider(TabColors, 'Contrast', -100, 100, 0,
    8, Y, LblContrastVal);
  TrackContrast.OnChange := @TrackColorChange;
  Inc(Y, 34);

  TrackSaturation := ColorSlider(TabColors, 'Saturation', 0, 200, 100,
    8, Y, LblSaturationVal);
  TrackSaturation.OnChange := @TrackColorChange;
  Inc(Y, 34);

  TrackGamma := ColorSlider(TabColors, 'Gamma', 50, 300, 100,
    8, Y, LblGammaVal);
  TrackGamma.OnChange := @TrackColorChange;
  Inc(Y, 34);

  TrackRed := ColorSlider(TabColors, 'Red', -100, 100, 0,
    8, Y, LblRedVal);
  TrackRed.OnChange := @TrackColorChange;
  Inc(Y, 34);

  TrackGreen := ColorSlider(TabColors, 'Green', -100, 100, 0,
    8, Y, LblGreenVal);
  TrackGreen.OnChange := @TrackColorChange;
  Inc(Y, 34);

  TrackBlue := ColorSlider(TabColors, 'Blue', -100, 100, 0,
    8, Y, LblBlueVal);
  TrackBlue.OnChange := @TrackColorChange;
  Inc(Y, 40);

  CbGray := TCheckBox.Create(Self);
  CbGray.Parent := TabColors;
  CbGray.Left := 8;
  CbGray.Top := Y;
  CbGray.Width := 90;
  CbGray.Caption := 'Grayscale';
  CbGray.OnClick := @CheckboxColorChange;

  CbSepia := TCheckBox.Create(Self);
  CbSepia.Parent := TabColors;
  CbSepia.Left := 100;
  CbSepia.Top := Y;
  CbSepia.Width := 80;
  CbSepia.Caption := 'Sepia';
  CbSepia.OnClick := @CheckboxColorChange;

  CbInvert := TCheckBox.Create(Self);
  CbInvert.Parent := TabColors;
  CbInvert.Left := 185;
  CbInvert.Top := Y;
  CbInvert.Width := 80;
  CbInvert.Caption := 'Invert';
  CbInvert.OnClick := @CheckboxColorChange;
  Inc(Y, 30);

  BtnColorApply := TButton.Create(Self);
  BtnColorApply.Parent := TabColors;
  BtnColorApply.Left := 8;
  BtnColorApply.Top := Y;
  BtnColorApply.Width := 100;
  BtnColorApply.Caption := '&Apply';
  BtnColorApply.OnClick := @BtnColorApplyClick;
end;

procedure TdlgPageEditor.BuildSplitTab;
begin
  RgDirection := TRadioGroup.Create(Self);
  RgDirection.Parent := TabSplit;
  RgDirection.Left := 8;
  RgDirection.Top := 8;
  RgDirection.Width := 296;
  RgDirection.Height := 76;
  RgDirection.Caption := 'Cut direction';
  RgDirection.Items.Add('Horizontal line (top / bottom)');
  RgDirection.Items.Add('Vertical line (left / right)');
  RgDirection.ItemIndex := 0;
  RgDirection.OnClick := @RgDirectionClick;

  LblLines := TabLabel(TabSplit, 'Cut lines (drag them on the preview):',
    8, 92);

  LBLines := TListBox.Create(Self);
  LBLines.Parent := TabSplit;
  LBLines.Left := 8;
  LBLines.Top := 112;
  LBLines.Width := 296;
  LBLines.Height := 110;

  SpinLinePos := TSpinEdit.Create(Self);
  SpinLinePos.Parent := TabSplit;
  SpinLinePos.Left := 8;
  SpinLinePos.Top := 232;
  SpinLinePos.Width := 70;
  SpinLinePos.MinValue := 1;
  SpinLinePos.MaxValue := 99;
  SpinLinePos.Value := 50;

  BtnAddLine := TButton.Create(Self);
  BtnAddLine.Parent := TabSplit;
  BtnAddLine.Left := 88;
  BtnAddLine.Top := 230;
  BtnAddLine.Width := 90;
  BtnAddLine.Caption := '&Add line';
  BtnAddLine.OnClick := @BtnAddLineClick;

  BtnRemoveLine := TButton.Create(Self);
  BtnRemoveLine.Parent := TabSplit;
  BtnRemoveLine.Left := 186;
  BtnRemoveLine.Top := 230;
  BtnRemoveLine.Width := 100;
  BtnRemoveLine.Caption := '&Remove';
  BtnRemoveLine.OnClick := @BtnRemoveLineClick;

  BtnSplitApply := TButton.Create(Self);
  BtnSplitApply.Parent := TabSplit;
  BtnSplitApply.Left := 8;
  BtnSplitApply.Top := 268;
  BtnSplitApply.Width := 120;
  BtnSplitApply.Caption := '&Apply split';
  BtnSplitApply.OnClick := @BtnSplitApplyClick;
end;

procedure TdlgPageEditor.StopLoader;
begin
  if FLoader <> nil then
  begin
    FLoader.Terminate;
    FLoader := nil;
  end;
end;

{ Loads the page in the background; the tools stay disabled until the
  loader finishes. }
procedure TdlgPageEditor.LoadPage(const AFile, AEntryName, ACaption: string);
begin
  FFile := AFile;
  FEntryName := AEntryName;
  FEntryExt := ExtractFileExt(AEntryName);
  Caption := ACaption;
  LblResizeInfo.Caption := 'Loading...';
  PageControl.Enabled := False;
  BtnOk.Enabled := False;
  BtnReset.Enabled := False;
  StopLoader;
  FLoader := TSingleImageLoader.Create(AFile, AEntryName);
  FLoader.OnTerminate := @LoaderTerminated;
  FLoader.Start;
end;

procedure TdlgPageEditor.LoaderTerminated(Sender: TObject);
var
  Img: TLazIntfImage;
begin
  { Only the CURRENT loader may update the dialog (see udlgpageview for the
    same pattern). }
  if Sender <> FLoader then Exit;
  if FLoader.FatalException <> nil then
    Log('PageEditor load failed: %s: %s',
      [FLoader.FatalException.ClassName,
       Exception(FLoader.FatalException).Message]);
  Img := FLoader.ExtractImage;
  FLoader := nil;

  if Img = nil then
  begin
    LblResizeInfo.Caption := 'Cannot decode image';
    MessageDlg('Page editor', 'The page could not be decoded.',
      mtError, [mbOk], 0);
    Exit;
  end;

  { The working image replaces any previous content. }
  FFull.Free;
  FFull := Img;
  FLoaded := True;
  ResetToOriginal;
  PageControl.Enabled := True;
  BtnOk.Enabled := True;
  BtnReset.Enabled := True;
end;

{ Restores the working image from the disk original (FFull was already set,
  either by the initial load or by Reset's re-decode): this resets the
  tools, the preview and the split state. }
procedure TdlgPageEditor.ResetToOriginal;
begin
  FSyncing := True;
  try
    TrackBrightness.Position := 0;
    TrackContrast.Position := 0;
    TrackSaturation.Position := 100;
    TrackGamma.Position := 100;
    TrackRed.Position := 0;
    TrackGreen.Position := 0;
    TrackBlue.Position := 0;
    CbGray.Checked := False;
    CbSepia.Checked := False;
    CbInvert.Checked := False;
    SpinW.Value := FFull.Width;
    SpinH.Value := FFull.Height;
    CbKeepAspect.Checked := True;
  finally
    FSyncing := False;
  end;
  FAspect := FFull.Height / FFull.Width;

  { Leave split mode (if any). }
  if FModeSplit then
  begin
    FModeSplit := False;
    TabResize.Enabled := True;
    TabColors.Enabled := True;
  end;
  FLines := nil;
  FDragIdx := -1;
  FModified := False;
  DiscardSlices;

  { Rebuild the preview-scale base and the displayed copy. }
  FPreviewBase.Free;
  FPreviewBase := ScaleIntfImage(FFull, PREVIEW_MAX_W, 100000);
  RefreshPreviewCopy;
  RefreshDimsLabel;
end;

{ Reads the current slider/checkbox state into a TColorAdjust. }
function TdlgPageEditor.BuildAdj: TColorAdjust;
begin
  Result := NeutralColorAdjust;
  Result.Brightness := TrackBrightness.Position;
  Result.Contrast := 1 + TrackContrast.Position / 100;
  Result.Saturation := TrackSaturation.Position / 100;
  Result.Gamma := TrackGamma.Position / 100;
  Result.RGain := 1 + TrackRed.Position / 100;
  Result.GGain := 1 + TrackGreen.Position / 100;
  Result.BGain := 1 + TrackBlue.Position / 100;
  Result.Invert := CbInvert.Checked;
  Result.Grayscale := CbGray.Checked;
  Result.Sepia := CbSepia.Checked;
end;

{ Recomputes FPreview from FPreviewBase with the current colour settings and
  shows it in the preview pane. }
procedure TdlgPageEditor.RefreshPreviewCopy;
begin
  FPreview.Free;
  FPreview := AdjustColors(FPreviewBase, BuildAdj);
  UpdatePreviewImage;
end;

procedure TdlgPageEditor.UpdatePreviewImage;
var
  Bmp: TBitmap;
begin
  if FPreview = nil then Exit;
  Bmp := IntfToBitmap(FPreview);
  if Bmp <> nil then
    try
      ImgPreview.Picture.Assign(Bmp);
    finally
      Bmp.Free;
    end;
end;

procedure TdlgPageEditor.RefreshDimsLabel;
begin
  if FFull = nil then Exit;
  LblResizeInfo.Caption := Format('Image size: %dx%d px',
    [FFull.Width, FFull.Height]);
end;

{ ---------------------------------------------------------------------------
  Resize tab
  --------------------------------------------------------------------------- }

procedure TdlgPageEditor.CbKeepAspectChange(Sender: TObject);
begin
  if FSyncing or not CbKeepAspect.Checked or (FFull = nil) or
    (FAspect <= 0) then Exit;
  FSyncing := True;
  try
    SpinH.Value := Round(SpinW.Value * FAspect);
  finally
    FSyncing := False;
  end;
end;

procedure TdlgPageEditor.SpinWChange(Sender: TObject);
begin
  if FSyncing or not CbKeepAspect.Checked or (FFull = nil) or
    (FAspect <= 0) then Exit;
  FSyncing := True;
  try
    SpinH.Value := Round(SpinW.Value * FAspect);
  finally
    FSyncing := False;
  end;
end;

procedure TdlgPageEditor.SpinHChange(Sender: TObject);
begin
  if FSyncing or not CbKeepAspect.Checked or (FFull = nil) or
    (FAspect <= 0) then Exit;
  FSyncing := True;
  try
    SpinW.Value := Round(SpinH.Value / FAspect);
  finally
    FSyncing := False;
  end;
end;

procedure TdlgPageEditor.BtnResizeApplyClick(Sender: TObject);
var
  NewW, NewH: integer;
  Res: TLazIntfImage;
begin
  if FFull = nil then Exit;
  NewW := SpinW.Value;
  NewH := SpinH.Value;
  if (NewW <= 0) or (NewH <= 0) then Exit;
  if (NewW = FFull.Width) and (NewH = FFull.Height) then Exit;
  Res := ResampleIntfImage(FFull, NewW, NewH);
  if Res = nil then
  begin
    MessageDlg('Page editor', 'Resize failed.', mtError, [mbOk], 0);
    Exit;
  end;
  FFull.Free;
  FFull := Res;
  FModified := True;
  FPreviewBase.Free;
  FPreviewBase := ScaleIntfImage(FFull, PREVIEW_MAX_W, 100000);
  RefreshPreviewCopy;
  RefreshDimsLabel;
end;

{ ---------------------------------------------------------------------------
  Colors tab
  --------------------------------------------------------------------------- }

procedure TdlgPageEditor.TrackColorChange(Sender: TObject);
begin
  { Update the numeric value label next to the slider, then restart the
    debounce timer for the live colour preview. }
  if Sender = TrackBrightness then
    LblBrightnessVal.Caption := IntToStr(TrackBrightness.Position)
  else if Sender = TrackContrast then
    LblContrastVal.Caption := IntToStr(TrackContrast.Position)
  else if Sender = TrackSaturation then
    LblSaturationVal.Caption := IntToStr(TrackSaturation.Position)
  else if Sender = TrackGamma then
    LblGammaVal.Caption := IntToStr(TrackGamma.Position)
  else if Sender = TrackRed then
    LblRedVal.Caption := IntToStr(TrackRed.Position)
  else if Sender = TrackGreen then
    LblGreenVal.Caption := IntToStr(TrackGreen.Position)
  else if Sender = TrackBlue then
    LblBlueVal.Caption := IntToStr(TrackBlue.Position);
  if FPreviewBase = nil then Exit;
  TimerPreview.Enabled := False;
  TimerPreview.Enabled := True;
end;

procedure TdlgPageEditor.CheckboxColorChange(Sender: TObject);
begin
  if FPreviewBase = nil then Exit;
  TimerPreview.Enabled := False;
  TimerPreview.Enabled := True;
end;

procedure TdlgPageEditor.TimerPreviewTimer(Sender: TObject);
begin
  TimerPreview.Enabled := False;
  if FPreviewBase <> nil then
    RefreshPreviewCopy;
end;

procedure TdlgPageEditor.BtnColorApplyClick(Sender: TObject);
var
  Res: TLazIntfImage;
begin
  if FFull = nil then Exit;
  Res := AdjustColors(FFull, BuildAdj);
  if Res = nil then
  begin
    MessageDlg('Page editor', 'Colour adjustment failed.', mtError, [mbOk], 0);
    Exit;
  end;
  FFull.Free;
  FFull := Res;
  FModified := True;
  FPreviewBase.Free;
  FPreviewBase := ScaleIntfImage(FFull, PREVIEW_MAX_W, 100000);
  RefreshPreviewCopy;
  RefreshDimsLabel;
end;

{ ---------------------------------------------------------------------------
  Split tab
  --------------------------------------------------------------------------- }

{ Rebuilds the listbox from FLines (percent strings). }
procedure TdlgPageEditor.RefreshLineList;
var
  i: integer;
begin
  LBLines.Items.BeginUpdate;
  try
    LBLines.Clear;
    for i := 0 to High(FLines) do
      LBLines.Items.Add(Format('%d%%', [Round(FLines[i] * 100)]));
  finally
    LBLines.Items.EndUpdate;
  end;
end;

procedure TdlgPageEditor.BtnAddLineClick(Sender: TObject);
var
  i, j, P: integer;
begin
  if FFull = nil then Exit;
  P := SpinLinePos.Value;
  { Insertion-sort the new position into FLines. }
  SetLength(FLines, Length(FLines) + 1);
  i := High(FLines) - 1;
  while (i >= 0) and (FLines[i] > P / 100) do
  begin
    FLines[i + 1] := FLines[i];
    Dec(i);
  end;
  FLines[i + 1] := P / 100;
  RefreshLineList;
  { Select the line just added and grab it for dragging. }
  j := 0;
  while (j <= High(FLines)) and (FLines[j] < P / 100) do Inc(j);
  LBLines.ItemIndex := j;
  FDragIdx := j;
  PaintBoxLines.Invalidate;
end;

procedure TdlgPageEditor.BtnRemoveLineClick(Sender: TObject);
var
  i, Sel: integer;
begin
  Sel := LBLines.ItemIndex;
  if (Sel < 0) or (Sel > High(FLines)) then Exit;
  for i := Sel to High(FLines) - 1 do
    FLines[i] := FLines[i + 1];
  SetLength(FLines, Length(FLines) - 1);
  FDragIdx := -1;
  RefreshLineList;
  PaintBoxLines.Invalidate;
end;

{ The fitted (displayed) preview rect inside PaintBoxLines: the paintbox
  sits exactly over ImgPreview (both alClient), and TImage's
  Stretch+Proportional+Center uses the same fit math. }
procedure TdlgPageEditor.FittedRect(out DW, DH, OX, OY: integer);
var
  F: double;
begin
  DW := 0;
  DH := 0;
  OX := 0;
  OY := 0;
  if (FPreview = nil) or (FPreview.Width = 0) or (FPreview.Height = 0) then
    Exit;
  F := Min(PaintBoxLines.Width / FPreview.Width,
    PaintBoxLines.Height / FPreview.Height);
  DW := Round(FPreview.Width * F);
  DH := Round(FPreview.Height * F);
  OX := (PaintBoxLines.Width - DW) div 2;
  OY := (PaintBoxLines.Height - DH) div 2;
end;

{ Draws the cut lines over the fitted preview image. }
procedure TdlgPageEditor.PaintBoxLinesPaint(Sender: TObject);
var
  i, DW, DH, OX, OY: integer;
begin
  if (FPreview = nil) or (Length(FLines) = 0) then Exit;
  FittedRect(DW, DH, OX, OY);
  if (DW = 0) or (DH = 0) then Exit;
  PaintBoxLines.Canvas.Pen.Color := clRed;
  PaintBoxLines.Canvas.Pen.Width := 2;
  for i := 0 to High(FLines) do
    if RgDirection.ItemIndex = 0 then
      { Horizontal cut: the line is drawn horizontally at frac of the height. }
      PaintBoxLines.Canvas.Line(OX, OY + Round(FLines[i] * DH),
        OX + DW, OY + Round(FLines[i] * DH))
    else
      PaintBoxLines.Canvas.Line(OX + Round(FLines[i] * DW), OY,
        OX + Round(FLines[i] * DW), OY + DH);
end;

function TdlgPageEditor.PosToFrac(X, Y: integer; out AFrac: double): boolean;
var
  DW, DH, OX, OY: integer;
begin
  Result := False;
  AFrac := 0;
  FittedRect(DW, DH, OX, OY);
  if (DW = 0) or (DH = 0) then Exit;
  if (X < OX) or (X > OX + DW) or (Y < OY) or (Y > OY + DH) then Exit;
  if RgDirection.ItemIndex = 0 then
    AFrac := (Y - OY) / DH
  else
    AFrac := (X - OX) / DW;
  Result := True;
end;

procedure TdlgPageEditor.PaintBoxLinesMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Frac: double;
  i: integer;
  Best: integer;
  BestDist: double;
  DW, DH, OX, OY: integer;
begin
  if (Button <> mbLeft) or (FPreview = nil) then Exit;
  if not PosToFrac(X, Y, Frac) then Exit;
  { Grab the nearest line within 12 pixels of the click. }
  FittedRect(DW, DH, OX, OY);
  Best := -1;
  BestDist := 1.0;
  for i := 0 to High(FLines) do
    if Abs(FLines[i] - Frac) < BestDist then
    begin
      BestDist := Abs(FLines[i] - Frac);
      Best := i;
    end;
  if (Best >= 0) and (BestDist <= 12 / Max(DW, DH)) then
  begin
    FDragIdx := Best;
    LBLines.ItemIndex := Best;
  end
  else if FFull <> nil then
  begin
    { No line within reach: create one at the click position and drag it.
      Dragging is the intuitive "add a split" gesture — without this, a drag
      on an empty preview silently did nothing. }
    if Frac < 0.01 then Frac := 0.01;
    if Frac > 0.99 then Frac := 0.99;
    SetLength(FLines, Length(FLines) + 1);
    FLines[High(FLines)] := Frac;
    FDragIdx := High(FLines);
    RefreshLineList;
    LBLines.ItemIndex := FDragIdx;
    PaintBoxLines.Invalidate;
  end;
end;

procedure TdlgPageEditor.PaintBoxLinesMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: integer);
var
  Frac: double;
begin
  if (FDragIdx < 0) or not (ssLeft in Shift) then Exit;
  if not PosToFrac(X, Y, Frac) then Exit;
  if Frac < 0.01 then Frac := 0.01;
  if Frac > 0.99 then Frac := 0.99;
  FLines[FDragIdx] := Frac;
  RefreshLineList;
  PaintBoxLines.Invalidate;
end;

procedure TdlgPageEditor.PaintBoxLinesMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  FDragIdx := -1;
end;

procedure TdlgPageEditor.RgDirectionClick(Sender: TObject);
begin
  PaintBoxLines.Invalidate;
end;

procedure TdlgPageEditor.BtnSplitApplyClick(Sender: TObject);
begin
  BuildSlices;
end;

{ Generates the pieces from the working image and the current cut lines,
  switches to split mode and shows the pieces in reading order.  FFull is
  kept as the pre-split image so OK can re-derive the pieces deterministically
  even when "Apply split" was skipped or failed earlier. }
function TdlgPageEditor.BuildSlices: boolean;
begin
  Result := False;
  if (FFull = nil) or (Length(FLines) = 0) then
  begin
    MessageDlg('Page editor', 'Add at least one cut line first.',
      mtInformation, [mbOk], 0);
    Exit;
  end;
  DiscardSlices;
  try
    FSlices := SplitIntfImage(FFull, RgDirection.ItemIndex = 0, FLines);
  except
    on E: Exception do
    begin
      Log('PageEditor split failed: %s: %s', [E.ClassName, E.Message]);
      MessageDlg('Page editor', 'Split failed: ' + E.Message,
        mtError, [mbOk], 0);
      Exit;
    end;
  end;
  if Length(FSlices) < 2 then
  begin
    MessageDlg('Page editor', 'Split produced no pieces.', mtError, [mbOk], 0);
    Exit;
  end;
  FModeSplit := True;
  FModified := True;
  TabResize.Enabled := False;
  TabColors.Enabled := False;
  ShowSlices;
  Result := True;
end;

{ Shows the split pieces in reading order (stacked for horizontal cuts,
  side by side for vertical cuts) inside the scrollbox. }
procedure TdlgPageEditor.ShowSlices;
var
  i, X, Y: integer;
  Img: TImage;
  Bmp: TBitmap;
  PW, PH: integer;
  SideBySide: boolean;
begin
  ClearSlicesView;
  SideBySide := RgDirection.ItemIndex <> 0;  { vertical cut → side by side }
  X := 0;
  Y := 0;
  PW := 220;
  for i := 0 to High(FSlices) do
  begin
    Bmp := IntfToBitmap(FSlices[i]);
    if Bmp = nil then Continue;
    Img := TImage.Create(SlicePanel);
    Img.Parent := SlicePanel;
    try
      Img.Picture.Assign(Bmp);
    finally
      Bmp.Free;
    end;
    PH := Max(1, Round(PW * FSlices[i].Height / FSlices[i].Width));
    Img.Width := PW;
    Img.Height := PH;
    Img.Left := X;
    Img.Top := Y;
    Img.Stretch := True;
    Img.Proportional := True;
    if SideBySide then
      Inc(X, PW + 8)
    else
      Inc(Y, PH + 8);
    FSliceImgs.Add(Img);
  end;
  SlicePanel.Width := Max(PW, X - 8);
  SlicePanel.Height := Max(1, Y - 8);
  ScrollBoxSlices.Visible := True;
  ImgPreview.Visible := False;
  PaintBoxLines.Visible := False;
end;

procedure TdlgPageEditor.ClearSlicesView;
begin
  FSliceImgs.Clear;  { owns the TImages }
end;

procedure TdlgPageEditor.DiscardSlices;
begin
  if Length(FSlices) > 0 then
    FreeImageArray(FSlices);
  FSlices := nil;
  ClearSlicesView;
  ScrollBoxSlices.Visible := False;
  ImgPreview.Visible := True;
  PaintBoxLines.Visible := True;
end;

{ ---------------------------------------------------------------------------
  Bottom bar
  --------------------------------------------------------------------------- }

procedure TdlgPageEditor.BtnResetClick(Sender: TObject);
begin
  if not FLoaded then Exit;
  { Re-decode the original from disk so any applied resize/colour edits are
    truly discarded (no second in-memory copy needed). }
  StopLoader;
  FLoader := TSingleImageLoader.Create(FFile, FEntryName);
  FLoader.OnTerminate := @LoaderTerminated;
  FLoader.Start;
  LblResizeInfo.Caption := 'Loading...';
  PageControl.Enabled := False;
end;

procedure TdlgPageEditor.BtnOkClick(Sender: TObject);
var
  i: integer;
  Stream: TMemoryStream;
  AllOk: boolean;
  WantSplit: boolean;
begin
  if not FLoaded then Exit;

  { The result is derived from the current state, not from whether "Apply
    split" happened to run: any cut line means the user wants a split, so OK
    re-derives the pieces even if the apply step was skipped or failed. }
  WantSplit := FModeSplit or (Length(FLines) > 0);
  if not WantSplit and not FModified then
  begin
    MessageDlg('Page editor', 'No changes to apply.', mtInformation, [mbOk], 0);
    Exit;
  end;

  if WantSplit then
  begin
    { Re-derive the pieces from the working image and the current lines
      (FFull is kept as the pre-split image).  BuildSlices shows the preview
      and reports failures; the dialog stays open on failure. }
    if not BuildSlices then Exit;
  end;

  AllOk := True;
  if FModeSplit then
  begin
    { Encode every piece first; only transfer ownership into the result when
      ALL encodes succeed, so a failed run leaves the dialog fully usable. }
    SetLength(FResult.Slices, Length(FSlices));
    for i := 0 to High(FSlices) do
    begin
      FResult.Slices[i].Ext := EncodeExtFor(FEntryExt);
      Stream := EncodeIntfImage(FSlices[i], FResult.Slices[i].Ext);
      if Stream = nil then
      begin
        AllOk := False;
        Break;
      end;
      FResult.Slices[i].Stream := Stream;
    end;
    if AllOk then
    begin
      FResult.Split := True;
      for i := 0 to High(FSlices) do
      begin
        FResult.Slices[i].Image := FSlices[i];
        FSlices[i] := nil;
      end;
    end
    else
    begin
      { Discard the partial streams; the pieces themselves stay in FSlices. }
      for i := 0 to High(FResult.Slices) do
        FResult.Slices[i].Stream.Free;
      FResult.Slices := nil;
    end;
  end
  else
  begin
    FResult.Split := False;
    FResult.Ext := EncodeExtFor(FEntryExt);
    Stream := EncodeIntfImage(FFull, FResult.Ext);
    if Stream = nil then
      AllOk := False
    else
    begin
      FResult.Stream := Stream;
      FResult.Image := FFull;
      FFull := nil;
    end;
  end;

  if not AllOk then
  begin
    MessageDlg('Page editor',
      'Encoding failed (is the WebP library available?).',
      mtError, [mbOk], 0);
    Exit;
  end;
  ModalResult := mrOk;
end;

procedure TdlgPageEditor.FormKeyDown(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    ModalResult := mrCancel;
    Key := 0;
  end;
end;

function TdlgPageEditor.ExtractResult: TPageEditResult;
begin
  Result := FResult;
  FResult.Stream := nil;
  FResult.Image := nil;
  FResult.Slices := nil;
end;

end.
