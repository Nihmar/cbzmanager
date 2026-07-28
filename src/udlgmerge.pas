unit udlgmerge;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Spin, uservicemerge, uloaderthread, udlgbase, usettings;

type

  TdlgMerge = class(TSettingsDialog)
    procedure FormCreate(Sender: TObject);
  private
    BtnMerge: TButton;
    BtnClose: TButton;
    BtnBuildSeq: TButton;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    LblSeries: TLabel;
    LblFolder: TLabel;
    LblSeq: TLabel;
    LVFiles: TListView;
    PanelBottom: TPanel;
    PanelTop: TPanel;
    FFiles: TStringArray;
    FDir: string;
    FImages: TLazIntfImageList;
    procedure CbManualCPVChange(Sender: TObject);
    procedure CbForceChange(Sender: TObject);
    procedure CbCustomSeqChange(Sender: TObject);
    procedure BtnBuildSeqClick(Sender: TObject);
    procedure EditCPVChange(Sender: TObject);
    procedure EditChapterSeqChange(Sender: TObject);
    procedure RefreshVolumeColumn;
    function GetChaptersList: TIntArray;
    function GetGenerateComicInfo: boolean;
    procedure LoadSettings; override;
    procedure SaveSettings; override;
  public
    EditSeries: TEdit;
    EditChapterStart: TSpinEdit;
    EditChapterEnd: TSpinEdit;
    EditCPV: TSpinEdit;
    CbManualCPV: TCheckBox;
    CbCustomSeq: TCheckBox;
    EditChapterSeq: TEdit;
    CbForce: TCheckBox;
    CbDelete: TCheckBox;
    CbGenerateComicInfo: TCheckBox;
    property ChaptersList: TIntArray read GetChaptersList;
    property GenerateComicInfo: boolean read GetGenerateComicInfo;
    property Images: TLazIntfImageList read FImages write FImages;
    procedure LoadChapters(const AFiles: TStringArray; const ADir: string;
      const ASeriesName: string);
  end;

implementation

{$R *.lfm}

uses
  udlgseqbuilder;

{ TdlgMerge }

procedure TdlgMerge.FormCreate(Sender: TObject);
var
  Col: TListColumn;
