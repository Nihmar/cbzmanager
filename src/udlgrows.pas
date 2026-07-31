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

  Usage:
    dlg.PageCount := N;        // resets the dialog for a new archive
    dlg.Directory := APath;
    if dlg.ShowModal = mrOk then
      for i := 0 to High(dlg.Selected) do
        if dlg.Selected[i] then ...   // page (i+1) was selected
}

interface

uses
  Classes,
  SysUtils,
  Forms,
  Controls,
  Graphics,
  StdCtrls,
  ExtCtrls,
  udlgbase,
  usettings;

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
      PageCount     - total number of pages in the archive. Assigning it also
                      resets the dialog, so set it before every ShowModal.
      Directory     - path to the archive directory (for contextual actions)
      Selected      - read-only boolean array marking selected pages
      SelectedCount - how many pages are currently selected
      Renumber / BatchAll / DeletePermanently - checkbox states }

  TdlgRows = class(TSettingsDialog)
    BtnCancel: TButton;
    BtnOk: TButton;
    CbRenumber: TCheckBox;
    CbBatchAll: TCheckBox;
    CbDeletePerm: TCheckBox;
    EditRanges: TEdit;
    LabelPreview: TLabel;
    LabelExample: TLabel;
    LabelFiles: TLabel;
    MemoFiles: TMemo;
    MemoPreview: TMemo;
    PanelBottom: TPanel;
    procedure EditRangesChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
  private
    FPageCount: integer;
    FDirectory: string;
    FSelected: TBooleanDynArray;
    FFileList: TStringList;
    function GetSelectedCount: integer;
    function GetRenumber: boolean;
    function GetBatchAll: boolean;
    function GetDeletePermanently: boolean;
    procedure SetPageCount(AValue: integer);
    procedure SetFileList(AValue: TStringList);
    procedure ParseRanges;
    procedure UpdatePreview;
    procedure LoadSettings; override;
    procedure SaveSettings; override;
  public
    { Clears the range text, the selection and the preview. Called
      automatically whenever PageCount is assigned. }
    procedure Reset;
    property PageCount: integer read FPageCount write SetPageCount;
    property Directory: string read FDirectory write FDirectory;
    property Selected: TBooleanDynArray read FSelected;
    property SelectedCount: integer read GetSelectedCount;
    property Renumber: boolean read GetRenumber;
    property BatchAll: boolean read GetBatchAll;
    property DeletePermanently: boolean read GetDeletePermanently;
    { Optional per-file scope description, one "name (N pages)" line per
      target archive.  Shown in a read-only memo; the caller keeps ownership.
      When nil (or empty) the file-scope area is hidden. }
    property FileList: TStringList read FFileList write SetFileList;
  end;

implementation

{$R *.lfm}

{ Parses range strings like "1, 4, 7-10, 15" into a boolean array
  where True means the page at that index is selected for deletion.
  Indices are 1-based in the input, 0-based in the array.
  Invalid tokens (non-numeric values) are silently skipped.
  Writes are bounded by the actual array length, so the routine is safe
  even if ATotal and Length(ASelected) disagree. }
procedure ParseRangeString(const S: string; ATotal: integer;
  var ASelected: array of boolean);
var
  Parts: TStringArray;
  i, Lo, Hi, Err, DashPos, j, Limit: integer;
  Token: string;
begin
  Limit := Length(ASelected);
  if ATotal < Limit then
    Limit := ATotal;

  for i := 0 to Limit - 1 do
    ASelected[i] := False;

  Parts := S.Split([',', ';']);
  for i := 0 to High(Parts) do
  begin
    Token := Trim(Parts[i]);
    if Token = '' then Continue;

    { Try "N-M" range }
    DashPos := Token.IndexOf('-');
    if DashPos >= 0 then
    begin
      Val(Trim(Token.Substring(0, DashPos)), Lo, Err);
      if Err <> 0 then Continue;  { skip token if left side is not a number }
      Val(Trim(Token.Substring(DashPos + 1)), Hi, Err);
      if Err <> 0 then Continue;  { skip token if right side is not a number }
    end
    else
    begin
      Val(Token, Lo, Err);
      if Err <> 0 then Continue;  { skip token if not a number }
      Hi := Lo;
    end;

    { Swap if the user wrote the range backwards, e.g. "10-7" }
    if Lo > Hi then
    begin
      j := Lo;
      Lo := Hi;
      Hi := j;
    end;

    { Clamp to the valid page interval before looping, so that a huge
      range such as "1-999999" costs nothing extra }
    if Lo < 1 then Lo := 1;
    if Hi > Limit then Hi := Limit;

    for j := Lo to Hi do
      ASelected[j - 1] := True;
  end;
