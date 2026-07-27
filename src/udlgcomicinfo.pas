unit udlgcomicinfo;

{$mode ObjFPC}{$H+}

{
  udlgcomicinfo.pas - ComicInfo Metadata Management Dialog

  Provides TdlgComicInfo, a dialog that scans comic archives (CBZ/CBR) for
  embedded ComicInfo.xml metadata and lets the user selectively remove it.
  Files are listed with their metadata status (Present / Absent / Error) and
  can be individually checked for removal. An optional backup of each archive
  can be created before the metadata is stripped.
}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ExtCtrls;

type

  { TdlgComicInfo - Dialog for inspecting and removing ComicInfo.xml metadata
    from comic archives. Displays scan results in a list view with a status
    column and checkboxes. Files whose metadata is "Present" are pre-checked.

    Fields:
      FDir   - base directory that contains the scanned files
      FFiles - array of file names being managed by this dialog }

  TdlgComicInfo = class(TForm)
    BtnRemove: TButton;
    BtnClose: TButton;
    CbBackup: TCheckBox;
    LVFiles: TListView;
    PanelBottom: TPanel;
    procedure BtnRemoveClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FDir: string;
    FFiles: TStringArray;
  public
    procedure ScanFiles(const AFiles: TStringArray; const ADir: string);
  end;

implementation

uses
  uservicecomicinfo,
  uLog;

{$R *.lfm}

{ TdlgComicInfo }

{ Initialise the dialog: clear the list view so it starts empty. }
procedure TdlgComicInfo.FormCreate(Sender: TObject);
begin
  LVFiles.Clear;
end;

{ Scan every file in AFiles for ComicInfo.xml metadata and populate the
  list view with the outcome.

  Parameters:
    AFiles - array of file names (relative paths) to scan
    ADir   - base directory that contains the files

  Each row receives a status of "Present" (metadata found, pre-checked),
  "Absent" (no metadata, not checked), or "Error" (scan failed, not checked). }
procedure TdlgComicInfo.ScanFiles(const AFiles: TStringArray;
  const ADir: string);
var
  i: integer;
  It: TListItem;
  Results: TComicInfoResults;
begin
  FDir := ADir;
  FFiles := AFiles;
  Results := TComicInfoService.Scan(AFiles, ADir);
  // BeginUpdate / EndUpdate pair avoids flicker while rebuilding the list
  LVFiles.BeginUpdate;
  try
    LVFiles.Items.Clear;
    for i := 0 to High(Results) do
    begin
      It := LVFiles.Items.Add;
      It.Caption := Results[i].FileName;
      if Results[i].Error <> '' then
      begin
        It.SubItems.Add('Error');
        It.Checked := False;
      end
      else if Results[i].HasComicInfo then
      begin
        It.SubItems.Add('Present');
        It.Checked := True;
      end
      else
      begin
        It.SubItems.Add('Absent');
        It.Checked := False;
      end;
    end;
  finally
    LVFiles.EndUpdate;
  end;
end;

{ Remove ComicInfo.xml from every checked file in the list view.
  Collects the checked items, delegates to TComicInfoService.Remove
  (optionally creating backups via CbBackup), then rescans the list.
  If at least one file was successfully stripped, ModalResult is set
  to mrOk so the caller knows the directory may need a refresh. }
procedure TdlgComicInfo.BtnRemoveClick(Sender: TObject);
var
  i, Removed: integer;
  ToRemove: TStringArray;
  Results: TComicInfoResults;
begin
  // Build the list of checked file names to remove metadata from
  ToRemove := nil;
  for i := 0 to LVFiles.Items.Count - 1 do
    if LVFiles.Items[i].Checked then
    begin
      SetLength(ToRemove, Length(ToRemove) + 1);
      ToRemove[High(ToRemove)] := LVFiles.Items[i].Caption;
    end;

  if Length(ToRemove) = 0 then Exit;

  Results := TComicInfoService.Remove(ToRemove, FDir, CbBackup.Checked);
  // Tally how many removals actually succeeded
  Removed := 0;
  for i := 0 to High(Results) do
    if Results[i].Removed then
      Inc(Removed);

  // Refresh the list view to reflect the new state after removal
  ScanFiles(FFiles, FDir);
  if Removed > 0 then
    ModalResult := mrOk;
end;

end.
