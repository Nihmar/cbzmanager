unit udlgcomicinfo;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ExtCtrls;

type

  { TdlgComicInfo }

  TdlgComicInfo = class(TForm)
    BtnClose: TButton;
    CbBackup: TCheckBox;
    LVFiles: TListView;
    PanelBottom: TPanel;
    procedure FormCreate(Sender: TObject);
  public
    procedure ScanFiles(const AFiles: TStringArray; const ADir: string);
  end;

implementation

uses
  Zipper,
  uLog;

{$R *.lfm}

function HasComicInfoEntry(const AFileName: string): boolean;
var
  UnZipper: TUnZipper;
  i: integer;
begin
  Result := False;
  UnZipper := TUnZipper.Create;
  try
    UnZipper.FileName := AFileName;
    UnZipper.Examine;
    for i := 0 to UnZipper.Entries.Count - 1 do
      if SameText(UnZipper.Entries[i].ArchiveFileName, 'ComicInfo.xml') then
        Exit(True);
  finally
    UnZipper.Free;
  end;
end;

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
  FullPath: string;
  HasIt: boolean;
begin
  LVFiles.BeginUpdate;
  try
    LVFiles.Items.Clear;
    for i := 0 to High(AFiles) do
    begin
      FullPath := IncludeTrailingPathDelimiter(ADir) + AFiles[i];
      It := LVFiles.Items.Add;
      It.Caption := AFiles[i];
      try
        HasIt := HasComicInfoEntry(FullPath);
      except
        HasIt := False;
      end;
      if HasIt then
      begin
        It.SubItems.Add('Presente');
        It.Checked := True;
      end
      else
      begin
        It.SubItems.Add('Assente');
        It.Checked := False;
      end;
    end;
  finally
    LVFiles.EndUpdate;
  end;
end;

end.
