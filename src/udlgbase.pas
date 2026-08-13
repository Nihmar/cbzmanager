unit udlgbase;

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Forms,
  Controls,
  Graphics,
  Dialogs,
  ExtCtrls,
  StdCtrls,
  ComCtrls,
  usettings;

type
  { Base class for the small settings dialogs.  When the dialog closes with
    ModalResult = mrOK it persists the user's choices via SaveSettings and
    flushes AppSettings.  Subclasses override LoadSettings / SaveSettings and
    call InitSettingsPersistence from FormCreate, after building their
    controls (which both the load and the OnClose wiring rely on). }

  { TSettingsDialog }

  TSettingsDialog = class(TForm)
  private
  protected
    procedure LoadSettings; virtual;
    procedure SaveSettings; virtual;
  public
    { Load initial values and wire OnClose to persist on OK. }
    procedure InitSettingsPersistence;
    procedure SettingsFormClose(Sender: TObject; var CloseAction: TCloseAction);
  end;

implementation

{$R *.lfm}

{ TSettingsDialog }

procedure TSettingsDialog.LoadSettings;
begin
  { no-op by default; subclasses override }
end;

procedure TSettingsDialog.SaveSettings;
begin
  { no-op by default; subclasses override }
end;

procedure TSettingsDialog.InitSettingsPersistence;
begin
  LoadSettings;
  OnClose := @SettingsFormClose;
end;

procedure TSettingsDialog.SettingsFormClose(Sender: TObject;
  var CloseAction: TCloseAction);
begin
  if ModalResult = mrOk then
  begin
    SaveSettings;
    AppSettings.UpdateFile;
  end;
end;

end.
