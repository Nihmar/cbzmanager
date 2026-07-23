unit main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls;

type
  TfrmMain = class(TForm)
    PanelTop: TPanel;
    EditDir: TEdit;
    BtnBrowse: TButton;
    FlowPanel: TFlowPanel;
    SelectDialog: TSelectDirectoryDialog;
    procedure BtnBrowseClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    procedure ClearThumbnails;
    procedure LoadDirectory(const ADir: string);
  public
  end;

var
  frmMain: TfrmMain;

implementation

uses
  uZipEditor;

{$R *.lfm}

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Caption := 'CBZ Manager';
  if ParamCount > 0 then
    LoadDirectory(ParamStr(1));
end;

procedure TfrmMain.ClearThumbnails;
var
  i: Integer;
begin
  for i := FlowPanel.ControlCount - 1 downto 0 do
    FlowPanel.Controls[i].Free;
end;

procedure TfrmMain.BtnBrowseClick(Sender: TObject);
begin
  if SelectDialog.Execute then
  begin
    EditDir.Text := SelectDialog.FileName;
    LoadDirectory(SelectDialog.FileName);
  end;
end;

procedure TfrmMain.LoadDirectory(const ADir: string);
var
  SearchRec: TSearchRec;
  FilePath: string;
  Panel: TPanel;
  Img: TImage;
  Lbl: TLabel;
  Bitmap: TBitmap;
  Dir: string;
begin
  ClearThumbnails;
  Dir := IncludeTrailingPathDelimiter(ADir);

  if FindFirst(Dir + '*.cbz', faAnyFile, SearchRec) = 0 then
  begin
    repeat
      FilePath := Dir + SearchRec.Name;

      Panel := TPanel.Create(Self);
      Panel.Parent := FlowPanel;
      Panel.Width := 150;
      Panel.Height := 180;
      Panel.BevelOuter := bvNone;
      Panel.BorderStyle := bsSingle;
      Panel.BorderSpacing.Around := 4;

      Img := TImage.Create(Self);
      Img.Parent := Panel;
      Img.Align := alClient;
      Img.Stretch := True;
      Img.Proportional := True;
      Img.Center := True;

      try
        Bitmap := GetFirstImageAsBitmap(FilePath);
        if Bitmap <> nil then
        begin
          Img.Picture.Bitmap := Bitmap;
          Bitmap.Free;
        end;
      except
      end;

      Lbl := TLabel.Create(Self);
      Lbl.Parent := Panel;
      Lbl.Align := alBottom;
      Lbl.AutoSize := False;
      Lbl.Height := 24;
      Lbl.Caption := SearchRec.Name;
      Lbl.Layout := tlCenter;
      Lbl.Alignment := taCenter;
      Lbl.WordWrap := True;

    until FindNext(SearchRec) <> 0;
    FindClose(SearchRec);
  end;
end;

end.

