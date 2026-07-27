unit udlgrows;

{$mode ObjFPC}{$H+}

{
  udlgrows.pas - Page Range Selection Dialog

  Provides TdlgRows, a dialog that lets the user specify which pages should
  be selected (typically for deletion) from a comic archive. The user enters
  page ranges in a compact notation (e.g. "1, 4, 7-10, 15") and the dialog
  parses them into a boolean array where True entries mark selected pages.
  A live preview panel shows the expanded selection so the user can verify
  the result before confirming.
}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, Math;

type
  { TBooleanDynArray - dynamic array of boolean used to represent which pages
    are selected. Index i (0-based) is True when page (i+1) is selected. }
  TBooleanDynArray = array of boolean;

  { TdlgRows - Page range selection dialog.

    The user types range expressions into an edit box; the dialog parses them
    on every keystroke and shows a preview of the resulting page list.
    Checkboxes control optional behaviours such as renumbering after deletion,
    batching across all files, and permanent (non-recoverable) deletion.

    Properties:
      PageCount - total number of pages in the archive (set before showing)
      Directory - path to the archive directory (for contextual actions)
      Selected  - read-only boolean array marking selected pages }

  TdlgRows = class(TForm)
    BtnOk: TButton;
    BtnCancel: TButton;
    CbRenumber: TCheckBox;
    CbBatchAll: TCheckBox;
    CbDeletePerm: TCheckBox;
    EditRanges: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    MemoPreview: TMemo;
    PanelBottom: TPanel;
    PanelPreview: TPanel;
    procedure EditRangesChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FPageCount: integer;
    FDirectory: string;
    FSelected: TBooleanDynArray;
    procedure ParseRanges;
    procedure UpdatePreview;
  public
    property PageCount: integer read FPageCount write FPageCount;
    property Directory: string read FDirectory write FDirectory;
    property Selected: TBooleanDynArray read FSelected;
  end;

implementation

{$R *.lfm}

{ Parses range strings like "1, 4, 7-10, 15" into a boolean array
  where True means the page at that index is selected for deletion.
  Indices are 1-based in the input, 0-based in the array. }
procedure ParseRangeString(const S: string; ATotal: integer;
  out ASelected: array of boolean);
var
  Parts: TStringArray;
  i, Lo, Hi, Code, DashPos: integer;
  Token: string;
begin
  for i := 0 to ATotal - 1 do
    if i < Length(ASelected) then
      ASelected[i] := False;

  Parts := S.Split([',', ';']);
  for i := 0 to High(Parts) do
  begin
    Token := Trim(Parts[i]);
    if Token = '' then Continue;

    { Try "N-M" range }
    Code := Token.IndexOf('-');
    if Code >= 0 then
    begin
      DashPos := Code;
      Val(Trim(Token.Substring(0, DashPos)), Lo, Code);
      if Code <> 0 then Lo := 1;
      Val(Trim(Token.Substring(DashPos + 1)), Hi, Code);
      if Code <> 0 then Hi := Lo;
    end
    else
    begin
      Val(Token, Lo, Code);
      if Code <> 0 then Lo := 0;
      Hi := Lo;
    end;

    if Lo > Hi then
    begin
      Code := Lo; Lo := Hi; Hi := Code;
    end;

    for Code := Lo to Hi do
      if (Code >= 1) and (Code <= ATotal) then
        ASelected[Code - 1] := True;
  end;
end;

{ TdlgRows }

{ Initialise the dialog: zero the page count, clear the selection array,
  and reset the range edit so no pages are selected on open. }
procedure TdlgRows.FormCreate(Sender: TObject);
begin
  FPageCount := 0;
  FSelected := nil;
  EditRanges.Text := '';
end;

{ Fired on every change to the range edit box. Re-parses the input string
  and updates the preview panel so the user sees instant feedback. }
procedure TdlgRows.EditRangesChange(Sender: TObject);
begin
  ParseRanges;
  UpdatePreview;
end;

{ Allocate the selection array (if PageCount > 0) and parse the current
  range text into it by calling the standalone ParseRangeString helper. }
procedure TdlgRows.ParseRanges;
begin
  if FPageCount <= 0 then Exit;
  SetLength(FSelected, FPageCount);
  ParseRangeString(EditRanges.Text, FPageCount, FSelected);
end;

{ Build a human-readable summary of the current selection and display it
  in the MemoPreview control. Shows either "No pages selected", the single
  selected page number, or a count followed by the comma-separated list. }
procedure TdlgRows.UpdatePreview;
var
  i, Count: integer;
  Parts: string;
begin
  Count := 0;
  Parts := '';
  for i := 0 to High(FSelected) do
    if FSelected[i] then
    begin
      Inc(Count);
      // Build comma-separated list of 1-based page numbers
      if Parts <> '' then Parts := Parts + ', ';
      Parts := Parts + IntToStr(i + 1);
    end;

  if Count = 0 then
    MemoPreview.Lines.Text := 'No pages selected'
  else if Count = 1 then
    MemoPreview.Lines.Text := '1 page: ' + Parts
  else
    MemoPreview.Lines.Text := Format('%d pages: %s', [Count, Parts]);
end;

end.
