unit udlgcomicinfo;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ExtCtrls;

type

  { TdlgComicInfo }

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

procedure TdlgComicInfo.FormCreate(Sender: TObject);
begin
  LVFiles.Clear;
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

procedure TdlgComicInfo.BtnRemoveClick(Sender: TObject);
var
  i, Removed: integer;
  ToRemove: TStringArray;
  Results: TComicInfoResults;
begin
  { Collect checked files }
  ToRemove := nil;
  for i := 0 to LVFiles.Items.Count - 1 do
    if LVFiles.Items[i].Checked then
    begin
      SetLength(ToRemove, Length(ToRemove) + 1);
      ToRemove[High(ToRemove)] := LVFiles.Items[i].Caption;
    end;

  if Length(ToRemove) = 0 then Exit;

  Results := TComicInfoService.Remove(ToRemove, FDir, CbBackup.Checked);
  Removed := 0;
  for i := 0 to High(Results) do
    if Results[i].Removed then
      Inc(Removed);

  { Refresh scan results }
  ScanFiles(FFiles, FDir);
  if Removed > 0 then
    ModalResult := mrOk;
end;

end.
