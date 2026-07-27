{
  udlgwebp — WebP Conversion Options Dialog
  -----------------------------------------
  Lets the user configure settings for a batch WebP image conversion
  run.  Exposes the chosen quality, backup policy, and several
  behavioural flags (skip existing, replace only if smaller, remove
  ComicInfo metadata, renumber pages) through public properties that
  the calling code reads after the dialog is closed with OK.
}
unit udlgwebp;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls;

type

  {
    TdlgWebp — Dialog for configuring WebP conversion parameters.

    All user-facing controls are published so the LFM loader can wire
    them up.  The public properties below are read by the caller after
    the dialog returns mrOk to learn the user's choices.
  }
  TdlgWebp = class(TForm)
    BtnConvert: TButton;
    BtnClose: TButton;
    CbReplaceOnlySmaller: TCheckBox;
    CbSkipExistingWebP: TCheckBox;
    CbRemoveComicInfo: TCheckBox;
    CbRenumber: TCheckBox;
    GroupBackup: TRadioGroup;
    LabelQuality: TLabel;
    LblQualityVal: TLabel;
    PanelBottom: TPanel;
    TrackQuality: TTrackBar;
    { Sets default trackbar range and initial quality value. }
    procedure FormCreate(Sender: TObject);
    { Updates the quality-percentage label whenever the slider moves. }
    procedure TrackQualityChange(Sender: TObject);
  private
    { --- Private getters for public properties --- }
    function GetQuality: integer;
    function GetBackup: boolean;
    function GetReplaceOnlyIfSmaller: boolean;
    function GetSkipExistingWebP: boolean;
    function GetRemoveComicInfo: boolean;
    function GetRenumberPages: boolean;
  public
    { WebP encoding quality, 30–100 (default 75). }
    property Quality: integer read GetQuality;
    { If true, replace the original image only when the WebP version is smaller. }
    property ReplaceOnlyIfSmaller: boolean read GetReplaceOnlyIfSmaller;
    { If true, skip conversion when a .webp counterpart already exists. }
    property SkipExistingWebP: boolean read GetSkipExistingWebP;
    { If true, strip ComicInfo metadata during conversion. }
    property RemoveComicInfo: boolean read GetRemoveComicInfo;
    { If true, renumber pages sequentially after conversion. }
    property RenumberPages: boolean read GetRenumberPages;
    { If true, keep a backup copy of the original file. }
    property BackupOld: boolean read GetBackup;
  end;

implementation

{$R *.lfm}

{ TdlgWebp }

{
  FormCreate — Initialise the quality trackbar with safe defaults.
  Quality range is 30–100 (below 30 produces unacceptable artefacts).
  The frequency of 5 makes the trackbar snap to multiples of 5.
}
procedure TdlgWebp.FormCreate(Sender: TObject);
begin
  TrackQuality.Min := 30;
  TrackQuality.Max := 100;
  TrackQuality.Frequency := 5;       // snap to multiples of 5 %
  TrackQuality.Position := 75;       // default quality
  LblQualityVal.Caption := '75%';
end;

{
  TrackQualityChange — Reflect the current slider position in the
  percentage label so the user always sees the selected quality.
}
procedure TdlgWebp.TrackQualityChange(Sender: TObject);
begin
  LblQualityVal.Caption := IntToStr(TrackQuality.Position) + '%';
end;

{ Return the WebP encoding quality value from the trackbar (30–100). }
function TdlgWebp.GetQuality: integer;
begin
  Result := TrackQuality.Position;
end;

{ Return whether the user wants to replace originals only when the
  WebP version is smaller. }
function TdlgWebp.GetReplaceOnlyIfSmaller: boolean;
begin
  Result := CbReplaceOnlySmaller.Checked;
end;

{ Return whether to skip images that already have a .webp counterpart. }
function TdlgWebp.GetSkipExistingWebP: boolean;
begin
  Result := CbSkipExistingWebP.Checked;
end;

{ Return whether ComicInfo metadata should be stripped. }
function TdlgWebp.GetRemoveComicInfo: boolean;
begin
  Result := CbRemoveComicInfo.Checked;
end;

{ Return whether pages should be renumbered sequentially. }
function TdlgWebp.GetRenumberPages: boolean;
begin
  Result := CbRenumber.Checked;
end;

{
  Return the backup preference.
  RadioGroup item 0 = "Backup", item 1 = "Delete".
  Any selection other than "Delete" (index 1) is treated as backup.
}
function TdlgWebp.GetBackup: boolean;
begin
  Result := GroupBackup.ItemIndex <> 1; // 0=Backup, 1=Delete
end;

end.
