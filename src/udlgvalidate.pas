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
  uservicevalidate,
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
  i, j: integer;
  It: TListItem;
  Results: TValidationResults;
  FirstError: string;
begin
  Results := TValidateService.ValidateDeep(AFiles, ADir);
  LVResult.BeginUpdate;
  try
    LVResult.Items.Clear;
    for i := 0 to High(Results) do
    begin
      It := LVResult.Items.Add;
      It.Caption := Results[i].FileName;
      if Results[i].Valid then
      begin
        It.SubItems.Add('OK');
        It.SubItems.Add(IntToStr(Results[i].ImageCount));
        { Build summary: valid count out of total }
        if Length(Results[i].ImageChecks) > Results[i].ImageCount then
          It.SubItems.Add(Format('%d/%d valid',
            [Results[i].ImageCount, Length(Results[i].ImageChecks)]))
        else
          It.SubItems.Add('');
      end
      else
      begin
        It.SubItems.Add('ERRORE');
        It.SubItems.Add('—');
        { Find first per-image error for detail }
        FirstError := Results[i].ErrorMsg;
        for j := 0 to High(Results[i].ImageChecks) do
          if not Results[i].ImageChecks[j].Valid then
          begin
            FirstError := Results[i].ImageChecks[j].EntryName + ': ' +
              Results[i].ImageChecks[j].ErrorMsg;
            Break;
          end;
        It.SubItems.Add(FirstError);
      end;
      It.ImageIndex := -1;
    end;
  finally
    LVResult.EndUpdate;
  end;
end;

end.
