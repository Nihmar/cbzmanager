unit udlgmerge;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Spin;

type

  { TdlgMerge }

  TdlgMerge = class(TForm)
    BtnMerge: TButton;
    BtnClose: TButton;
    CbForce: TCheckBox;
    CbManualCPV: TCheckBox;
    EditSeries: TEdit;
    EditChapterStart: TSpinEdit;
    EditChapterEnd: TSpinEdit;
    EditCPV: TSpinEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    LblSeries: TLabel;
    LVFiles: TListView;
    PanelBottom: TPanel;
    PanelTop: TPanel;
    procedure CbManualCPVChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FFiles: TStringArray;
    FDir: string;
  public
    procedure LoadChapters(const AFiles: TStringArray; const ADir: string;
      const ASeriesName: string);
  end;

implementation

{$R *.lfm}

{ TdlgMerge }

procedure TdlgMerge.FormCreate(Sender: TObject);
begin
  EditCPV.Enabled := False;
  EditCPV.Value := 7;
  EditChapterStart.Value := 1;
  EditChapterEnd.Value := 1;
end;

procedure TdlgMerge.CbManualCPVChange(Sender: TObject);
begin
  EditCPV.Enabled := CbManualCPV.Checked;
end;

procedure TdlgMerge.LoadChapters(const AFiles: TStringArray;
  const ADir: string; const ASeriesName: string);
var
  i: integer;
  It: TListItem;
begin
  FFiles := AFiles;
  FDir := ADir;
  EditSeries.Text := ASeriesName;
  EditChapterEnd.Value := Length(AFiles);
  LVFiles.BeginUpdate;
  try
    LVFiles.Items.Clear;
    for i := 0 to High(AFiles) do
    begin
      It := LVFiles.Items.Add;
      It.Caption := IntToStr(i + 1);
      It.SubItems.Add(ChangeFileExt(AFiles[i], ''));
      It.SubItems.Add(Format('Vol.%d', [(i div 7) + 1]));
    end;
  finally
    LVFiles.EndUpdate;
  end;
end;

end.
