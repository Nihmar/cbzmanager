unit udynlib;

{
  TDynLib – lazy, thread-safe loader for a dynamic library chosen from a list
  of candidate file names.

  Shared by uwebp (libwebp) and uarchive (libarchive), which used to carry
  near-identical load/guard/unload boilerplate.  The class keeps the handle,
  the name that actually loaded and the "already tried" flag behind one
  critical section, so callers only have to wire their symbols:

    Lib := TDynLib.Create(['libfoo.so.1', 'libfoo.so'], 'Foo: not found');
    ...
    if not Lib.TryInit then Exit;
    Pointer(_FooDo) := Lib.Symbol('foo_do');
    if not Assigned(_FooDo) then Lib.Reject('missing core symbols');

  Unloading happens in Reject or the destructor.  Logging stays in the
  owning units (the messages are library-specific).
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DynLibs;

type
  TDynLib = class
  private
    FLock: TRTLCriticalSection;
    FNames: TStringArray;
    FNotFoundLog: string;
    FHandle: TLibHandle;
    FName: string;
    FTried: boolean;
  public
    constructor Create(const ANames: array of string;
      const ANotFoundLog: string);
    destructor Destroy; override;
    { Loads the first candidate that opens, exactly once and thread-safe.
      Returns True when THIS call performed the load, False when another call
      (or thread) already did — including a failed attempt. }
    function TryInit: boolean;
    { Address of AName, or nil when the library lacks it.  Call only after
      TryInit returned True (no lock: the init already happened-before). }
    function Symbol(const AName: string): Pointer;
    { Unloads after a capability check failed (the library was found but
      cannot do the job), leaving Tried set so we do not retry. }
    procedure Reject;
    { Non-nil when a library was loaded successfully. }
    property Handle: TLibHandle read FHandle;
    { File name of the library that actually loaded. }
    property LibraryName: string read FName;
    property Tried: boolean read FTried;
  end;

implementation

uses
  uLog;

constructor TDynLib.Create(const ANames: array of string;
  const ANotFoundLog: string);
var
  i: integer;
begin
  inherited Create;
  SetLength(FNames, Length(ANames));
  for i := 0 to High(ANames) do
    FNames[i] := ANames[i];
  FNotFoundLog := ANotFoundLog;
  FHandle := NilHandle;
  FName := '';
  FTried := False;
  InitCriticalSection(FLock);
end;

destructor TDynLib.Destroy;
begin
  if FHandle <> NilHandle then
  begin
    UnloadLibrary(FHandle);
    FHandle := NilHandle;
  end;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

function TDynLib.TryInit: boolean;
var
  i: integer;
begin
  EnterCriticalSection(FLock);
  try
    if FTried then
      Exit(False);
    FTried := True;
    for i := 0 to High(FNames) do
    begin
      FHandle := LoadLibrary(FNames[i]);
      if FHandle <> NilHandle then
      begin
        FName := FNames[i];
        Break;
      end;
    end;
    if FHandle = NilHandle then
    begin
      Log('%s', [FNotFoundLog]);
      Exit(False);
    end;
    Result := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TDynLib.Symbol(const AName: string): Pointer;
begin
  if FHandle = NilHandle then
    Exit(nil);
  Result := GetProcedureAddress(FHandle, AName);
end;

procedure TDynLib.Reject;
begin
  EnterCriticalSection(FLock);
  try
    if FHandle <> NilHandle then
    begin
      UnloadLibrary(FHandle);
      FHandle := NilHandle;
    end;
    FName := '';
  finally
    LeaveCriticalSection(FLock);
  end;
end;

end.
