{
  udlgvalidate — Validation Results Dialog
  ----------------------------------------
  Displays a list of archive validation results in a TListView.
  Each row shows the file name, pass/fail status, image count,
  and the first encountered error (if any).

  This dialog is populated by the validation service (uservicevalidate)
  and lets the user review results after a batch validation run.
}
unit udlgvalidate;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ExtCtrls, uservicevalidate;

type
  {
    TdlgValidate — Dialog form that presents validation results in a tabular view.
    Columns: File Name | Status | Image Count | First Error
  }
  TdlgValidate = class(TForm)
    BtnClose: TButton;
    LVResult: TListView;
    PanelBottom: TPanel;
    { Initialises the list view on form creation. }
    procedure FormCreate(Sender: TObject);
  public
    {
      ShowResults — Fill the list view with validation outcome data.

      Parameters:
        AResults — an open array of TValidationResult records, one per
                   validated archive. Each record carries the file name,
                   overall validity flag, image count, per-image check
                   details, and a top-level error message.
    }
    procedure ShowResults(const AResults: TValidationResults);
  end;

implementation

uses
  uLog;

{$R *.lfm}

{ TdlgValidate }

{
  FormCreate — Clear the list view so the dialog always starts empty.
}
procedure TdlgValidate.FormCreate(Sender: TObject);
begin
  LVResult.Clear;
end;

{
  ShowResults — Populate the list view from an array of per-archive
  validation records. Each item gets a row with:
    Column 0 (Caption): archive file name
    Column 1 (SubItem 0): status — 'OK' or 'ERROR'
    Column 2 (SubItem 1): image count (or '—' for failures)
    Column 3 (SubItem 2): first error detail (or a "N of M valid" summary)

  The list view is wrapped in BeginUpdate/EndUpdate to prevent flickering
  and redundant repaints while rows are being added.

  Parameters:
    AResults — dynamic array of TValidationResult records.
}
procedure TdlgValidate.ShowResults(const AResults: TValidationResults);
var
  i, j: integer;
  It: TListItem;
  FirstError: string;
begin
  LVResult.BeginUpdate;      // freeze painting while we add rows
  try
    LVResult.Items.Clear;
    for i := 0 to High(AResults) do
    begin
      It := LVResult.Items.Add;
      It.Caption := AResults[i].FileName;   // column 0
      if AResults[i].Valid then
      begin
        // --- archive passed validation ---
        It.SubItems.Add('OK');
        It.SubItems.Add(IntToStr(AResults[i].ImageCount));
        // If the per-image detail list is longer than the image count,
        // show a summary like "3/5 valid" to hint at partial failures.
        if Length(AResults[i].ImageChecks) > AResults[i].ImageCount then
          It.SubItems.Add(Format('%d/%d valid',
            [AResults[i].ImageCount, Length(AResults[i].ImageChecks)]))
        else
          It.SubItems.Add('');
      end
      else
      begin
        // --- archive failed validation; surface the first error ---
        It.SubItems.Add('ERROR');
        It.SubItems.Add('—');
        // Fall back to the top-level error message, then scan for the
        // first per-image error (which is usually more specific).
        FirstError := AResults[i].ErrorMsg;
        for j := 0 to High(AResults[i].ImageChecks) do
          if not AResults[i].ImageChecks[j].Valid then
          begin
            FirstError := AResults[i].ImageChecks[j].EntryName + ': ' +
              AResults[i].ImageChecks[j].ErrorMsg;
            Break;  // stop at the first failing image
          end;
        It.SubItems.Add(FirstError);
      end;
      It.ImageIndex := -1;   // no icon for this list item
    end;
  finally
    LVResult.EndUpdate;      // re-enable painting
  end;
end;

end.
