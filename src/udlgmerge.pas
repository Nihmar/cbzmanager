unit udlgmerge;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Spin, uservicemerge, uloaderthread, udlgbase, usettings;

type

  { TdlgMerge }

  TdlgMerge = class(TSettingsDialog)
    BtnBuildSeq: TButton;
    BtnClose: TButton;
    BtnMerge: TButton;
    CbForce: TCheckBox;
    CbGenerateComicInfo: TCheckBox;
    CbDelete: TCheckBox;
    CbCustomSeq: TCheckBox;
    CbManualCPV: TCheckBox;
    EditChapterEnd: TSpinEdit;
    EditChapterStart: TSpinEdit;
    EditCPV: TSpinEdit;
    GBSource: TGroupBox;
    GBVolumes: TGroupBox;
    GBOutput: TGroupBox;
    LblChaptersFrom: TLabel;
    LblChaptersTo: TLabel;
    LblCPV: TLabel;
    MemoChapterSequence: TMemo;
    PanelCPV: TPanel;
    PanelCustomMergeTop: TPanel;
    PanelCustomMerge: TPanel;
    PanelRight: TPanel;
    PanelBottom: TPanel;
    PanelLeft: TPanel;
    LblFolder: TLabel;
    procedure BtnBuildSeqClick(Sender: TObject);  
    procedure CbCustomSeqChange(Sender: TObject);
    procedure CbForceChange(Sender: TObject);
    procedure CbManualCPVChange(Sender: TObject);
    procedure EditCPVChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure MemoChapterSequenceChange(Sender: TObject);
  private
    LVFiles: TListView;
    FFiles: TStringArray;
    FDir: string;
    FImages: TLazIntfImageList;
    procedure RefreshVolumeColumn;
    function GetChaptersList: TIntArray;
    function GetGenerateComicInfo: boolean;
  protected
    procedure LoadSettings; override;
    procedure SaveSettings; override;
  public
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
  LVFiles := CreateReportListView(PanelRight, False);

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
  BtnBuildSeq.Enabled := False;

  InitSettingsPersistence;
end;

procedure TdlgMerge.MemoChapterSequenceChange(Sender: TObject);
begin
  if CbCustomSeq.Checked then
    RefreshVolumeColumn;
end;

procedure TdlgMerge.EditCPVChange(Sender: TObject);
begin
  if CbManualCPV.Checked then
    RefreshVolumeColumn;
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
    MemoChapterSequence.Enabled := False;
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
  MemoChapterSequence.Enabled := CbCustomSeq.Checked;
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
    if Builder.ShowModal = mrOk then
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
        MemoChapterSequence.Text := S;
        CbCustomSeq.Checked := True;
        MemoChapterSequence.Enabled := True;
        CbManualCPV.Checked := False;
        EditCPV.Enabled := False;
        RefreshVolumeColumn;
      end;
    end;
  finally
    Builder.Free;
  end;
end;

function TdlgMerge.GetChaptersList: TIntArray;
var
  Parts: TStringArray;
  i, V, Err: integer;
  S: string;
begin
  Result := nil;
  if not CbCustomSeq.Checked then Exit;
  S := Trim(MemoChapterSequence.Text);
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
  CPV, FullVols: integer;
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
        { Force: last volume absorbs the leftovers.  When there are fewer
          chapters than CPV there are zero "full" volumes, but the merge
          still produces a single Vol.1, so clamp the leftover label to 1. }
        FullVols := LVFiles.Items.Count div CPV;
        if FullVols < 1 then FullVols := 1;
        for i := 0 to LVFiles.Items.Count - 1 do
        begin
          if i < (LVFiles.Items.Count div CPV) * CPV then
            LVFiles.Items[i].SubItems[1] := Format('Vol.%d', [(i div CPV) + 1])
          else
            LVFiles.Items[i].SubItems[1] := Format('Vol.%d', [FullVols]);
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
