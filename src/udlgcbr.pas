unit udlgcbr;

{$mode ObjFPC}{$H+}

{
  Conversion options dialog for CBR-to-CBZ batch conversion: skip files
  whose .cbz target already exists (default) and delete the .cbr source
  after a successful conversion (default: keep).  Settings persist via
  the shared INI settings store.
}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls,
  ExtCtrls, udlgbase, usettings;

type
  TdlgCbr = class(TSettingsDialog)
    procedure FormCreate(Sender: TObject);
  private
    CbSkipExisting: TCheckBox;
    CbDeleteSource: TCheckBox;
    PanelBottom: TPanel;
    procedure LoadSettings; override;
    procedure SaveSettings; override;
    function GetSkipExisting: boolean;
    function GetDeleteSource: boolean;
  public
    property SkipExisting: boolean read GetSkipExisting;
    property DeleteSource: boolean read GetDeleteSource;
  end;

implementation

{$R *.lfm}

procedure TdlgCbr.FormCreate(Sender: TObject);
begin
  Caption := 'Convert CBR to CBZ';
  ClientWidth := 460;
  ClientHeight := 150;

  CbSkipExisting := TCheckBox.Create(Self);
  CbSkipExisting.Parent := Self;
  CbSkipExisting.Left := 12;
  CbSkipExisting.Top := 12;
  CbSkipExisting.Width := 436;
  CbSkipExisting.Caption := 'Skip files whose .cbz target already exists';
  CbSkipExisting.Checked := True;

  CbDeleteSource := TCheckBox.Create(Self);
  CbDeleteSource.Parent := Self;
  CbDeleteSource.Left := 12;
  CbDeleteSource.Top := 40;
  CbDeleteSource.Width := 436;
  CbDeleteSource.Caption := 'Delete the .cbr source after conversion';

  PanelBottom := CreateBottomPanel(Self, 44);

  CreateDialogButton(PanelBottom, '&Convert', 284, 7, mrOK, True, False);
  CreateDialogButton(PanelBottom, '&Cancel', 372, 7, mrCancel, False, True);

  InitSettingsPersistence;
end;

procedure TdlgCbr.LoadSettings;
begin
  CbSkipExisting.Checked := AppSettings.ReadBool('CBR', 'SkipExisting', True);
  CbDeleteSource.Checked := AppSettings.ReadBool('CBR', 'DeleteSource', False);
end;

procedure TdlgCbr.SaveSettings;
begin
  AppSettings.WriteBool('CBR', 'SkipExisting', CbSkipExisting.Checked);
  AppSettings.WriteBool('CBR', 'DeleteSource', CbDeleteSource.Checked);
end;

function TdlgCbr.GetSkipExisting: boolean;
begin
  Result := CbSkipExisting.Checked;
end;

function TdlgCbr.GetDeleteSource: boolean;
begin
  Result := CbDeleteSource.Checked;
end;

end.
