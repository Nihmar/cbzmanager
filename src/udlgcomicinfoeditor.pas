unit udlgcomicinfoeditor;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Spin, ucomicinfo;

type
  TdlgComicInfoEditor = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    Pages: TPageControl;
    PanelBottom: TPanel;
    BtnSave: TButton;
    BtnRemove: TButton;
    BtnCancel: TButton;
    CbBackup: TCheckBox;
    LblHeader: TLabel;

    { General tab }
    EdSeries: TEdit;
    EdNumber: TEdit;
    EdTitle: TEdit;
    SpVolume: TSpinEdit;
    SpCount: TSpinEdit;
    EdAltSeries: TEdit;
    EdAltNumber: TEdit;
    SpAltCount: TSpinEdit;
    EdFormat: TEdit;
    SpPageCount: TSpinEdit;

    { Story tab }
    MemoSummary: TMemo;
    MemoNotes: TMemo;
    EdGenre: TEdit;
    EdTags: TEdit;
    EdStoryArc: TEdit;
    EdStoryArcNumber: TEdit;
    EdSeriesGroup: TEdit;
    EdCharacters: TEdit;
    EdTeams: TEdit;
    EdLocations: TEdit;

    { Credits tab }
    EdWriter: TEdit;
    EdPenciller: TEdit;
    EdInker: TEdit;
    EdColorist: TEdit;
    EdLetterer: TEdit;
    EdCoverArtist: TEdit;
    EdEditor: TEdit;

    { Publishing tab }
    EdPublisher: TEdit;
    EdImprint: TEdit;
    SpYear: TSpinEdit;
    SpMonth: TSpinEdit;
    SpDay: TSpinEdit;
    EdWeb: TEdit;
    EdLanguageISO: TEdit;
    CbManga: TComboBox;
    CbBlackAndWhite: TComboBox;
    CbAgeRating: TComboBox;
    EdScanInfo: TEdit;
    SpCommunityRating: TFloatSpinEdit;

    FData: TComicInfo;
    FFilePath: string;
    FFileName: string;
    FExistingLoaded: boolean;
    FRemoved: boolean;
    procedure BtnRemoveClick(Sender: TObject);
    function GetBackup: boolean;

    procedure BuildGeneralTab(ATab: TTabSheet);
    procedure BuildStoryTab(ATab: TTabSheet);
    procedure BuildCreditsTab(ATab: TTabSheet);
    procedure BuildPublishingTab(ATab: TTabSheet);
    procedure DataToUI;
    procedure UIToData;
    function AddRow(AParent: TWinControl; ATop: integer;
      const ACaption: string; AHighlight: boolean): TLabel;
    function AddEdit(AParent: TWinControl; ALeft, ATop, AWidth: integer): TEdit;
    function AddSpin(AParent: TWinControl; ALeft, ATop, AWidth, AMin,
      AMax: integer): TSpinEdit;
    function AddCombo(AParent: TWinControl; ALeft, ATop, AWidth: integer;
      const AItems: array of string): TComboBox;
    function AddMemo(AParent: TWinControl; ALeft, ATop, AWidth,
      AHeight: integer): TMemo;
  public
    procedure LoadFile(const AFilePath, AFileName: string;
      const ASeriesName: string; APageCount: integer);
    function GetData: TComicInfo;
    property HasExisting: boolean read FExistingLoaded;
    property Removed: boolean read FRemoved;
    property BackupEnabled: boolean read GetBackup;
  end;

implementation

{$R *.lfm}

uses
  uzipcore;

const
  LBL_LEFT = 12;
  ED_LEFT = 140;
  ED_WIDTH = 390;
  ED_HALF = 100;
  ROW_H = 28;

procedure TdlgComicInfoEditor.FormCreate(Sender: TObject);
var
  Tab: TTabSheet;
