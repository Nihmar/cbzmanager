unit udlgconvertresults;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls,
  ComCtrls, ExtCtrls, userviceconvert, udlgbase;

type
  TdlgConvertResults = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    LVResult: TListView;
    LblSummary: TLabel;
    PanelBottom: TPanel;
    BtnClose: TButton;
  public
    procedure ShowResults(const AResults: TConvertResults);
  end;

implementation

{$R *.lfm}

function FormatSize(ABytes: Int64): string;
begin
  if ABytes >= 1024 * 1024 then
    Result := Format('%.1f MB', [ABytes / (1024 * 1024)])
  else if ABytes >= 1024 then
    Result := Format('%.1f KB', [ABytes / 1024])
  else
    Result := Format('%d B', [ABytes]);
end;

procedure TdlgConvertResults.FormCreate(Sender: TObject);
var
  Col: TListColumn;
begin
  InitDialogChrome(Self);

  PanelBottom := CreateBottomPanel(Self, 64);

  LblSummary := TLabel.Create(Self);
  LblSummary.Parent := PanelBottom;
  LblSummary.Left := 12;
  LblSummary.Top := 8;
  LblSummary.Width := 500;
  LblSummary.Font.Height := -13;
  LblSummary.Font.Style := [fsBold];

  BtnClose := CreateDialogButton(PanelBottom, 'Close',
    PanelBottom.ClientWidth - DLG_BTN_WIDTH - 8, 26, mrOK, True, True);
  BtnClose.Anchors := [akTop, akRight];

  LVResult := CreateReportListView(Self, False);

  Col := LVResult.Columns.Add;
  Col.Caption := 'File';
  Col.Width := 220;

  Col := LVResult.Columns.Add;
  Col.Caption := 'Status';
  Col.Width := 100;

  Col := LVResult.Columns.Add;
  Col.Caption := 'Original';
  Col.Width := 90;
  Col.Alignment := taRightJustify;

  Col := LVResult.Columns.Add;
  Col.Caption := 'New';
  Col.Width := 90;
  Col.Alignment := taRightJustify;

  Col := LVResult.Columns.Add;
  Col.Caption := 'Saved';
  Col.Width := 90;
  Col.Alignment := taRightJustify;

  Col := LVResult.Columns.Add;
  Col.Caption := 'Note';
  Col.AutoSize := True;
end;

procedure TdlgConvertResults.ShowResults(const AResults: TConvertResults);
var
  i: integer;
  It: TListItem;
  TotalOrig, TotalNew, Diff: Int64;
  Converted, Skipped: integer;
begin
  TotalOrig := 0;
  TotalNew := 0;
  Converted := 0;
  Skipped := 0;

  LVResult.BeginUpdate;
  try
    LVResult.Items.Clear;
    for i := 0 to High(AResults) do
    begin
      It := LVResult.Items.Add;
      It.Caption := AResults[i].FileName;

      if not AResults[i].Success then
      begin
        It.SubItems.Add('Error');
        It.SubItems.Add('-');
        It.SubItems.Add('-');
        It.SubItems.Add('-');
        It.SubItems.Add(AResults[i].ErrorMsg);
      end
      else if AResults[i].PagesConverted = 0 then
      begin
        Inc(Skipped);
        It.SubItems.Add('Skipped');
        It.SubItems.Add(FormatSize(AResults[i].OriginalSize));
        It.SubItems.Add('-');
        It.SubItems.Add('-');
        It.SubItems.Add(AResults[i].ErrorMsg);
        TotalOrig := TotalOrig + AResults[i].OriginalSize;
        TotalNew := TotalNew + AResults[i].OriginalSize;
      end
      else
      begin
        Inc(Converted);
        Diff := AResults[i].OriginalSize - AResults[i].NewSize;
        It.SubItems.Add('Converted');
        It.SubItems.Add(FormatSize(AResults[i].OriginalSize));
        It.SubItems.Add(FormatSize(AResults[i].NewSize));
        if Diff > 0 then
          It.SubItems.Add('-' + FormatSize(Diff))
        else if Diff < 0 then
          It.SubItems.Add('+' + FormatSize(-Diff))
        else
          It.SubItems.Add('0 B');
        It.SubItems.Add(Format('%d pages', [AResults[i].PagesConverted]));
        TotalOrig := TotalOrig + AResults[i].OriginalSize;
        TotalNew := TotalNew + AResults[i].NewSize;
      end;
      It.ImageIndex := -1;
    end;
  finally
    LVResult.EndUpdate;
  end;

  Diff := TotalOrig - TotalNew;
  if Diff > 0 then
    LblSummary.Caption := Format('%d converted, %d skipped  —  Total saved: %s (%.0f%%)',
      [Converted, Skipped, FormatSize(Diff), Diff * 100 / Max(TotalOrig, 1)])
  else
    LblSummary.Caption := Format('%d converted, %d skipped  —  No space saved',
      [Converted, Skipped]);
end;

end.
