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
  uZipEditor,
  uLog;

{$R *.lfm}

function HasComicInfoEntry(const AFileName: string): boolean;
var
  Entries: TZipEntries;
  i: integer;
begin
  Result := False;
  Entries := CollectZipEntries(AFileName);
  try
    for i := 0 to High(Entries) do
      if SameText(Entries[i].Name, 'ComicInfo.xml') then
        Exit(True);
  finally
    FreeZipEntries(Entries);
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
begin
  FDir := ADir;
  FFiles := AFiles;
  LVFiles.BeginUpdate;
  try
    LVFiles.Items.Clear;
    for i := 0 to High(AFiles) do
    begin
      FullPath := IncludeTrailingPathDelimiter(ADir) + AFiles[i];
      It := LVFiles.Items.Add;
      It.Caption := AFiles[i];
      try
        if HasComicInfoEntry(FullPath) then
        begin
          It.SubItems.Add('Present');
          It.Checked := True;
        end
        else
        begin
          It.SubItems.Add('Absent');
          It.Checked := False;
        end;
      except
        It.SubItems.Add('Error');
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
  FileName, OldFile, FullPath: string;
  Entries: TZipEntries;
  j, k: integer;
begin
  Removed := 0;
  for i := 0 to LVFiles.Items.Count - 1 do
  begin
    if not LVFiles.Items[i].Checked then Continue;
    FileName := LVFiles.Items[i].Caption;
    FullPath := IncludeTrailingPathDelimiter(FDir) + FileName;

    { Read all entries, filter out ComicInfo.xml, write back }
    Entries := CollectZipEntries(FullPath);
    try
      { Count how many entries after removing ComicInfo.xml }
      k := 0;
      for j := 0 to High(Entries) do
        if not SameText(Entries[j].Name, 'ComicInfo.xml') then
          Inc(k);

      if k = Length(Entries) then
        Continue; { no ComicInfo.xml found }

      { Backup original }
      if CbBackup.Checked then
      begin
        OldFile := ChangeFileExt(FullPath, '') + '_OLD.cbz';
        if FileExists(OldFile) then DeleteFile(OldFile);
        RenameFile(FullPath, OldFile);
      end;

      { Write new CBZ without ComicInfo.xml }
      k := 0;
      for j := 0 to High(Entries) do
      begin
        if SameText(Entries[j].Name, 'ComicInfo.xml') then
        begin
          Entries[j].Data.Free;
          Entries[j].Data := nil;
          Continue;
        end;
        if j <> k then
        begin
          Entries[k] := Entries[j];
          Entries[j].Data := nil;
        end;
        Inc(k);
      end;
      SetLength(Entries, k);

      WriteZipFromEntries(FullPath, Entries);
      { Free the streams — no longer needed }
      for j := 0 to High(Entries) do
        Entries[j].Data.Free;
      Entries := nil;
      Inc(Removed);
    finally
      if Entries <> nil then
        FreeZipEntries(Entries);
    end;
  end;

  if Removed > 0 then
    ModalResult := mrOk;
end;

end.
