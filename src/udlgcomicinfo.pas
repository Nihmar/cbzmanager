unit udlgcomicinfo;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ExtCtrls;

type

  TdlgComicInfo = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    BtnRemove: TButton;
    BtnClose: TButton;
    CbBackup: TCheckBox;
    LVFiles: TListView;
    PanelBottom: TPanel;
    FDir: string;
    FFiles: TStringArray;
    procedure BtnRemoveClick(Sender: TObject);
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
var
  Col: TListColumn;
begin
  BorderStyle := bsDialog;
  BorderIcons := [biSystemMenu];

  LVFiles := TListView.Create(Self);
  LVFiles.Parent := Self;
  LVFiles.Align := alClient;
  LVFiles.BorderSpacing.Around := 8;
  LVFiles.Checkboxes := True;
  LVFiles.GridLines := True;
  LVFiles.ReadOnly := True;
  LVFiles.RowSelect := True;
  LVFiles.ViewStyle := vsReport;
  Col := LVFiles.Columns.Add;
  Col.Caption := 'File';
  Col.AutoSize := True;
  Col := LVFiles.Columns.Add;
  Col.Caption := 'ComicInfo.xml';
  Col.Width := 120;

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 88;
  PanelBottom.BevelOuter := bvNone;

  CbBackup := TCheckBox.Create(Self);
  CbBackup.Parent := PanelBottom;
  CbBackup.SetBounds(12, 8, 540, 24);
  CbBackup.Caption := 'Create backup (_OLD.cbz) before rewriting';
  CbBackup.Checked := True;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PanelBottom;
  BtnClose.SetBounds(472, 44, 80, 30);
  BtnClose.Cancel := True;
  BtnClose.Caption := 'Close';
  BtnClose.Default := True;
  BtnClose.ModalResult := mrOk;

  BtnRemove := TButton.Create(Self);
  BtnRemove.Parent := PanelBottom;
  BtnRemove.SetBounds(384, 44, 80, 30);
  BtnRemove.Caption := 'Remove';
  BtnRemove.OnClick := @BtnRemoveClick;

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

  ScanFiles(FFiles, FDir);
  if Removed > 0 then
    ModalResult := mrOk;
end;

end.
