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
    procedure FormCreate(Sender: TObject);
  private
    CbSkipExisting: TCheckBox;
    CbDeleteSource: TCheckBox;
    SpinThreads: TSpinEdit;
    PanelBottom: TPanel;
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
  Caption := 'Convert CBR to CBZ';
  ClientWidth := 460;
  ClientHeight := 200;

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

  { 0 = automatic (one worker per CPU core, capped at 4); 1 = sequential. }
  with TLabel.Create(Self) do
  begin
    Parent := Self;
    Left := 12;
    Top := 76;
    Width := 120;
    Caption := 'Parallel threads';
  end;
  SpinThreads := TSpinEdit.Create(Self);
  SpinThreads.Parent := Self;
  SpinThreads.Left := 328;
  SpinThreads.Top := 72;
  SpinThreads.Width := 120;
  SpinThreads.MinValue := 0;
  SpinThreads.MaxValue := 32;
  SpinThreads.Value := 0;

  PanelBottom := CreateBottomPanel(Self, 44);

  CreateDialogButton(PanelBottom, '&Convert', 284, 7, mrOK, True, False);
  CreateDialogButton(PanelBottom, '&Cancel', 372, 7, mrCancel, False, True);

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
