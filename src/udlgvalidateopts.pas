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
    procedure FormCreate(Sender: TObject);
  private
    SpinThreads: TSpinEdit;
    PanelBottom: TPanel;
    procedure LoadSettings; override;
    procedure SaveSettings; override;
    function GetThreads: integer;
  public
    property Threads: integer read GetThreads;
  end;

implementation

procedure TdlgValidateOpts.FormCreate(Sender: TObject);
begin
  Caption := 'Validate CBZ files';
  ClientWidth := 460;
  ClientHeight := 150;

  { 0 = automatic (one worker per CPU core, capped at 8); 1 = sequential. }
  with TLabel.Create(Self) do
  begin
    Parent := Self;
    Left := 12;
    Top := 36;
    Width := 200;
    Caption := 'Parallel decode threads';
  end;
  SpinThreads := TSpinEdit.Create(Self);
  SpinThreads.Parent := Self;
  SpinThreads.Left := 328;
  SpinThreads.Top := 32;
  SpinThreads.Width := 120;
  SpinThreads.MinValue := 0;
  SpinThreads.MaxValue := 32;
  SpinThreads.Value := 0;

  PanelBottom := CreateBottomPanel(Self, 44);

  CreateDialogButton(PanelBottom, '&Validate', 284, 7, mrOK, True, False);
  CreateDialogButton(PanelBottom, '&Cancel', 372, 7, mrCancel, False, True);

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
