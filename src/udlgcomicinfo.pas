unit udlgcomicinfo;

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Forms,
  Controls,
  Graphics,
  Dialogs,
  StdCtrls,
  ComCtrls,
  ExtCtrls,
  Spin,
  udlgbase,
  usettings;

type

  { TdlgComicInfo }

  TdlgComicInfo = class(TSettingsDialog)
    BtnClose: TButton;
    BtnRemove: TButton;
    CbBackup: TCheckBox;
    LVFiles: TListView;
    PanelBottom: TPanel;
    PanelTop: TPanel;
    SpinThreads: TSpinEdit;
    procedure BtnRemoveClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FDir: string;
    FFiles: TStringArray;
    function GetThreads: integer;
    procedure LoadSettings; override;
    procedure SaveSettings; override;
  public
    procedure ScanFiles(const AFiles: TStringArray; const ADir: string);
    property Threads: integer read GetThreads;
  end;

implementation

uses
  uservicecomicinfo,
  uLog;

{$R *.lfm}

{ TdlgComicInfo }

procedure TdlgComicInfo.FormCreate(Sender: TObject);
var
  Col: TListColumn;
begin
  Col := LVFiles.Columns.Add;
  Col.Caption := 'File';
  Col.AutoSize := True;
  Col := LVFiles.Columns.Add;
  Col.Caption := 'ComicInfo.xml';
  Col.Width := 120;

  LVFiles.Clear;
  InitSettingsPersistence;
end;

procedure TdlgComicInfo.LoadSettings;
begin
  CbBackup.Checked := AppSettings.ReadBool('RemoveComicInfo', 'Backup', True);
  SpinThreads.Value := AppSettings.ReadInteger('RemoveComicInfo', 'Threads', 0);
end;

procedure TdlgComicInfo.SaveSettings;
begin
  AppSettings.WriteBool('RemoveComicInfo', 'Backup', CbBackup.Checked);
  AppSettings.WriteInteger('RemoveComicInfo', 'Threads', SpinThreads.Value);
end;

function TdlgComicInfo.GetThreads: integer;
begin
  Result := SpinThreads.Value;
end;

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
  LVFiles.BeginUpdate;
  try
    LVFiles.Items.Clear;
    for i := 0 to High(Results) do
    begin
      It := LVFiles.Items.Add;
      It.Caption := Results[i].FileName;
      if Results[i].ErrorMsg <> '' then
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

procedure TdlgComicInfo.BtnRemoveClick(Sender: TObject);
var
  i, Removed: integer;
  ToRemove: TStringArray;
  Results: TComicInfoResults;
begin
  ToRemove := nil;
  for i := 0 to LVFiles.Items.Count - 1 do
    if LVFiles.Items[i].Checked then
    begin
      SetLength(ToRemove, Length(ToRemove) + 1);
      ToRemove[High(ToRemove)] := LVFiles.Items[i].Caption;
    end;

  if Length(ToRemove) = 0 then Exit;

  Results := TComicInfoService.Remove(ToRemove, FDir, CbBackup.Checked,
    nil, SpinThreads.Value);
  Removed := 0;
  for i := 0 to High(Results) do
    if Results[i].Removed then
      Inc(Removed);

  { Only rebuild the list when the dialog will stay open; on success we
    close immediately, so re-scanning every archive would be wasted work. }
  if Removed > 0 then
    ModalResult := mrOk
  else
    ScanFiles(FFiles, FDir);
end;

end.