end;

{ TdlgRows }

procedure TdlgRows.FormCreate(Sender: TObject);
begin
  FPageCount := 0;
  FSelected := nil;
  FFileList := nil;

  InitSettingsPersistence;
end;

procedure TdlgRows.LoadSettings;
begin
  CbRenumber.Checked := AppSettings.ReadBool('DeleteRows', 'Renumber', True);
  CbBatchAll.Checked := AppSettings.ReadBool('DeleteRows', 'BatchAll', False);
  CbDeletePerm.Checked :=
    AppSettings.ReadBool('DeleteRows', 'DeletePermanently', False);
end;

procedure TdlgRows.SaveSettings;
begin
  AppSettings.WriteBool('DeleteRows', 'Renumber', CbRenumber.Checked);
  AppSettings.WriteBool('DeleteRows', 'BatchAll', CbBatchAll.Checked);
  AppSettings.WriteBool('DeleteRows', 'DeletePermanently', CbDeletePerm.Checked);
end;

procedure TdlgRows.FormShow(Sender: TObject);
begin
  ParseRanges;
  UpdatePreview;
end;

procedure TdlgRows.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  if (ModalResult = mrOk) and (GetSelectedCount = 0) then
  begin
    CanClose := False;
    MemoPreview.Lines.Text := 'No pages selected - nothing to delete.' +
      LineEnding + 'Enter a range such as 1, 4, 7-10 or press Cancel.';
    if EditRanges.CanFocus then
      EditRanges.SetFocus;
  end;
end;

procedure TdlgRows.Reset;
begin
  EditRanges.Text := '';
  SetLength(FSelected, 0);
  ParseRanges;
  UpdatePreview;
end;

procedure TdlgRows.EditRangesChange(Sender: TObject);
begin
  ParseRanges;
  UpdatePreview;
end;

procedure TdlgRows.SetPageCount(AValue: integer);
begin
  if AValue < 0 then
    AValue := 0;
  FPageCount := AValue;
  Reset;
end;

{ Copies the per-file scope lines into the memo and reveals the area only
  when there is something to show (the preview "Delete rows" flow has no
  file list).  The caller keeps ownership of AValue. }
procedure TdlgRows.SetFileList(AValue: TStringList);
begin
  FFileList := AValue;
  LabelFiles.Visible := (AValue <> nil) and (AValue.Count > 0);
  MemoFiles.Visible := LabelFiles.Visible;
  if LabelFiles.Visible then
    MemoFiles.Lines.Assign(AValue)
  else
    MemoFiles.Clear;
end;

function TdlgRows.GetSelectedCount: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to High(FSelected) do
    if FSelected[i] then
      Inc(Result);
end;

function TdlgRows.GetRenumber: boolean;
begin
  Result := CbRenumber.Checked;
end;

function TdlgRows.GetBatchAll: boolean;
begin
  Result := CbBatchAll.Checked;
end;

function TdlgRows.GetDeletePermanently: boolean;
begin
  Result := CbDeletePerm.Checked;
end;

procedure TdlgRows.ParseRanges;
begin
  if FPageCount <= 0 then
  begin
    SetLength(FSelected, 0);
    Exit;
  end;
  SetLength(FSelected, FPageCount);
  ParseRangeString(EditRanges.Text, FPageCount, FSelected);
end;

procedure TdlgRows.UpdatePreview;
var
  i, Count: integer;
  List: string;
begin
  Count := 0;
  List := '';
  for i := 0 to High(FSelected) do
    if FSelected[i] then
    begin
      Inc(Count);
      // Build comma-separated list of 1-based page numbers
      if List <> '' then List := List + ', ';
      List := List + IntToStr(i + 1);
    end;

  if Count = 0 then
    MemoPreview.Lines.Text := 'No pages selected'
  else if Count = 1 then
    MemoPreview.Lines.Text := '1 page: ' + List
  else
    MemoPreview.Lines.Text := Format('%d pages: %s', [Count, List]);
end;

end.
