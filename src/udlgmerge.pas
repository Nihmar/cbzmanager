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
    { Highest volume number already present in the directory; proposed
      volumes start one after it (0 when the series has no volumes yet). }
    FLastVolume: integer;
    { Series name the merge operates on — the name passed to LoadChapters.
      Volume files are named "<SeriesName> VNNN.cbz" after it. }
    FSeriesName: string;
    { Auto-calculated chapters-per-volume as a REAL value (Python reference
      semantics, e.g. 3.75), fallbacked to DEFAULT_CHAPTERS_PER_VOLUME when
      incalculable.  Drives the volume-column preview when the user is not
      in manual CPV mode, so the preview matches the service's planning. }
    FAutoCPVF: Double;
    procedure RefreshVolumeColumn;
    function GetChaptersList: TIntArray;
    function GetGenerateComicInfo: boolean;
  protected
    procedure LoadSettings; override;
    procedure SaveSettings; override;
  public
    property ChaptersList: TIntArray read GetChaptersList;
    property GenerateComicInfo: boolean read GetGenerateComicInfo;
    property SeriesName: string read FSeriesName;
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
  end
  else
    { Back to auto: restore the spin to the auto-calculated value so the
      preview and the service agree.  FAutoCPVF is 0 before LoadChapters
      ran (LoadSettings can fire this handler during FormCreate). }
    if FAutoCPVF >= 1.0 then
      EditCPV.Value := Trunc(FAutoCPVF);
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
  i, j, VolNum, Consumed, SeqIdx, Count, TotalFull, BatchSize: integer;
  Seq: TIntArray;
  CPVF: Double;
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
      VolNum := FLastVolume + 1;
      Consumed := 0;
      SeqIdx := 0;
      for i := 0 to LVFiles.Items.Count - 1 do
      begin
        if SeqIdx <= High(Seq) then
        begin
          { A batch that does not fully fit the remaining rows is skipped
            entirely (the service breaks there too, matching the Python
            reference) — label the remaining rows as unassigned. }
          if Seq[SeqIdx] > LVFiles.Items.Count - i then
          begin
            for j := i to LVFiles.Items.Count - 1 do
              LVFiles.Items[j].SubItems[1] := '-';
            Break;
          end;
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
      { Mirrors the service's planning: manual CPV uses the spin's integer
        value; auto uses the float (Python reference) estimate, which can
        be fractional (e.g. 3.75 → 4 volumes of 3, leftovers unassigned).
        TotalFull is int(count / CPVF) — the Python reference's
        int(num_chapters / chapters_per_volume). }
      Count := LVFiles.Items.Count;
      if CbManualCPV.Checked then
      begin
        CPVF := EditCPV.Value;
        if CPVF < 1 then CPVF := 1;
      end
      else
      begin
        CPVF := FAutoCPVF;
        if CPVF < 1 then CPVF := 1;  { 0 before LoadChapters ran }
      end;
      BatchSize := Trunc(CPVF);
      if BatchSize < 1 then BatchSize := 1;
      TotalFull := Trunc(Count / CPVF);
      if CbForce.Checked then
      begin
        { Force: the last volume absorbs the leftovers.  When there are
          fewer chapters than CPV there are zero "full" volumes, but the
          merge still produces a single Vol.1, so clamp the label to 1. }
        if TotalFull < 1 then TotalFull := 1;
        for i := 0 to Count - 1 do
        begin
          if i < TotalFull * BatchSize then
            LVFiles.Items[i].SubItems[1] :=
              Format('Vol.%d', [FLastVolume + (i div BatchSize) + 1])
          else
            LVFiles.Items[i].SubItems[1] := Format('Vol.%d',
              [FLastVolume + TotalFull]);
        end;
      end
      else
      begin
        { Without Force: only full volumes — leftovers stay unassigned }
        for i := 0 to Count - 1 do
          if i < TotalFull * BatchSize then
            LVFiles.Items[i].SubItems[1] :=
              Format('Vol.%d', [FLastVolume + (i div BatchSize) + 1])
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
  Chapters: TChapterArray;
  MaxCh: integer;
begin
  FFiles := AFiles;
  FDir := ADir;
  FSeriesName := ASeriesName;
  FLastVolume := TMergeService.LastVolumeNumber(AFiles, ASeriesName);
  LblFolder.Caption := ExtractFileName(ExcludeTrailingPathDelimiter(ADir));

  { The merge list shows only the chapters of the detected series, sorted
    by chapter number (specials last).  Volume files and _OLD backups are
    excluded here and never participate in the merge. }
  Chapters := TMergeService.CollectChapters(AFiles, ASeriesName);
  MaxCh := 1;
  for i := 0 to High(Chapters) do
    if Chapters[i].Number > MaxCh then
      MaxCh := Chapters[i].Number;
  { Default range = everything, so a plain "Merge" click behaves like the
    Python reference, which always merges all chapters. }
  EditChapterEnd.Value := MaxCh;

  { Auto-fill the chapters-per-volume default from the existing volumes in
    the directory — but only when the user is not in manual CPV mode, so a
    remembered manual value (restored by LoadSettings) is preserved.  The
    REAL value (Python reference semantics, can be fractional) is kept in
    FAutoCPVF for the volume-column preview; the spin shows its integer
    part. }
  FAutoCPVF :=
    TMergeService.CalculateChaptersPerVolumeFloat(AFiles, ASeriesName);
  if FAutoCPVF < 1.0 then
    FAutoCPVF := DEFAULT_CHAPTERS_PER_VOLUME;
  if not CbManualCPV.Checked then
    EditCPV.Value := Trunc(FAutoCPVF);

  LVFiles.BeginUpdate;
  try
    LVFiles.Items.Clear;
    for i := 0 to High(Chapters) do
    begin
      It := LVFiles.Items.Add;
      It.Caption := IntToStr(i + 1);
      It.SubItems.Add(ExtractChapterNumStr(Chapters[i].FileName));
      if It.SubItems[0] = '' then
        It.SubItems[0] := ChangeFileExt(Chapters[i].FileName, '');
      It.SubItems.Add('');  // placeholder — filled by RefreshVolumeColumn below
    end;
  finally
    LVFiles.EndUpdate;
  end;
  RefreshVolumeColumn;
end;

end.