begin
  InitDialogChrome(Self);

  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 192;  { room for folder label + shifted controls }
  PanelTop.BevelOuter := bvNone;

  LblSeries := TLabel.Create(Self);
  LblSeries.Parent := PanelTop;
  LblSeries.Left := 12;
  LblSeries.Top := 12;
  LblSeries.Caption := 'Series name';
  LblSeries.Font.Height := -13;
  LblSeries.Font.Style := [fsBold];

  EditSeries := TEdit.Create(Self);
  EditSeries.Parent := PanelTop;
  EditSeries.Left := 12;
  EditSeries.Top := 32;
  EditSeries.Width := 536;
  EditSeries.ReadOnly := True;

  LblFolder := TLabel.Create(Self);
  LblFolder.Parent := PanelTop;
  LblFolder.Left := 12;
  LblFolder.Top := 56;
  LblFolder.Font.Color := clGray;
  LblFolder.Font.Height := -11;
  LblFolder.Caption := '';

  Label1 := TLabel.Create(Self);
  Label1.Parent := PanelTop;
  Label1.Left := 12;
  Label1.Top := 76;
  Label1.Caption := 'Chapters from:';

  EditChapterStart := TSpinEdit.Create(Self);
  EditChapterStart.Parent := PanelTop;
  EditChapterStart.Left := 90;
  EditChapterStart.Top := 72;
  EditChapterStart.Width := 56;
  EditChapterStart.MinValue := 0;
  EditChapterStart.MaxValue := 9999;
  EditChapterStart.Value := 0;

  Label2 := TLabel.Create(Self);
  Label2.Parent := PanelTop;
  Label2.Left := 154;
  Label2.Top := 76;
  Label2.Caption := 'a:';

  EditChapterEnd := TSpinEdit.Create(Self);
  EditChapterEnd.Parent := PanelTop;
  EditChapterEnd.Left := 180;
  EditChapterEnd.Top := 72;
  EditChapterEnd.Width := 56;
  EditChapterEnd.MinValue := 1;
  EditChapterEnd.MaxValue := 9999;
  EditChapterEnd.Value := 1;

  Label3 := TLabel.Create(Self);
  Label3.Parent := PanelTop;
  Label3.Left := 260;
  Label3.Top := 76;
  Label3.Caption := 'Ch. per volume:';

  EditCPV := TSpinEdit.Create(Self);
  EditCPV.Parent := PanelTop;
  EditCPV.Left := 366;
  EditCPV.Top := 72;
  EditCPV.Width := 56;
  EditCPV.MinValue := 1;
  EditCPV.MaxValue := 999;
  EditCPV.Value := 7;
  EditCPV.OnChange := @EditCPVChange;

  CbManualCPV := TCheckBox.Create(Self);
  CbManualCPV.Parent := PanelTop;
  CbManualCPV.Left := 12;
  CbManualCPV.Top := 104;
  CbManualCPV.Width := 240;
  CbManualCPV.Caption := 'Set CPV manually';
  CbManualCPV.OnClick := @CbManualCPVChange;

  CbForce := TCheckBox.Create(Self);
  CbForce.Parent := PanelTop;
  CbForce.Left := 260;
  CbForce.Top := 104;
  CbForce.Width := 280;
  CbForce.Caption := 'Force extra chapters into last volume';
  CbForce.OnClick := @CbForceChange;

  CbCustomSeq := TCheckBox.Create(Self);
  CbCustomSeq.Parent := PanelTop;
  CbCustomSeq.Left := 12;
  CbCustomSeq.Top := 124;
  CbCustomSeq.Width := 160;
  CbCustomSeq.Caption := 'Custom sequence:';
  CbCustomSeq.OnClick := @CbCustomSeqChange;

  LblSeq := TLabel.Create(Self);
  LblSeq.Parent := PanelTop;
  LblSeq.Left := 178;
  LblSeq.Top := 128;
  LblSeq.Caption := 'e.g. 5,6,7,3';
  LblSeq.Enabled := False;

  EditChapterSeq := TEdit.Create(Self);
  EditChapterSeq.Parent := PanelTop;
  EditChapterSeq.Left := 260;
  EditChapterSeq.Top := 122;
  EditChapterSeq.Width := 196;
  EditChapterSeq.Enabled := False;
  EditChapterSeq.OnChange := @EditChapterSeqChange;

  BtnBuildSeq := TButton.Create(Self);
  BtnBuildSeq.Parent := PanelTop;
  BtnBuildSeq.Left := 462;
  BtnBuildSeq.Top := 120;
  BtnBuildSeq.Width := 80;
  BtnBuildSeq.Height := 26;
  BtnBuildSeq.Caption := '&Build...';
  BtnBuildSeq.Enabled := False;
  BtnBuildSeq.OnClick := @BtnBuildSeqClick;

  CbGenerateComicInfo := TCheckBox.Create(Self);
  CbGenerateComicInfo.Parent := PanelTop;
  CbGenerateComicInfo.Left := 12;
  CbGenerateComicInfo.Top := 152;
  CbGenerateComicInfo.Width := 280;
  CbGenerateComicInfo.Caption := 'Generate ComicInfo.xml per volume';
  CbGenerateComicInfo.Checked := True;

  PanelBottom := CreateBottomPanel(Self, 44);

  CbDelete := TCheckBox.Create(Self);
  CbDelete.Parent := PanelBottom;
  CbDelete.Left := 12;
  CbDelete.Top := 10;
  CbDelete.Width := 260;
  CbDelete.Caption := 'Permanently delete original chapters';

  BtnMerge := CreateDialogButton(PanelBottom, '&Merge', 388, 7, mrOK, True, False);
  BtnClose := CreateDialogButton(PanelBottom, '&Cancel', 476, 7, mrCancel,
    False, True);

  LVFiles := CreateReportListView(Self, False);

  Col := LVFiles.Columns.Add;
  Col.Caption := '#';
  Col.Width := 40;

  Col := LVFiles.Columns.Add;
  Col.Caption := 'Chapter file';
  Col.AutoSize := True;

  Col := LVFiles.Columns.Add;
  Col.Caption := 'Volume';
  Col.Width := 80;

  EditCPV.Enabled := False;

  InitSettingsPersistence;
