unit udlgbatchedit;

{$mode ObjFPC}{$H+}

{
  Modal dialog for the batch page edit: applies one uniform edit (percent
  resize, colour adjustments and/or parallel cut lines) to the selected
  pages of the open CBZ preview.

  The dialog only collects the parameters; main.pas runs the actual work on
  TMultiEditWorker (ubatchedit) and stages the results into the page model.
  A live preview shows the first selected page with the current resize and
  colour settings applied (debounced, like the single page editor); split
  lines are entered as percentages in the list, not on the preview.

  Split semantics: every selected page is cut along the same normalized
  positions, so a 50% line halves every page regardless of its size.
}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  ComCtrls, Spin, Dialogs, IntfGraphics, Math,
  uimageedit, uimgutil, uzipeditor, ubatchedit;

type
  TdlgBatchEdit = class(TForm)
    { Wired from the .lfm — controls and event handlers must be published
      for RTTI lookup. }
    PanelBottom: TPanel;
    BtnApply: TButton;
    BtnCancel: TButton;
    PanelLeft: TPanel;
    LblHeader: TLabel;
    PageControl: TPageControl;
    TabResize: TTabSheet;
    CbResize: TCheckBox;
    LblPercent: TLabel;
    SpinPercent: TSpinEdit;
    TabColors: TTabSheet;
    LblBrightness: TLabel;
    TrackBrightness: TTrackBar;
    LblBrightnessVal: TLabel;
    LblContrast: TLabel;
    TrackContrast: TTrackBar;
    LblContrastVal: TLabel;
    LblSaturation: TLabel;
    TrackSaturation: TTrackBar;
    LblSaturationVal: TLabel;
    LblGamma: TLabel;
    TrackGamma: TTrackBar;
    LblGammaVal: TLabel;
    LblRed: TLabel;
    TrackRed: TTrackBar;
    LblRedVal: TLabel;
    LblGreen: TLabel;
    TrackGreen: TTrackBar;
    LblGreenVal: TLabel;
    LblBlue: TLabel;
    TrackBlue: TTrackBar;
    LblBlueVal: TLabel;
    CbGray: TCheckBox;
    CbSepia: TCheckBox;
    CbInvert: TCheckBox;
    TabSplit: TTabSheet;
    RgDirection: TRadioGroup;
    LblLines: TLabel;
    LBLines: TListBox;
    SpinLinePos: TSpinEdit;
    BtnAddLine: TButton;
    BtnRemoveLine: TButton;
    PanelPreview: TPanel;
    LblPreviewInfo: TLabel;
    ImgPreview: TImage;
    TimerPreview: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure CbResizeChange(Sender: TObject);
    procedure TrackColorChange(Sender: TObject);
    procedure CheckboxColorChange(Sender: TObject);
    procedure TimerPreviewTimer(Sender: TObject);
    procedure RgDirectionClick(Sender: TObject);
    procedure BtnAddLineClick(Sender: TObject);
    procedure BtnRemoveLineClick(Sender: TObject);
    procedure BtnApplyClick(Sender: TObject);
  private
    FFile: string;
    FInput: TMultiEditPageInput;
    FPageCount: integer;
    { Full-resolution first selected page (preview source). }
    FFull: TLazIntfImage;
    { Preview-scale copy of FFull used as the base of the live preview. }
    FPreviewBase: TLazIntfImage;
    { The image currently shown in the preview pane. }
    FPreview: TLazIntfImage;
    { Normalized cut-line positions in 0..1 (insertion-sorted). }
    FLines: array of double;
    FSyncing: boolean;
    function BuildAdj: TColorAdjust;
    procedure RefreshHeader;
    procedure RefreshPreviewCopy;
    procedure RefreshLineList;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Sets the batch target: APageCount selected pages, the first one
      described by AInput (used for the live preview) extracted from
      AFile.  The dialog decodes the first page synchronously. }
    procedure LoadTarget(const AFile: string; const AInput: TMultiEditPageInput;
      APageCount: integer);
    { The parameters to apply; call after ShowModal = mrOk. }
    function ExtractParams: TMultiEditParams;
  end;

implementation

{$R *.lfm}

uses
  LCLType;

const
  { Preview width cap for the live preview copy. }
  PREVIEW_MAX_W = 260;

constructor TdlgBatchEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  KeyPreview := True;
  FFull := nil;
  FPreviewBase := nil;
  FPreview := nil;
  FSyncing := False;
end;

destructor TdlgBatchEdit.Destroy;
begin
  FPreview.Free;
  FPreviewBase.Free;
  FFull.Free;
  inherited Destroy;
end;

procedure TdlgBatchEdit.FormCreate(Sender: TObject);
begin
end;

