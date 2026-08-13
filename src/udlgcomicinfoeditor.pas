unit udlgcomicinfoeditor;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Spin, ucomicinfo;

type
  TdlgComicInfoEditor = class(TForm)
    { Wired from the .lfm — controls and event handlers must be published
      for RTTI lookup. }
    Pages: TPageControl;
    PanelBottom: TPanel;
    CbBackup: TCheckBox;
    BtnRemove: TButton;
    BtnSave: TButton;
    BtnCancel: TButton;
    TabGeneral: TTabSheet;
    ScrollGeneral: TScrollBox;
    LblSeries: TLabel;
    EdSeries: TEdit;
    LblNumber: TLabel;
    EdNumber: TEdit;
    LblTitle: TLabel;
    EdTitle: TEdit;
    LblVolume: TLabel;
    SpVolume: TSpinEdit;
    LblCount: TLabel;
    SpCount: TSpinEdit;
    LblAltSeries: TLabel;
    EdAltSeries: TEdit;
    LblAltNumber: TLabel;
    EdAltNumber: TEdit;
    LblAltCount: TLabel;
    SpAltCount: TSpinEdit;
    LblFormat: TLabel;
    EdFormat: TEdit;
    LblPageCount: TLabel;
    SpPageCount: TSpinEdit;
    TabStory: TTabSheet;
    ScrollStory: TScrollBox;
    LblSummary: TLabel;
    MemoSummary: TMemo;
    LblNotes: TLabel;
    MemoNotes: TMemo;
    LblGenre: TLabel;
    EdGenre: TEdit;
    LblTags: TLabel;
    EdTags: TEdit;
    LblStoryArc: TLabel;
    EdStoryArc: TEdit;
    LblStoryArcNumber: TLabel;
    EdStoryArcNumber: TEdit;
    LblSeriesGroup: TLabel;
    EdSeriesGroup: TEdit;
    LblCharacters: TLabel;
    EdCharacters: TEdit;
    LblTeams: TLabel;
    EdTeams: TEdit;
    LblLocations: TLabel;
    EdLocations: TEdit;
    TabCredits: TTabSheet;
    ScrollCredits: TScrollBox;
    LblWriter: TLabel;
    EdWriter: TEdit;
    LblPenciller: TLabel;
    EdPenciller: TEdit;
    LblInker: TLabel;
    EdInker: TEdit;
    LblColorist: TLabel;
    EdColorist: TEdit;
    LblLetterer: TLabel;
    EdLetterer: TEdit;
    LblCoverArtist: TLabel;
    EdCoverArtist: TEdit;
    LblEditor: TLabel;
    EdEditor: TEdit;
    TabPublishing: TTabSheet;
    ScrollPublishing: TScrollBox;
    LblPublisher: TLabel;
    EdPublisher: TEdit;
    LblImprint: TLabel;
    EdImprint: TEdit;
    LblYear: TLabel;
    SpYear: TSpinEdit;
    LblMonth: TLabel;
    SpMonth: TSpinEdit;
    LblDay: TLabel;
    SpDay: TSpinEdit;
    LblWeb: TLabel;
    EdWeb: TEdit;
    LblLanguageISO: TLabel;
    EdLanguageISO: TEdit;
    LblManga: TLabel;
    CbManga: TComboBox;
    LblBlackAndWhite: TLabel;
    CbBlackAndWhite: TComboBox;
    LblAgeRating: TLabel;
    CbAgeRating: TComboBox;
    LblScanInfo: TLabel;
    EdScanInfo: TEdit;
    LblCommunityRating: TLabel;
    SpCommunityRating: TFloatSpinEdit;
    procedure BtnRemoveClick(Sender: TObject);
  private
    FData: TComicInfo;
    FFilePath: string;
    FFileName: string;
    FExistingLoaded: boolean;
    FRemoved: boolean;
    function GetBackup: boolean;
    procedure DataToUI;
    procedure UIToData;
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
  uzipcore, uLog;

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
  HasXML: boolean;
begin
  FFilePath := AFilePath;
  FFileName := AFileName;
  FRemoved := False;
  Caption := 'Manage ComicInfo.xml - ' + ChangeFileExt(AFileName, '');

  { Open the archive once: detect ComicInfo.xml and, if present, parse it
    from the same collected entries instead of re-opening the CBZ. }
  HasXML := False;
  FData := DefaultComicInfo;
  try
    Entries := CollectZipEntries(AFilePath);
    try
      HasXML := FindComicInfoIndex(Entries) >= 0;
      if HasXML then
        FData := ReadComicInfoFromEntries(Entries);
    finally
      FreeZipEntries(Entries);
    end;
  except
    on E: Exception do
    begin
      Log('ComicInfoEditor: could not inspect %s: %s', [AFilePath, E.Message]);
      HasXML := False;
      FData := DefaultComicInfo;
    end;
  end;

  FExistingLoaded := HasXML;
  BtnRemove.Enabled := HasXML;

  if not HasXML then
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