end;

procedure TdlgMerge.LoadSettings;
begin
  CbForce.Checked := AppSettings.ReadBool('Merge', 'Force', False);
  CbDelete.Checked := AppSettings.ReadBool('Merge', 'Delete', False);
  CbGenerateComicInfo.Checked :=
    AppSettings.ReadBool('Merge', 'GenerateComicInfo', True);
  CbManualCPV.Checked := AppSettings.ReadBool('Merge', 'ManualCPV', False);
  EditCPV.Value := AppSettings.ReadInteger('Merge', 'CPV', 7);
  { Sync the CPV editor's enabled state without invoking the full change
    handler (which touches the volume column before chapters are loaded). }
  EditCPV.Enabled := CbManualCPV.Checked;
end;

procedure TdlgMerge.SaveSettings;
begin
  AppSettings.WriteBool('Merge', 'Force', CbForce.Checked);
  AppSettings.WriteBool('Merge', 'Delete', CbDelete.Checked);
  AppSettings.WriteBool('Merge', 'GenerateComicInfo',
    CbGenerateComicInfo.Checked);
  AppSettings.WriteBool('Merge', 'ManualCPV', CbManualCPV.Checked);
  AppSettings.WriteInteger('Merge', 'CPV', EditCPV.Value);
end;

procedure TdlgMerge.CbManualCPVChange(Sender: TObject);
begin
  if CbManualCPV.Checked then
  begin
    CbCustomSeq.Checked := False;
    EditChapterSeq.Enabled := False;
    LblSeq.Enabled := False;
    BtnBuildSeq.Enabled := False;
  end;
  EditCPV.Enabled := CbManualCPV.Checked;
  RefreshVolumeColumn;
end;

procedure TdlgMerge.CbForceChange(Sender: TObject);
begin
  RefreshVolumeColumn;
end;

procedure TdlgMerge.CbCustomSeqChange(Sender: TObject);
begin
  if CbCustomSeq.Checked then
  begin
    CbManualCPV.Checked := False;
    EditCPV.Enabled := False;
  end;
  EditChapterSeq.Enabled := CbCustomSeq.Checked;
  LblSeq.Enabled := CbCustomSeq.Checked;
  BtnBuildSeq.Enabled := CbCustomSeq.Checked;
  RefreshVolumeColumn;
end;

procedure TdlgMerge.BtnBuildSeqClick(Sender: TObject);
var
  Builder: TdlgSeqBuilder;
  Seq: TIntArray;
  i: integer;
  S: string;
begin
  if FImages = nil then Exit;

  Builder := TdlgSeqBuilder.Create(Self);
  try
    Builder.LoadChapters(FFiles, FImages, FDir);
    if Builder.ShowModal = mrOK then
    begin
      Seq := Builder.GetSequence;
      if Length(Seq) > 0 then
      begin
        S := '';
        for i := 0 to High(Seq) do
        begin
          if S <> '' then S := S + ',';
          S := S + IntToStr(Seq[i]);
        end;
        EditChapterSeq.Text := S;
        CbCustomSeq.Checked := True;
        EditChapterSeq.Enabled := True;
        LblSeq.Enabled := True;
        CbManualCPV.Checked := False;
        EditCPV.Enabled := False;
        RefreshVolumeColumn;
      end;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TdlgMerge.EditCPVChange(Sender: TObject);
begin
  if CbManualCPV.Checked then
    RefreshVolumeColumn;
end;

procedure TdlgMerge.EditChapterSeqChange(Sender: TObject);
begin
  if CbCustomSeq.Checked then
    RefreshVolumeColumn;
end;

function TdlgMerge.GetChaptersList: TIntArray;
var
  Parts: TStringArray;
  i, V, Err: integer;
  S: string;
