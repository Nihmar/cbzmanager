unit udlgvalidateopts;

{$mode ObjFPC}{$H+}

{
  Options dialog for the deep CBZ validation: parallel decode workers.
  0 = automatic (one worker per CPU core, capped at 8); 1 = sequential.
  Settings persist via the shared INI settings store.
}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls,
  ExtCtrls, Spin, udlgbase, usettings;

type
  TdlgValidateOpts = class(TSettingsDialog)
    { Wired from the .lfm — controls must be published for RTTI lookup. }
    LblThreads: TLabel;
    SpinThreads: TSpinEdit;
    PanelBottom: TPanel;
    BtnValidate: TButton;
    BtnCancel: TButton;
    procedure FormCreate(Sender: TObject);
  private
    procedure LoadSettings; override;
    procedure SaveSettings; override;
    function GetThreads: integer;
  public
    property Threads: integer read GetThreads;
  end;

implementation

{$R *.lfm}

procedure TdlgValidateOpts.FormCreate(Sender: TObject);
begin
  InitSettingsPersistence;
end;

procedure TdlgValidateOpts.LoadSettings;
begin
  SpinThreads.Value := AppSettings.ReadInteger('Validate', 'Threads', 0);
end;

procedure TdlgValidateOpts.SaveSettings;
begin
  AppSettings.WriteInteger('Validate', 'Threads', SpinThreads.Value);
end;

function TdlgValidateOpts.GetThreads: integer;
begin
  Result := SpinThreads.Value;
end;

end.
