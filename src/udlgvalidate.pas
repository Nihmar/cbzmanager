unit udlgvalidate;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ExtCtrls, uservicevalidate;

type
  { TdlgValidate }

  TdlgValidate = class(TForm)
    BtnClose: TButton;
    LVResult: TListView;
    PanelBottom: TPanel;
    procedure FormCreate(Sender: TObject);
  public
    { Populate the result list from already-collected validation results. }
    procedure ShowResults(const AResults: TValidationResults);
  end;

implementation

uses
  uLog;

{$R *.lfm}

{ TdlgValidate }

procedure TdlgValidate.FormCreate(Sender: TObject);
begin
  LVResult.Clear;
end;

procedure TdlgValidate.ShowResults(const AResults: TValidationResults);
var
  i, j: integer;
  It: TListItem;
  FirstError: string;
begin
  LVResult.BeginUpdate;
  try
    LVResult.Items.Clear;
    for i := 0 to High(AResults) do
    begin
      It := LVResult.Items.Add;
      It.Caption := AResults[i].FileName;
      if AResults[i].Valid then
      begin
        It.SubItems.Add('OK');
        It.SubItems.Add(IntToStr(AResults[i].ImageCount));
        if Length(AResults[i].ImageChecks) > AResults[i].ImageCount then
          It.SubItems.Add(Format('%d/%d valid',
            [AResults[i].ImageCount, Length(AResults[i].ImageChecks)]))
        else
          It.SubItems.Add('');
      end
      else
      begin
        It.SubItems.Add('ERROR');
        It.SubItems.Add('—');
        FirstError := AResults[i].ErrorMsg;
        for j := 0 to High(AResults[i].ImageChecks) do
          if not AResults[i].ImageChecks[j].Valid then
          begin
            FirstError := AResults[i].ImageChecks[j].EntryName + ': ' +
              AResults[i].ImageChecks[j].ErrorMsg;
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
