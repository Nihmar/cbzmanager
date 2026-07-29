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

const
  DLG_BTN_WIDTH = 80;
  DLG_BTN_HEIGHT = 30;

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

{ Creates the bottom button strip: alBottom, no bevel, the given height. }
function CreateBottomPanel(ADialog: TForm; AHeight: integer): TPanel;

{ Creates an 80x30 dialog button parented to AParent.  Left/Top position and
  the modal/default/cancel flags are supplied by the caller; anything more
  exotic (anchors, OnClick) is set on the returned button. }
function CreateDialogButton(AParent: TWinControl; const ACaption: string;
  ALeft, ATop: integer; AModalResult: TModalResult;
  ADefault, ACancel: boolean): TButton;

{ Creates a read-only, grid-lined vsReport list view filling the dialog. }
function CreateReportListView(AParent: TWinControl; ACheckboxes: boolean): TListView;

implementation

{$R *.lfm}

function CreateBottomPanel(ADialog: TForm; AHeight: integer): TPanel;
begin
  Result := TPanel.Create(ADialog);
  Result.Parent := ADialog;
  Result.Align := alBottom;
  Result.Height := AHeight;
  Result.BevelOuter := bvNone;
end;

function CreateDialogButton(AParent: TWinControl; const ACaption: string;
  ALeft, ATop: integer; AModalResult: TModalResult;
  ADefault, ACancel: boolean): TButton;
begin
  Result := TButton.Create(AParent.Owner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := DLG_BTN_WIDTH;
  Result.Height := DLG_BTN_HEIGHT;
  Result.ModalResult := AModalResult;
  Result.Default := ADefault;
  Result.Cancel := ACancel;
end;

function CreateReportListView(AParent: TWinControl; ACheckboxes: boolean): TListView;
begin
  Result := TListView.Create(AParent);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.BorderSpacing.Around := 8;
  Result.ViewStyle := vsReport;
  Result.ReadOnly := True;
  Result.RowSelect := True;
  Result.GridLines := True;
  Result.Checkboxes := ACheckboxes;
end;

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
