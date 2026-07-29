unit udlgwebp;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, udlgbase, usettings, uWebP;

type
  TdlgWebp = class(TSettingsDialog)
    procedure FormCreate(Sender: TObject);
  private
    TrackQuality: TTrackBar;
    LabelQuality: TLabel;
    LblQualityVal: TLabel;
    CbReplaceOnlySmaller: TCheckBox;
    CbSkipExistingWebP: TCheckBox;
    CbRemoveComicInfo: TCheckBox;
    CbRenumber: TCheckBox;
    GroupBackup: TRadioGroup;
    PanelBottom: TPanel;
    BtnConvert: TButton;
    BtnClose: TButton;
    procedure LoadSettings; override;
    procedure SaveSettings; override;
    procedure TrackQualityChange(Sender: TObject);
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

procedure TdlgWebp.FormCreate(Sender: TObject);
begin
  LabelQuality := TLabel.Create(Self);
  LabelQuality.Parent := Self;
  LabelQuality.Left := 12;
  LabelQuality.Top := 12;
  LabelQuality.Caption := 'Quality';
  LabelQuality.Font.Height := -13;
  LabelQuality.Font.Style := [fsBold];

  LblQualityVal := TLabel.Create(Self);
  LblQualityVal.Parent := Self;
  LblQualityVal.Left := 400;
  LblQualityVal.Top := 36;
  LblQualityVal.Width := 48;
  LblQualityVal.Alignment := taRightJustify;
  LblQualityVal.Caption := IntToStr(DEFAULT_WEBP_QUALITY) + '%';

  TrackQuality := TTrackBar.Create(Self);
  TrackQuality.Parent := Self;
  TrackQuality.Left := 12;
  TrackQuality.Top := 32;
  TrackQuality.Width := 380;
  TrackQuality.Min := WEBP_QUALITY_MIN;
  TrackQuality.Max := WEBP_QUALITY_MAX;
  TrackQuality.Frequency := 5;
  TrackQuality.Position := DEFAULT_WEBP_QUALITY;
  TrackQuality.OnChange := @TrackQualityChange;

  CbReplaceOnlySmaller := TCheckBox.Create(Self);
  CbReplaceOnlySmaller.Parent := Self;
  CbReplaceOnlySmaller.Left := 12;
  CbReplaceOnlySmaller.Top := 80;
  CbReplaceOnlySmaller.Width := 436;
  CbReplaceOnlySmaller.Caption := 'Replace only if smaller';
  CbReplaceOnlySmaller.Checked := True;

  CbSkipExistingWebP := TCheckBox.Create(Self);
  CbSkipExistingWebP.Parent := Self;
  CbSkipExistingWebP.Left := 12;
  CbSkipExistingWebP.Top := 108;
  CbSkipExistingWebP.Width := 436;
  CbSkipExistingWebP.Caption := 'Skip existing WebP';
  CbSkipExistingWebP.Checked := True;

  CbRemoveComicInfo := TCheckBox.Create(Self);
  CbRemoveComicInfo.Parent := Self;
  CbRemoveComicInfo.Left := 12;
  CbRemoveComicInfo.Top := 136;
  CbRemoveComicInfo.Width := 436;
  CbRemoveComicInfo.Caption := 'Remove ComicInfo.xml';
  CbRemoveComicInfo.Checked := True;

  CbRenumber := TCheckBox.Create(Self);
  CbRenumber.Parent := Self;
  CbRenumber.Left := 12;
  CbRenumber.Top := 164;
  CbRenumber.Width := 436;
  CbRenumber.Caption := 'Rename to page_NNNN.*';
  CbRenumber.Checked := True;

  GroupBackup := TRadioGroup.Create(Self);
  GroupBackup.Parent := Self;
  GroupBackup.Left := 12;
  GroupBackup.Top := 196;
  GroupBackup.Width := 436;
  GroupBackup.Height := 72;
  GroupBackup.Caption := 'Original file';
  GroupBackup.Columns := 2;
  GroupBackup.Items.Add('Create backup (_OLD.cbz)');
  GroupBackup.Items.Add('Permanently delete');
  GroupBackup.ItemIndex := 0;

  PanelBottom := CreateBottomPanel(Self, 44);

  BtnConvert := CreateDialogButton(PanelBottom, '&Convert', 284, 7, mrOK,
    True, False);
  BtnClose := CreateDialogButton(PanelBottom, '&Cancel', 372, 7, mrCancel,
    False, True);

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

end.
