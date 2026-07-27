unit uLog;

{
  Logger minimale thread-safe su file, accanto all'eseguibile.
  Il file viene troncato ad ogni avvio dell'applicazione.

  Lo stream resta aperto per tutta la sessione: una riga scritta e' una riga
  che l'applicazione ha davvero raggiunto. Le scritture non sono bufferizzate
  in spazio utente, quindi il log sopravvive anche a un crash del processo.
}

{$mode ObjFPC}{$H+}

interface

{ Percorso del file di log effettivamente usato. }
function LogFileName: string;

{ Scrive una riga con timestamp e id del thread chiamante. }
procedure Log(const Msg: string);
procedure Log(const Fmt: string; const Args: array of const);

implementation

uses
  Classes, SysUtils;

var
  LogLock: TRTLCriticalSection;
  LogStream: TFileStream = nil;
  LogPath: string = '';
  LogReady: boolean = False;

function TryOpen(const APath: string): boolean;
begin
  Result := False;
  try
    LogStream := TFileStream.Create(APath, fmCreate or fmShareDenyNone);
    LogPath := APath;
    Result := True;
  except
    LogStream := nil;
  end;
end;

{ Da chiamare con LogLock gia' acquisito. }
procedure InitLog;
begin
  if LogReady then Exit;
  LogReady := True;
  if TryOpen(ExtractFilePath(ParamStr(0)) + 'cbzmanager.log') then Exit;
  { cartella dell'exe non scrivibile: ripiega sulla temp }
  TryOpen(GetTempDir + 'cbzmanager.log');
end;

function LogFileName: string;
begin
  EnterCriticalSection(LogLock);
  try
    InitLog;
    Result := LogPath;
  finally
    LeaveCriticalSection(LogLock);
  end;
end;

procedure Log(const Msg: string);
var
  Line: rawbytestring;
begin
  EnterCriticalSection(LogLock);
  try
    InitLog;
    if LogStream = nil then Exit;
    Line := rawbytestring(FormatDateTime('hh:nn:ss.zzz', Now) + ' [t' +
      IntToStr(PtrUInt(GetCurrentThreadId)) + '] ' + Msg + LineEnding);
    try
      LogStream.WriteBuffer(Line[1], Length(Line));
    except
      { il logging non deve mai far fallire il chiamante }
    end;
  finally
    LeaveCriticalSection(LogLock);
  end;
end;

procedure Log(const Fmt: string; const Args: array of const);
begin
  try
    Log(Format(Fmt, Args));
  except
    Log(Fmt);
  end;
end;

initialization
  InitCriticalSection(LogLock);

finalization
  FreeAndNil(LogStream);
  DoneCriticalSection(LogLock);

end.
