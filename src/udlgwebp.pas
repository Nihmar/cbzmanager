unit udlgwebp;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Spin, udlgbase, usettings, uWebP;

type
  TdlgWebp = class(TSettingsDialog)
    { Wired from the .lfm — controls must be published for RTTI lookup. }
    LabelQuality: TLabel;
    TrackQuality: TTrackBar;
    LblQualityVal: TLabel;
    CbReplaceOnlySmaller: TCheckBox;
    CbSkipExistingWebP: TCheckBox;
    CbRemoveComicInfo: TCheckBox;
    CbRenumber: TCheckBox;
    SpinThreads: TSpinEdit;
    GroupBackup: TRadioGroup;
    PanelBottom: TPanel;
    BtnConvert: TButton;
    BtnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure TrackQualityChange(Sender: TObject);
  private
    procedure LoadSettings; override;
    procedure SaveSettings; override;
    function GetQuality: integer;
    function GetBackup: boolean;
    function GetReplaceOnlyIfSmaller: boolean;
    function GetSkipExistingWebP: boolean;
    function GetRemoveComicInfo: boolean;
    function GetRenumberPages: boolean;
    function GetThreads: integer;
  public
    property Quality: integer read GetQuality;
    property ReplaceOnlyIfSmaller: boolean read GetReplaceOnlyIfSmaller;
    property SkipExistingWebP: boolean read GetSkipExistingWebP;
    property RemoveComicInfo: boolean read GetRemoveComicInfo;
    property RenumberPages: boolean read GetRenumberPages;
    property BackupOld: boolean read GetBackup;
    property Threads: integer read GetThreads;
  end;

implementation

{$R *.lfm}

procedure TdlgWebp.FormCreate(Sender: TObject);
begin
  InitSettingsPersistence;
end;

procedure TdlgWebp.LoadSettings;
begin
  TrackQuality.Position := AppSettings.ReadInteger('WebP', 'Quality', DEFAULT_WEBP_QUALITY);
  LblQualityVal.Caption := IntToStr(TrackQuality.Position) + '%';
  CbReplaceOnlySmaller.Checked :=
    AppSettings.ReadBool('WebP', 'ReplaceOnlyIfSmaller', True);
  CbSkipExistingWebP.Checked :=
    AppSettings.ReadBool('WebP', 'SkipExistingWebP', True);
  CbRemoveComicInfo.Checked :=
    AppSettings.ReadBool('WebP', 'RemoveComicInfo', True);
  CbRenumber.Checked := AppSettings.ReadBool('WebP', 'Renumber', True);
  GroupBackup.ItemIndex := AppSettings.ReadInteger('WebP', 'BackupMode', 0);
  SpinThreads.Value := AppSettings.ReadInteger('WebP', 'Threads', 0);
end;

procedure TdlgWebp.SaveSettings;
begin
  AppSettings.WriteInteger('WebP', 'Quality', TrackQuality.Position);
  AppSettings.WriteBool('WebP', 'ReplaceOnlyIfSmaller',
    CbReplaceOnlySmaller.Checked);
  AppSettings.WriteBool('WebP', 'SkipExistingWebP', CbSkipExistingWebP.Checked);
  AppSettings.WriteBool('WebP', 'RemoveComicInfo', CbRemoveComicInfo.Checked);
  AppSettings.WriteBool('WebP', 'Renumber', CbRenumber.Checked);
  AppSettings.WriteInteger('WebP', 'BackupMode', GroupBackup.ItemIndex);
  AppSettings.WriteInteger('WebP', 'Threads', SpinThreads.Value);
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
  Result := GroupBackup.ItemIndex <> 1;
end;

function TdlgWebp.GetThreads: integer;
begin
  Result := SpinThreads.Value;
end;

end.
