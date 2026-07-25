unit udlgrows;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, Math;

type
  TBooleanDynArray = array of boolean;

  { TdlgRows }

  TdlgRows = class(TForm)
    BtnOk: TButton;
    BtnCancel: TButton;
    CbRenumber: TCheckBox;
    CbBatchAll: TCheckBox;
    CbDeletePerm: TCheckBox;
    EditRanges: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    LblPreview: TLabel;
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
  i, Lo, Hi, Code: integer;
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
      Val(Trim(Token.Substring(0, Code)), Lo, Code);
      if Code <> 0 then Lo := 1;
      Val(Trim(Token.Substring(Code + 1)), Hi, Code);
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

procedure TdlgRows.FormCreate(Sender: TObject);
begin
  FPageCount := 0;
  FSelected := nil;
  EditRanges.Text := '';
end;

procedure TdlgRows.EditRangesChange(Sender: TObject);
begin
  ParseRanges;
  UpdatePreview;
end;

procedure TdlgRows.ParseRanges;
begin
  if FPageCount <= 0 then Exit;
  SetLength(FSelected, FPageCount);
  ParseRangeString(EditRanges.Text, FPageCount, FSelected);
end;

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
      if Parts <> '' then Parts := Parts + ', ';
      Parts := Parts + IntToStr(i + 1);
    end;

  if Count = 0 then
    LblPreview.Caption := 'No pages selected'
  else if Count = 1 then
    LblPreview.Caption := '1 page: ' + Parts
  else
    LblPreview.Caption := Format('%d pages: %s', [Count, Parts]);
end;

end.
