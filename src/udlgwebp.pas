unit udlgwebp;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls;

type

  { TdlgWebp }

  TdlgWebp = class(TForm)
    BtnConvert: TButton;
    BtnClose: TButton;
    CbReplaceOnlySmaller: TCheckBox;
    CbSkipExistingWebP: TCheckBox;
    CbRemoveComicInfo: TCheckBox;
    CbRenumber: TCheckBox;
    GroupBackup: TRadioGroup;
    LabelQuality: TLabel;
    LblQualityVal: TLabel;
    PanelBottom: TPanel;
    TrackQuality: TTrackBar;
    procedure FormCreate(Sender: TObject);
    procedure TrackQualityChange(Sender: TObject);
  private
    function GetQuality: integer;
    function GetBackup: boolean;
    function GetReplaceOnlyIfSmaller: boolean;
    function GetSkipExistingWebP: boolean;
    function GetRemoveComicInfo: boolean;
    function GetRenumberPages: boolean;
  public
    property Quality: integer read GetQuality;
    property ReplaceOnlyIfSmaller: boolean read GetReplaceOnlyIfSmaller;
    property SkipExistingWebP: boolean read GetSkipExistingWebP;
    property RemoveComicInfo: boolean read GetRemoveComicInfo;
    property RenumberPages: boolean read GetRenumberPages;
    property BackupOld: boolean read GetBackup;
  end;

implementation

{$R *.lfm}

{ TdlgWebp }

procedure TdlgWebp.FormCreate(Sender: TObject);
begin
  TrackQuality.Min := 30;
  TrackQuality.Max := 100;
  TrackQuality.Frequency := 5;
  TrackQuality.Position := 75;
  LblQualityVal.Caption := '75%';
end;

procedure TdlgWebp.TrackQualityChange(Sender: TObject);
begin
  LblQualityVal.Caption := IntToStr(TrackQuality.Position) + '%';
end;

function TdlgWebp.GetQuality: integer;
begin
  Result := TrackQuality.Position;
end;

function TdlgWebp.GetReplaceOnlyIfSmaller: boolean;
begin
  Result := CbReplaceOnlySmaller.Checked;
end;

function TdlgWebp.GetSkipExistingWebP: boolean;
begin
  Result := CbSkipExistingWebP.Checked;
end;

function TdlgWebp.GetRemoveComicInfo: boolean;
begin
  Result := CbRemoveComicInfo.Checked;
end;

function TdlgWebp.GetRenumberPages: boolean;
begin
  Result := CbRenumber.Checked;
end;

function TdlgWebp.GetBackup: boolean;
begin
  Result := GroupBackup.ItemIndex <> 1; // 0=Backup, 1=Elimina
end;

end.
