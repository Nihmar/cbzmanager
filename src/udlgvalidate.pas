unit udlgvalidate;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ExtCtrls, uservicevalidate, udlgbase;

type
  TdlgValidate = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    LVResult: TListView;
    PanelBottom: TPanel;
    BtnClose: TButton;
  public
    procedure ShowResults(const AResults: TValidationResults);
  end;

implementation

{$R *.lfm}

procedure TdlgValidate.FormCreate(Sender: TObject);
var
  Col: TListColumn;
begin
  InitDialogChrome(Self);

  PanelBottom := CreateBottomPanel(Self, 44);

  BtnClose := CreateDialogButton(PanelBottom, 'Close',
    PanelBottom.ClientWidth - DLG_BTN_WIDTH - 8, 7, mrOK, True, True);
  BtnClose.Anchors := [akTop, akRight];

  LVResult := CreateReportListView(Self, False);

  Col := LVResult.Columns.Add;
  Col.Caption := 'File';
  Col.AutoSize := True;

  Col := LVResult.Columns.Add;
  Col.Caption := 'Result';
  Col.Width := 80;

  Col := LVResult.Columns.Add;
  Col.Caption := 'Images';
  Col.Width := 80;

  Col := LVResult.Columns.Add;
  Col.Caption := 'Note';
  Col.AutoSize := True;
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
        It.SubItems.Add('-');
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
