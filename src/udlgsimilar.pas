unit udlgsimilar;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls;

type

  { TdlgSimilar }

  TdlgSimilar = class(TForm)
    BtnClose: TButton;
    BtnExtract: TButton;
    BtnDeleteDups: TButton;
    LabelThreshold: TLabel;
    LblThresholdVal: TLabel;
    LVGroups: TListView;
    PanelBottom: TPanel;
    TrackThreshold: TTrackBar;
    procedure FormCreate(Sender: TObject);
    procedure TrackThresholdChange(Sender: TObject);
  end;

implementation

{$R *.lfm}

{ TdlgSimilar }

procedure TdlgSimilar.FormCreate(Sender: TObject);
begin
  TrackThreshold.Min := 0;
  TrackThreshold.Max := 16;
  TrackThreshold.Position := 10;
  LblThresholdVal.Caption := '10';
end;

procedure TdlgSimilar.TrackThresholdChange(Sender: TObject);
begin
  LblThresholdVal.Caption := IntToStr(TrackThreshold.Position);
end;

end.
