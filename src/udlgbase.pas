unit udlgbase;

{ ============================================================================
  udlgbase – Shared construction helpers for the programmatically-built
  dialogs.

  Every dialog in this project is streamed from an empty .lfm shell and builds
  its controls in FormCreate.  That led to the same chrome being copy-pasted
  across all eight dialogs: the bsDialog border, an alBottom button panel,
  80x30 action buttons, and read-only vsReport list views.  These helpers
  centralise those patterns so each dialog only declares what actually differs.
  ============================================================================ }

{$mode ObjFPC}{$H+}

interface

uses
  Classes, Controls, Forms, StdCtrls, ComCtrls, ExtCtrls, usettings;

const
  DLG_BTN_WIDTH = 80;
  DLG_BTN_HEIGHT = 30;

type
  { Base class for the small settings dialogs.  When the dialog closes with
    ModalResult = mrOK it persists the user's choices via SaveSettings and
    flushes AppSettings.  Subclasses override LoadSettings / SaveSettings and
    call InitSettingsPersistence from FormCreate, after building their
    controls (which both the load and the OnClose wiring rely on). }
  TSettingsDialog = class(TForm)
  protected
    procedure LoadSettings; virtual;
    procedure SaveSettings; virtual;
  public
    { Load initial values and wire OnClose to persist on OK. }
    procedure InitSettingsPersistence;
    procedure SettingsFormClose(Sender: TObject; var CloseAction: TCloseAction);
  end;

{ Applies the standard modal-dialog chrome (fixed border, system menu only). }
procedure InitDialogChrome(ADialog: TForm);

{ Creates the bottom button strip: alBottom, no bevel, the given height. }
function CreateBottomPanel(ADialog: TForm; AHeight: integer): TPanel;

{ Creates an 80x30 dialog button parented to AParent.  Left/Top position and
  the modal/default/cancel flags are supplied by the caller; anything more
  exotic (anchors, OnClick) is set on the returned button. }
function CreateDialogButton(AParent: TWinControl; const ACaption: string;
  ALeft, ATop: integer; AModalResult: TModalResult;
  ADefault, ACancel: boolean): TButton;

{ Creates a read-only, grid-lined vsReport list view filling the dialog. }
function CreateReportListView(ADialog: TForm; ACheckboxes: boolean): TListView;

implementation

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
  if ModalResult = mrOK then
  begin
    SaveSettings;
    AppSettings.UpdateFile;
  end;
end;

procedure InitDialogChrome(ADialog: TForm);
begin
  ADialog.BorderStyle := bsDialog;
  ADialog.BorderIcons := [biSystemMenu];
end;

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

function CreateReportListView(ADialog: TForm; ACheckboxes: boolean): TListView;
begin
  Result := TListView.Create(ADialog);
  Result.Parent := ADialog;
  Result.Align := alClient;
  Result.BorderSpacing.Around := 8;
  Result.ViewStyle := vsReport;
  Result.ReadOnly := True;
  Result.RowSelect := True;
  Result.GridLines := True;
  Result.Checkboxes := ACheckboxes;
end;

end.