begin
  BorderStyle := bsDialog;
  BorderIcons := [biSystemMenu];

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 44;
  PanelBottom.BevelOuter := bvNone;

  CbBackup := TCheckBox.Create(Self);
  CbBackup.Parent := PanelBottom;
  CbBackup.Left := 12;
  CbBackup.Top := 10;
  CbBackup.Width := 200;
  CbBackup.Caption := 'Backup before saving';
  CbBackup.Checked := True;

  BtnRemove := TButton.Create(Self);
  BtnRemove.Parent := PanelBottom;
  BtnRemove.Left := 272;
  BtnRemove.Top := 7;
  BtnRemove.Width := 80;
  BtnRemove.Height := 30;
  BtnRemove.Caption := 'Remove';
  BtnRemove.Enabled := False;
  BtnRemove.OnClick := @BtnRemoveClick;

  BtnSave := TButton.Create(Self);
  BtnSave.Parent := PanelBottom;
  BtnSave.Left := 368;
  BtnSave.Top := 7;
  BtnSave.Width := 80;
  BtnSave.Height := 30;
  BtnSave.Caption := 'Save';
  BtnSave.Default := True;
  BtnSave.ModalResult := mrOK;

  BtnCancel := TButton.Create(Self);
  BtnCancel.Parent := PanelBottom;
  BtnCancel.Left := 456;
  BtnCancel.Top := 7;
  BtnCancel.Width := 80;
  BtnCancel.Height := 30;
  BtnCancel.Caption := 'Cancel';
  BtnCancel.Cancel := True;
  BtnCancel.ModalResult := mrCancel;

  Pages := TPageControl.Create(Self);
  Pages.Parent := Self;
  Pages.Align := alClient;

  Tab := TTabSheet.Create(Pages);
  Tab.PageControl := Pages;
  Tab.Caption := 'General';
  BuildGeneralTab(Tab);

  Tab := TTabSheet.Create(Pages);
  Tab.PageControl := Pages;
  Tab.Caption := 'Story';
  BuildStoryTab(Tab);

  Tab := TTabSheet.Create(Pages);
  Tab.PageControl := Pages;
  Tab.Caption := 'Credits';
  BuildCreditsTab(Tab);

  Tab := TTabSheet.Create(Pages);
  Tab.PageControl := Pages;
  Tab.Caption := 'Publishing';
  BuildPublishingTab(Tab);
end;

