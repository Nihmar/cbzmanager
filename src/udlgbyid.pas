unit udlgbyid;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls;

type

  { TdlgByID }

  TdlgByID = class(TForm)
    BtnDelete: TButton;
    BtnClose: TButton;
    BtnLoadCSV: TButton;
    CbRenumber: TCheckBox;
    LblHint: TLabel;
    LblCount: TLabel;
    MemoIDs: TMemo;
    PanelBottom: TPanel;
    procedure FormCreate(Sender: TObject);
    procedure MemoIDsChange(Sender: TObject);
  private
    procedure UpdateCount;
  end;

implementation

{$R *.lfm}

{ TdlgByID }

procedure TdlgByID.FormCreate(Sender: TObject);
begin
  UpdateCount;
end;

procedure TdlgByID.MemoIDsChange(Sender: TObject);
begin
  UpdateCount;
end;

function IsValidID(const S: string): boolean;
var
  Dot: integer;
begin
  Dot := Pos('.cbz:', S);
  if Dot = 0 then
    Dot := Pos('.CBZ:', S);
  Result := (Dot > 1) and (Dot + 5 < Length(S));
end;

procedure TdlgByID.UpdateCount;
var
  i, ValidCount: integer;
  Line: string;
begin
  ValidCount := 0;
  for i := 0 to MemoIDs.Lines.Count - 1 do
  begin
    Line := Trim(MemoIDs.Lines[i]);
    if (Line <> '') and IsValidID(Line) then
      Inc(ValidCount);
  end;
  LblCount.Caption := Format('%d ID validi', [ValidCount]);
  BtnDelete.Enabled := ValidCount > 0;
end;

end.