procedure TdlgBatchEdit.FormKeyDown(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    ModalResult := mrCancel;
    Key := 0;
  end;
end;

{ Loads the target: remembers the selection size and decodes the first
  selected page (its current state) for the live preview. }
procedure TdlgBatchEdit.LoadTarget(const AFile: string;
  const AInput: TMultiEditPageInput; APageCount: integer);
begin
  FFile := AFile;
  FInput := AInput;
  FPageCount := APageCount;
  Caption := Format('Batch edit — %d page(s)', [APageCount]);
  RefreshHeader;

  FFull.Free;
  FFull := nil;
  try
    if FInput.Data <> nil then
      FFull := DecodeImage(FInput.Data, FInput.Ext)
    else if FInput.OrigName <> '' then
      FFull := GetImageAsIntfImage(FFile, FInput.OrigName);
  except
    FFull := nil;
  end;

  FPreviewBase.Free;
  FPreviewBase := nil;
  if FFull <> nil then
    FPreviewBase := ScaleIntfImage(FFull, PREVIEW_MAX_W, 100000);
  RefreshPreviewCopy;
end;

{ Reads the current slider/checkbox state into a TColorAdjust. }
function TdlgBatchEdit.BuildAdj: TColorAdjust;
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

{ Header shows the outcome: N pages, or N pages -> N*(lines+1) pieces. }
procedure TdlgBatchEdit.RefreshHeader;
var
  M: integer;
begin
  M := FPageCount;
  if Length(FLines) > 0 then
    M := FPageCount * (Length(FLines) + 1);
  if M = FPageCount then
    LblHeader.Caption := Format('Apply to %d selected page(s)', [FPageCount])
  else
    LblHeader.Caption := Format('Apply to %d pages -> %d pieces',
      [FPageCount, M]);
end;

{ Recomputes the preview from FPreviewBase with the current resize and
  colour settings and shows it. }
procedure TdlgBatchEdit.RefreshPreviewCopy;
var
  Bmp: TBitmap;
  Base, Res: TLazIntfImage;
begin
  if FPreviewBase = nil then Exit;
  Base := FPreviewBase;
  Res := nil;
  if CbResize.Checked and (SpinPercent.Value <> 100) then
  begin
    Res := ResampleIntfImage(Base,
      Max(1, Round(Base.Width * SpinPercent.Value / 100)),
      Max(1, Round(Base.Height * SpinPercent.Value / 100)));
    if Res <> nil then
      Base := Res;
  end;
  FPreview.Free;
  FPreview := AdjustColors(Base, BuildAdj);
  Res.Free;
  if FPreview = nil then Exit;
  Bmp := IntfToBitmap(FPreview);
  if Bmp <> nil then
    try
      ImgPreview.Picture.Assign(Bmp);
    finally
      Bmp.Free;
    end;
end;

procedure TdlgBatchEdit.TrackColorChange(Sender: TObject);
begin
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
  TimerPreview.Enabled := False;
  TimerPreview.Enabled := True;
end;

procedure TdlgBatchEdit.CheckboxColorChange(Sender: TObject);
begin
  TimerPreview.Enabled := False;
  TimerPreview.Enabled := True;
end;

procedure TdlgBatchEdit.CbResizeChange(Sender: TObject);
begin
  SpinPercent.Enabled := CbResize.Checked;
  TimerPreview.Enabled := False;
  TimerPreview.Enabled := True;
end;

procedure TdlgBatchEdit.TimerPreviewTimer(Sender: TObject);
begin
  TimerPreview.Enabled := False;
  RefreshPreviewCopy;
end;

procedure TdlgBatchEdit.RgDirectionClick(Sender: TObject);
begin
  { Direction does not affect the preview or the piece count. }
end;

{ Rebuilds the listbox from FLines (percent strings). }
procedure TdlgBatchEdit.RefreshLineList;
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

procedure TdlgBatchEdit.BtnAddLineClick(Sender: TObject);
var
  i, j, P: integer;
begin
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
  j := 0;
  while (j <= High(FLines)) and (FLines[j] < P / 100) do Inc(j);
  LBLines.ItemIndex := j;
  RefreshHeader;
end;

procedure TdlgBatchEdit.BtnRemoveLineClick(Sender: TObject);
var
  i, Sel: integer;
begin
  Sel := LBLines.ItemIndex;
  if (Sel < 0) or (Sel > High(FLines)) then Exit;
  for i := Sel to High(FLines) - 1 do
    FLines[i] := FLines[i + 1];
  SetLength(FLines, Length(FLines) - 1);
  RefreshLineList;
  RefreshHeader;
end;

function TdlgBatchEdit.ExtractParams: TMultiEditParams;
begin
  Result.Resize := CbResize.Checked and (SpinPercent.Value <> 100);
  Result.Percent := SpinPercent.Value;
  Result.Adj := BuildAdj;
  Result.Split := Length(FLines) > 0;
  Result.Horizontal := RgDirection.ItemIndex = 0;
  Result.Lines := FLines;
end;

procedure TdlgBatchEdit.BtnApplyClick(Sender: TObject);
begin
  if ParamsAreNeutral(ExtractParams) then
  begin
    MessageDlg('Batch edit', 'No changes to apply.', mtInformation, [mbOk], 0);
    Exit;
  end;
  ModalResult := mrOk;
end;

end.
