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
  ExtCtrls, Spin, udlgbase, usettings;

type
  TdlgCbr = class(TSettingsDialog)
    { Wired from the .lfm — controls must be published for RTTI lookup. }
    CbSkipExisting: TCheckBox;
    CbDeleteSource: TCheckBox;
    LblThreads: TLabel;
    SpinThreads: TSpinEdit;
    PanelBottom: TPanel;
    BtnConvert: TButton;
    BtnClose: TButton;
    procedure FormCreate(Sender: TObject);
  private
    procedure LoadSettings; override;
    procedure SaveSettings; override;
    function GetSkipExisting: boolean;
    function GetDeleteSource: boolean;
    function GetThreads: integer;
  public
    property SkipExisting: boolean read GetSkipExisting;
    property DeleteSource: boolean read GetDeleteSource;
    property Threads: integer read GetThreads;
  end;

implementation

{$R *.lfm}

procedure TdlgCbr.FormCreate(Sender: TObject);
begin
  InitSettingsPersistence;
end;

procedure TdlgCbr.LoadSettings;
begin
  CbSkipExisting.Checked := AppSettings.ReadBool('CBR', 'SkipExisting', True);
  CbDeleteSource.Checked := AppSettings.ReadBool('CBR', 'DeleteSource', False);
  SpinThreads.Value := AppSettings.ReadInteger('CBR', 'Threads', 0);
end;

procedure TdlgCbr.SaveSettings;
begin
  AppSettings.WriteBool('CBR', 'SkipExisting', CbSkipExisting.Checked);
  AppSettings.WriteBool('CBR', 'DeleteSource', CbDeleteSource.Checked);
  AppSettings.WriteInteger('CBR', 'Threads', SpinThreads.Value);
end;

function TdlgCbr.GetSkipExisting: boolean;
begin
  Result := CbSkipExisting.Checked;
end;

function TdlgCbr.GetDeleteSource: boolean;
begin
  Result := CbDeleteSource.Checked;
end;

function TdlgCbr.GetThreads: integer;
begin
  Result := SpinThreads.Value;
end;

end.
