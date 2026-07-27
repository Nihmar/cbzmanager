unit udlgmerge;

{$mode ObjFPC}{$H+}

{
  udlgmerge.pas - Chapter Merge Dialog

  Provides TdlgMerge, a dialog that helps the user merge a sequence of comic
  chapter files (CBZ/CBR) into larger volume archives. Chapters are displayed
  in a list view with their assigned volume number. The user can control the
  chapters-per-volume (CPV) count — either auto-detected from existing volumes
  or set manually — as well as chapter range, deletion of originals after
  merge, and forced overwrite of existing targets.
}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Spin;

type

  { TdlgMerge - Dialog for merging comic chapter files into volumes.

    The list view shows each chapter with its index, file name, and which
    volume it will be placed into (computed from the CPV setting).

    Fields:
      FFiles - array of chapter file names to merge
      FDir   - base directory containing the chapter files }

  TdlgMerge = class(TForm)
    BtnMerge: TButton;
    BtnClose: TButton;
    CbForce: TCheckBox;
    CbDelete: TCheckBox;
    CbManualCPV: TCheckBox;
    EditSeries: TEdit;
    EditChapterStart: TSpinEdit;
    EditChapterEnd: TSpinEdit;
    EditCPV: TSpinEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    LblSeries: TLabel;
    LVFiles: TListView;
    PanelBottom: TPanel;
    PanelTop: TPanel;
    procedure CbManualCPVChange(Sender: TObject);
    procedure EditCPVChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FFiles: TStringArray;
    FDir: string;
    procedure RefreshVolumeColumn;
  public
    procedure LoadChapters(const AFiles: TStringArray; const ADir: string;
      const ASeriesName: string);
  end;

implementation

uses
  uservicemerge;

{$R *.lfm}

{ TdlgMerge }

{ Initialise the dialog with default values:
  - Manual CPV editing is disabled until the user opts in.
  - Default CPV is 7 chapters per volume.
  - Chapter range defaults to [1 .. 1] (will be adjusted in LoadChapters). }
procedure TdlgMerge.FormCreate(Sender: TObject);
begin
  EditCPV.Enabled := False;
  EditCPV.Value := 7;
  EditChapterStart.Value := 1;
  EditChapterEnd.Value := 1;
end;

{ When the manual CPV checkbox is toggled, enable or disable the CPV spin
  edit. If the user just turned manual mode on, immediately refresh the
  volume column so the custom CPV takes effect. }
procedure TdlgMerge.CbManualCPVChange(Sender: TObject);
begin
  EditCPV.Enabled := CbManualCPV.Checked;
  if CbManualCPV.Checked then
    RefreshVolumeColumn;
end;

{ When the CPV spin edit value changes, refresh the volume column if the
  user is in manual-CPV mode (otherwise the auto CPV controls the display). }
procedure TdlgMerge.EditCPVChange(Sender: TObject);
begin
  if CbManualCPV.Checked then
    RefreshVolumeColumn;
end;

{ Recompute and rewrite the "Vol.X" sub-item for every row in the list view
  based on the current CPV spin-edit value. Row i (0-based) is assigned to
  volume (i div CPV) + 1. Clamps CPV to a minimum of 1 to avoid division
  by zero. }
procedure TdlgMerge.RefreshVolumeColumn;
var
  i, CPV: integer;
begin
  CPV := EditCPV.Value;
  if CPV < 1 then CPV := 1;   // guard against zero or negative CPV
  LVFiles.BeginUpdate;
  try
    for i := 0 to LVFiles.Items.Count - 1 do
      LVFiles.Items[i].SubItems[1] := Format('Vol.%d', [(i div CPV) + 1]);
  finally
    LVFiles.EndUpdate;
  end;
end;

{ Populate the dialog with a list of chapter files and prepare merge settings.

  Parameters:
    AFiles      - array of chapter file names
    ADir        - base directory containing the files
    ASeriesName - series name, pre-filled into the series edit box

  The chapter-end spin edit is set to the total file count. An automatic
  chapters-per-volume value is computed from any existing volumes via
  TMergeService.CalculateChaptersPerVolume; if none can be inferred the
  CPV defaults to 7.

  The list view is rebuilt: column 0 = 1-based index, column 1 = file name
  (without extension), column 2 = assigned volume label. }
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
  EditChapterEnd.Value := Length(AFiles);

  // Try to guess a sensible CPV from existing volume files
  AutoCPV := TMergeService.CalculateChaptersPerVolume(AFiles, ASeriesName);
  if AutoCPV >= 1 then
    EditCPV.Value := AutoCPV
  else
    EditCPV.Value := 7;

  // Populate the list view: index | name | volume
  LVFiles.BeginUpdate;
  try
    LVFiles.Items.Clear;
    for i := 0 to High(AFiles) do
    begin
      It := LVFiles.Items.Add;
      It.Caption := IntToStr(i + 1);
      It.SubItems.Add(ChangeFileExt(AFiles[i], ''));
      It.SubItems.Add(Format('Vol.%d', [(i div EditCPV.Value) + 1]));
    end;
  finally
    LVFiles.EndUpdate;
  end;
end;

end.