function TdlgComicInfoEditor.AddRow(AParent: TWinControl; ATop: integer;
  const ACaption: string; AHighlight: boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Left := LBL_LEFT;
  Result.Top := ATop + 3;
  Result.Caption := ACaption;
  if AHighlight then
    Result.Font.Style := [fsBold];
end;

function TdlgComicInfoEditor.AddEdit(AParent: TWinControl;
  ALeft, ATop, AWidth: integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := AWidth;
end;

function TdlgComicInfoEditor.AddSpin(AParent: TWinControl;
  ALeft, ATop, AWidth, AMin, AMax: integer): TSpinEdit;
begin
  Result := TSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := AWidth;
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.Value := 0;
end;

function TdlgComicInfoEditor.AddCombo(AParent: TWinControl;
  ALeft, ATop, AWidth: integer;
  const AItems: array of string): TComboBox;
var
  i: integer;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := AParent;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := AWidth;
  Result.Style := csDropDownList;
  for i := 0 to High(AItems) do
    Result.Items.Add(AItems[i]);
  Result.ItemIndex := 0;
end;

function TdlgComicInfoEditor.AddMemo(AParent: TWinControl;
  ALeft, ATop, AWidth, AHeight: integer): TMemo;
begin
  Result := TMemo.Create(Self);
  Result.Parent := AParent;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.ScrollBars := ssVertical;
  Result.WordWrap := True;
end;

procedure TdlgComicInfoEditor.BuildGeneralTab(ATab: TTabSheet);
var
  Y: integer;
  Scroll: TScrollBox;
begin
  Scroll := TScrollBox.Create(Self);
  Scroll.Parent := ATab;
  Scroll.Align := alClient;
  Scroll.BorderStyle := bsNone;
  Scroll.HorzScrollBar.Visible := False;

  Y := 12;
  AddRow(Scroll, Y, 'Series', True);
  EdSeries := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Number', True);
  EdNumber := AddEdit(Scroll, ED_LEFT, Y, ED_HALF);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Title', False);
  EdTitle := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Volume', False);
  SpVolume := AddSpin(Scroll, ED_LEFT, Y, ED_HALF, 0, 9999);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Count', False);
  SpCount := AddSpin(Scroll, ED_LEFT, Y, ED_HALF, 0, 9999);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Alternate series', False);
  EdAltSeries := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Alternate number', False);
  EdAltNumber := AddEdit(Scroll, ED_LEFT, Y, ED_HALF);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Alternate count', False);
  SpAltCount := AddSpin(Scroll, ED_LEFT, Y, ED_HALF, 0, 9999);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Format', False);
  EdFormat := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Page count', True);
  SpPageCount := AddSpin(Scroll, ED_LEFT, Y, ED_HALF, 0, 99999);
end;

procedure TdlgComicInfoEditor.BuildStoryTab(ATab: TTabSheet);
var
  Y: integer;
  Scroll: TScrollBox;
begin
  Scroll := TScrollBox.Create(Self);
  Scroll.Parent := ATab;
  Scroll.Align := alClient;
  Scroll.BorderStyle := bsNone;
  Scroll.HorzScrollBar.Visible := False;

  Y := 12;
  AddRow(Scroll, Y, 'Summary', True);
  MemoSummary := AddMemo(Scroll, ED_LEFT, Y, ED_WIDTH, 80);
  Inc(Y, 88);

  AddRow(Scroll, Y, 'Notes', False);
  MemoNotes := AddMemo(Scroll, ED_LEFT, Y, ED_WIDTH, 60);
  Inc(Y, 68);

  AddRow(Scroll, Y, 'Genre', False);
  EdGenre := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Tags', False);
  EdTags := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Story arc', False);
  EdStoryArc := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Story arc number', False);
  EdStoryArcNumber := AddEdit(Scroll, ED_LEFT, Y, ED_HALF);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Series group', False);
  EdSeriesGroup := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Characters', False);
  EdCharacters := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Teams', False);
  EdTeams := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Locations', False);
  EdLocations := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
end;

procedure TdlgComicInfoEditor.BuildCreditsTab(ATab: TTabSheet);
var
  Y: integer;
  Scroll: TScrollBox;
begin
  Scroll := TScrollBox.Create(Self);
  Scroll.Parent := ATab;
  Scroll.Align := alClient;
  Scroll.BorderStyle := bsNone;
  Scroll.HorzScrollBar.Visible := False;

  Y := 12;
  AddRow(Scroll, Y, 'Writer', True);
  EdWriter := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Penciller', False);
  EdPenciller := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Inker', False);
  EdInker := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Colorist', False);
  EdColorist := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Letterer', False);
  EdLetterer := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Cover artist', False);
  EdCoverArtist := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Editor', False);
  EdEditor := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
end;

procedure TdlgComicInfoEditor.BuildPublishingTab(ATab: TTabSheet);
var
  Y: integer;
  Scroll: TScrollBox;
begin
  Scroll := TScrollBox.Create(Self);
  Scroll.Parent := ATab;
  Scroll.Align := alClient;
  Scroll.BorderStyle := bsNone;
  Scroll.HorzScrollBar.Visible := False;

  Y := 12;
  AddRow(Scroll, Y, 'Publisher', True);
  EdPublisher := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Imprint', False);
  EdImprint := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Year', True);
  SpYear := AddSpin(Scroll, ED_LEFT, Y, ED_HALF, 0, 2100);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Month', False);
  SpMonth := AddSpin(Scroll, ED_LEFT, Y, ED_HALF, 0, 12);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Day', False);
  SpDay := AddSpin(Scroll, ED_LEFT, Y, ED_HALF, 0, 31);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Web', False);
  EdWeb := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Language (ISO)', True);
  EdLanguageISO := AddEdit(Scroll, ED_LEFT, Y, ED_HALF);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Manga', True);
  CbManga := AddCombo(Scroll, ED_LEFT, Y, 180,
    ['', 'Unknown', 'Yes', 'No', 'YesAndRightToLeft']);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Black and white', False);
  CbBlackAndWhite := AddCombo(Scroll, ED_LEFT, Y, 180,
    ['', 'Unknown', 'Yes', 'No']);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Age rating', False);
  CbAgeRating := AddCombo(Scroll, ED_LEFT, Y, 220,
    ['', 'Unknown', 'Adults Only 18+', 'Early Childhood', 'Everyone',
     'Everyone 10+', 'G', 'Kids to Adults', 'M', 'MA15+', 'Mature 17+',
     'PG', 'R18+', 'Rating Pending', 'Teen', 'X18+']);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Scan information', False);
  EdScanInfo := AddEdit(Scroll, ED_LEFT, Y, ED_WIDTH);
  Inc(Y, ROW_H);

  AddRow(Scroll, Y, 'Community rating', False);
  SpCommunityRating := TFloatSpinEdit.Create(Self);
  SpCommunityRating.Parent := Scroll;
  SpCommunityRating.Left := ED_LEFT;
  SpCommunityRating.Top := Y;
  SpCommunityRating.Width := ED_HALF;
  SpCommunityRating.MinValue := 0;
  SpCommunityRating.MaxValue := 5;
  SpCommunityRating.DecimalPlaces := 1;
  SpCommunityRating.Increment := 0.5;
  SpCommunityRating.Value := 0;
end;

procedure TdlgComicInfoEditor.DataToUI;

  procedure SetCombo(ACb: TComboBox; const AVal: string);
  var
    Idx: integer;
  begin
    Idx := ACb.Items.IndexOf(AVal);
    if Idx >= 0 then
      ACb.ItemIndex := Idx
    else
      ACb.ItemIndex := 0;
  end;

  procedure SetSpin(ASp: TSpinEdit; AVal: integer);
  begin
    if AVal >= 0 then
      ASp.Value := AVal
    else
      ASp.Value := 0;
  end;

begin
  EdSeries.Text := FData.Series;
  EdNumber.Text := FData.Number;
  EdTitle.Text := FData.Title;
  SetSpin(SpVolume, FData.Volume);
  SetSpin(SpCount, FData.Count);
  EdAltSeries.Text := FData.AlternateSeries;
  EdAltNumber.Text := FData.AlternateNumber;
  SetSpin(SpAltCount, FData.AlternateCount);
  EdFormat.Text := FData.Format;
  SetSpin(SpPageCount, FData.PageCount);

  MemoSummary.Text := FData.Summary;
  MemoNotes.Text := FData.Notes;
  EdGenre.Text := FData.Genre;
  EdTags.Text := FData.Tags;
  EdStoryArc.Text := FData.StoryArc;
  EdStoryArcNumber.Text := FData.StoryArcNumber;
  EdSeriesGroup.Text := FData.SeriesGroup;
  EdCharacters.Text := FData.Characters;
  EdTeams.Text := FData.Teams;
  EdLocations.Text := FData.Locations;

  EdWriter.Text := FData.Writer;
  EdPenciller.Text := FData.Penciller;
  EdInker.Text := FData.Inker;
  EdColorist.Text := FData.Colorist;
  EdLetterer.Text := FData.Letterer;
  EdCoverArtist.Text := FData.CoverArtist;
  EdEditor.Text := FData.Editor;

  EdPublisher.Text := FData.Publisher;
  EdImprint.Text := FData.Imprint;
  SetSpin(SpYear, FData.Year);
  SetSpin(SpMonth, FData.Month);
  SetSpin(SpDay, FData.Day);
  EdWeb.Text := FData.Web;
  EdLanguageISO.Text := FData.LanguageISO;
  SetCombo(CbManga, FData.Manga);
  SetCombo(CbBlackAndWhite, FData.BlackAndWhite);
  SetCombo(CbAgeRating, FData.AgeRating);
  EdScanInfo.Text := FData.ScanInformation;

  if FData.CommunityRating >= 0 then
    SpCommunityRating.Value := FData.CommunityRating
  else
    SpCommunityRating.Value := 0;
end;

procedure TdlgComicInfoEditor.UIToData;

  function SpinToInt(ASp: TSpinEdit): integer;
  begin
    if ASp.Value > 0 then
      Result := ASp.Value
    else
      Result := -1;
  end;

  function ComboVal(ACb: TComboBox): string;
  begin
    if ACb.ItemIndex > 0 then
      Result := ACb.Items[ACb.ItemIndex]
    else
      Result := '';
  end;

begin
  FData.Series := Trim(EdSeries.Text);
  FData.Number := Trim(EdNumber.Text);
  FData.Title := Trim(EdTitle.Text);
  FData.Volume := SpinToInt(SpVolume);
  FData.Count := SpinToInt(SpCount);
  FData.AlternateSeries := Trim(EdAltSeries.Text);
  FData.AlternateNumber := Trim(EdAltNumber.Text);
  FData.AlternateCount := SpinToInt(SpAltCount);
  FData.Format := Trim(EdFormat.Text);
  FData.PageCount := SpinToInt(SpPageCount);

  FData.Summary := Trim(MemoSummary.Text);
  FData.Notes := Trim(MemoNotes.Text);
  FData.Genre := Trim(EdGenre.Text);
  FData.Tags := Trim(EdTags.Text);
  FData.StoryArc := Trim(EdStoryArc.Text);
  FData.StoryArcNumber := Trim(EdStoryArcNumber.Text);
  FData.SeriesGroup := Trim(EdSeriesGroup.Text);
  FData.Characters := Trim(EdCharacters.Text);
  FData.Teams := Trim(EdTeams.Text);
  FData.Locations := Trim(EdLocations.Text);

  FData.Writer := Trim(EdWriter.Text);
  FData.Penciller := Trim(EdPenciller.Text);
  FData.Inker := Trim(EdInker.Text);
  FData.Colorist := Trim(EdColorist.Text);
  FData.Letterer := Trim(EdLetterer.Text);
  FData.CoverArtist := Trim(EdCoverArtist.Text);
  FData.Editor := Trim(EdEditor.Text);

  FData.Publisher := Trim(EdPublisher.Text);
  FData.Imprint := Trim(EdImprint.Text);
  FData.Year := SpinToInt(SpYear);
  FData.Month := SpinToInt(SpMonth);
  FData.Day := SpinToInt(SpDay);
  FData.Web := Trim(EdWeb.Text);
  FData.LanguageISO := Trim(EdLanguageISO.Text);
  FData.Manga := ComboVal(CbManga);
  FData.BlackAndWhite := ComboVal(CbBlackAndWhite);
  FData.AgeRating := ComboVal(CbAgeRating);
  FData.ScanInformation := Trim(EdScanInfo.Text);

  if SpCommunityRating.Value > 0 then
    FData.CommunityRating := SpCommunityRating.Value
  else
    FData.CommunityRating := -1.0;
end;

procedure TdlgComicInfoEditor.BtnRemoveClick(Sender: TObject);
begin
  if MessageDlg('Remove ComicInfo.xml',
    'Remove ComicInfo.xml from this file?',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FRemoved := True;
    ModalResult := mrOK;
  end;
end;

function TdlgComicInfoEditor.GetBackup: boolean;
begin
  Result := CbBackup.Checked;
end;

procedure TdlgComicInfoEditor.LoadFile(const AFilePath, AFileName: string;
  const ASeriesName: string; APageCount: integer);
var
  BaseName: string;
  n, ChNum, Err: integer;
  NumStr: string;
  Entries: TZipEntries;
  i: integer;
  HasXML: boolean;
begin
  FFilePath := AFilePath;
  FFileName := AFileName;
  FRemoved := False;
  Caption := 'Manage ComicInfo.xml - ' + ChangeFileExt(AFileName, '');

  HasXML := False;
  try
    Entries := CollectZipEntries(AFilePath);
    try
      for i := 0 to High(Entries) do
        if SameText(Entries[i].Name, COMICINFO_XML) then
        begin
          HasXML := True;
          Entries[i].Data.Position := 0;
          Break;
        end;
    finally
      FreeZipEntries(Entries);
    end;
  except
  end;

  FExistingLoaded := HasXML;
  BtnRemove.Enabled := HasXML;

  if HasXML then
  begin
    try
      FData := ReadComicInfoFromCBZ(AFilePath);
    except
      FData := DefaultComicInfo;
    end;
  end
  else
  begin
    FData := DefaultComicInfo;

    if ASeriesName <> '' then
      FData.Series := ASeriesName;

    BaseName := ChangeFileExt(AFileName, '');
    n := RPos(' -', BaseName);
    if n > 0 then
    begin
      NumStr := Trim(Copy(BaseName, n + 2, Length(BaseName)));
      Val(NumStr, ChNum, Err);
      if (Err = 0) and (ChNum > 0) then
        FData.Number := IntToStr(ChNum);
    end;

    if APageCount > 0 then
      FData.PageCount := APageCount;
  end;

  DataToUI;
end;

function TdlgComicInfoEditor.GetData: TComicInfo;
begin
  UIToData;
  Result := FData;
end;

end.