begin
  Result := nil;
  if not CbCustomSeq.Checked then Exit;
  S := Trim(EditChapterSeq.Text);
  if S = '' then Exit;
  Parts := S.Split([',', ';']);
  for i := 0 to High(Parts) do
  begin
    Val(Trim(Parts[i]), V, Err);
    if (Err = 0) and (V > 0) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := V;
    end;
  end;
end;

function TdlgMerge.GetGenerateComicInfo: boolean;
begin
  Result := CbGenerateComicInfo.Checked;
end;

procedure TdlgMerge.RefreshVolumeColumn;
var
  i, VolNum, Consumed, SeqIdx: integer;
  Seq: TIntArray;
  CPV: integer;
begin
  LVFiles.BeginUpdate;
  try
    if CbCustomSeq.Checked then
    begin
      Seq := GetChaptersList;
      if Length(Seq) = 0 then
      begin
        for i := 0 to LVFiles.Items.Count - 1 do
          LVFiles.Items[i].SubItems[1] := '?';
        Exit;
      end;
      VolNum := 1;
      Consumed := 0;
      SeqIdx := 0;
      for i := 0 to LVFiles.Items.Count - 1 do
      begin
        if SeqIdx <= High(Seq) then
        begin
          LVFiles.Items[i].SubItems[1] := Format('Vol.%d', [VolNum]);
          Inc(Consumed);
          if Consumed >= Seq[SeqIdx] then
          begin
            Inc(VolNum);
            Inc(SeqIdx);
            Consumed := 0;
          end;
        end
        else
          LVFiles.Items[i].SubItems[1] := '-';
      end;
    end
    else
    begin
      CPV := EditCPV.Value;
      if CPV < 1 then CPV := 1;
      if CbForce.Checked then
      begin
        { Force: last volume absorbs the leftovers }
        for i := 0 to LVFiles.Items.Count - 1 do
        begin
          if i < (LVFiles.Items.Count div CPV) * CPV then
            LVFiles.Items[i].SubItems[1] := Format('Vol.%d', [(i div CPV) + 1])
          else
            LVFiles.Items[i].SubItems[1] := Format('Vol.%d', [(LVFiles.Items.Count div CPV)]);
        end;
      end
      else
      begin
        { Without Force: only full volumes — leftovers stay unassigned }
        for i := 0 to LVFiles.Items.Count - 1 do
          if i < (LVFiles.Items.Count div CPV) * CPV then
            LVFiles.Items[i].SubItems[1] := Format('Vol.%d', [(i div CPV) + 1])
          else
            LVFiles.Items[i].SubItems[1] := '-';
      end;
    end;
  finally
    LVFiles.EndUpdate;
  end;
end;

procedure TdlgMerge.LoadChapters(const AFiles: TStringArray;
  const ADir: string; const ASeriesName: string);
var
  i: integer;
  It: TListItem;
  AutoCPV: integer;
begin
  FFiles := AFiles;
  FDir := ADir;
  EditSeries.Text := ASeriesName;
  LblFolder.Caption := ExtractFileName(ExcludeTrailingPathDelimiter(ADir));
  EditChapterEnd.Value := Length(AFiles);

  { Auto-fill the chapters-per-volume default from the existing volumes in the
    directory — but only when the user is not in manual CPV mode, so a
    remembered manual value (restored by LoadSettings) is preserved. }
  if not CbManualCPV.Checked then
  begin
    AutoCPV := TMergeService.CalculateChaptersPerVolume(AFiles, ASeriesName);
    if AutoCPV >= 1 then
      EditCPV.Value := AutoCPV
    else
      EditCPV.Value := 7;
  end;

  LVFiles.BeginUpdate;
  try
    LVFiles.Items.Clear;
    for i := 0 to High(AFiles) do
    begin
      It := LVFiles.Items.Add;
      It.Caption := IntToStr(i + 1);
      It.SubItems.Add(ExtractChapterNumStr(AFiles[i]));
      if It.SubItems[0] = '' then
        It.SubItems[0] := ChangeFileExt(AFiles[i], '');
      It.SubItems.Add('');  // placeholder — filled by RefreshVolumeColumn below
    end;
  finally
    LVFiles.EndUpdate;
  end;
  RefreshVolumeColumn;
end;

end.
