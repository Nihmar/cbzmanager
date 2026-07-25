unit uPageEditModel;

{
  In-memory page editing model for the CBZ preview pane.
  Types and the background save thread — pure data + I/O, no GUI dependencies.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, IntfGraphics, uservicebase, uZipEditor;

type
  { In-memory page state for the editing model }
  TPageState = record
    Name: string;          // current entry name inside CBZ
    OrigName: string;      // original entry name at open time
    Image: TLazIntfImage;  // cached thumbnail (writable copy)
    Gone: boolean;         // marked for deletion
    OrigIndex: integer;    // original position at open time
  end;
  TPageStates = array of TPageState;

  TChangeKind = (ckDeleted, ckMoved);

  TChange = record
    Kind: TChangeKind;
    PageName: string;
  end;
  TChanges = array of TChange;

  { Result record for background save-changes thread }
  TSaveChangesResult = record
    Success: boolean;
    ErrorMsg: string;
  end;

  { Background thread for saving in-memory page edits to disk.
    Takes a snapshot of FPages so the main thread stays responsive. }
  TSaveChangesThread = class(TThread)
  private
    FPageFile: string;
    FPages: TPageStates;
    FRenumber: boolean;
    FResult: TSaveChangesResult;
    FOnProgress: TProgressEvent;
    FPendingPct: integer;
    FPendingMsg: string;
    procedure SyncProgress;
    procedure DoProgress(APercent: integer; const AMsg: string);
  protected
    procedure Execute; override;
  public
    constructor Create(const APageFile: string; const APages: TPageStates;
      ARenumber: boolean; AOnProgress: TProgressEvent);
    property Result: TSaveChangesResult read FResult;
  end;

implementation

{ TSaveChangesThread }

constructor TSaveChangesThread.Create(const APageFile: string;
  const APages: TPageStates; ARenumber: boolean;
  AOnProgress: TProgressEvent);
var
  i: integer;
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FPageFile := APageFile;
  SetLength(FPages, Length(APages));
  for i := 0 to High(APages) do
  begin
    FPages[i].Name := APages[i].Name;
    FPages[i].OrigName := APages[i].OrigName;
    FPages[i].Gone := APages[i].Gone;
    { Image reference not copied — thread doesn't need it }
  end;
  FRenumber := ARenumber;
  FOnProgress := AOnProgress;
  FResult.Success := False;
end;

procedure TSaveChangesThread.DoProgress(APercent: integer; const AMsg: string);
begin
  FPendingPct := APercent;
  FPendingMsg := AMsg;
  if Assigned(FOnProgress) then
    TThread.Queue(nil, @SyncProgress);
end;

procedure TSaveChangesThread.SyncProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(FPendingPct, FPendingMsg);
end;

procedure TSaveChangesThread.Execute;
var
  i, j, PageNum: integer;
  AllEntries, OutEntries: TZipEntries;
  NewName, PageExt: string;
begin
  try
    DoProgress(0, 'Reading all entries into RAM...');
    AllEntries := CollectZipEntries(FPageFile);
    try
      SetLength(OutEntries, 0);
      for i := 0 to High(FPages) do
      begin
        if Terminated then Exit;
        if FPages[i].Gone then Continue;
        for j := 0 to High(AllEntries) do
          if SameText(AllEntries[j].Name, FPages[i].OrigName) then
          begin
            SetLength(OutEntries, Length(OutEntries) + 1);
            if FRenumber then
            begin
              PageNum := Length(OutEntries);
              PageExt := ExtractFileExt(FPages[i].Name);
              NewName := FormatPageName(PageNum, 4, PageExt);
            end
            else
              NewName := FPages[i].Name;
            OutEntries[High(OutEntries)].Name := NewName;
            OutEntries[High(OutEntries)].Data := TMemoryStream.Create;
            AllEntries[j].Data.Position := 0;
            OutEntries[High(OutEntries)].Data.CopyFrom(AllEntries[j].Data,
              AllEntries[j].Data.Size);
            Break;
          end;
      end;
      DoProgress(60, 'Writing new CBZ...');
      if not ReplaceCBZ(FPageFile, OutEntries) then
      begin
        FResult.ErrorMsg := 'Replace failed — check disk space or permissions';
        FreeZipEntries(OutEntries);
        Exit;
      end;
      FreeZipEntries(OutEntries);
      FResult.Success := True;
      DoProgress(100, 'Save complete');
    finally
      FreeZipEntries(AllEntries);
    end;
  except
    on E: Exception do
    begin
      FResult.Success := False;
      FResult.ErrorMsg := E.Message;
    end;
  end;
end;

end.
