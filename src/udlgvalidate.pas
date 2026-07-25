unit udlgvalidate;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ExtCtrls;

type
  { TdlgValidate }

  TdlgValidate = class(TForm)
    BtnClose: TButton;
    LVResult: TListView;
    PanelBottom: TPanel;
    procedure FormCreate(Sender: TObject);
  public
    procedure ValidateFiles(const AFiles: TStringArray; const ADir: string);
  end;

implementation

uses
  uZipEditor,
  uLog;

{$R *.lfm}

{ TdlgValidate }

procedure TdlgValidate.FormCreate(Sender: TObject);
begin
  LVResult.Clear;
end;

procedure TdlgValidate.ValidateFiles(const AFiles: TStringArray;
  const ADir: string);
var
  i, ImgCount: integer;
  It: TListItem;
  FullPath: string;
  Valid: boolean;
begin
  LVResult.BeginUpdate;
  try
    LVResult.Items.Clear;
    for i := 0 to High(AFiles) do
    begin
      FullPath := IncludeTrailingPathDelimiter(ADir) + AFiles[i];
      It := LVResult.Items.Add;
      It.Caption := AFiles[i];
      try
        Valid := IsValidCBZ(FullPath);
        ImgCount := GetImageCount(FullPath);
      except
        on E: Exception do
        begin
          Log('Validate: eccezione su %s: %s', [AFiles[i], E.Message]);
          Valid := False;
          ImgCount := 0;
        end;
      end;
      if Valid then
      begin
        It.SubItems.Add('OK');
        It.SubItems.Add(IntToStr(ImgCount));
        It.SubItems.Add('');
      end
      else
      begin
        It.SubItems.Add('ERRORE');
        It.SubItems.Add('—');
        It.SubItems.Add('ZIP non valido o nessuna immagine leggibile');
      end;
      It.ImageIndex := -1;
    end;
  finally
    LVResult.EndUpdate;
  end;
end;

end.
