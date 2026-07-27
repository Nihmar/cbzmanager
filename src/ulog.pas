unit uLog;

{
  uLog — Logger minimale thread-safe su file.
  ---------------------------------------------------------------------------
  Scrive messaggi con timestamp e thread-id nel file "cbzmanager.log",
  creato accanto all'eseguibile (o nella directory temporanea di sistema
  se quella dell'exe non è scrivibile).

  Il file viene troncato ad ogni avvio dell'applicazione.
  Lo stream resta aperto per tutta la sessione: una riga scritta è una riga
  che l'applicazione ha davvero raggiunto. Le scritture non sono bufferizzate
  in spazio utente, quindi il log sopravvive anche a un crash del processo.

  Tutte le scritture sono serializzate da una critical section: il logging
  è safe da qualsiasi thread senza rischio di deadlock.

  Il modulo non genera mai eccezioni verso il chiamante: se la scrittura
  fallisce l'errore viene silenziosamente ignorato.
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
  { Mutex condiviso: serializza InitLog e tutte le scritture. }
  LogLock: TRTLCriticalSection;
  { Stream aperto per tutta la sessione; nil se non inizializzato o fallito. }
  LogStream: TFileStream = nil;
  { Percorso effettivo del file di log (può essere nella temp). }
  LogPath: string = '';
  { Diventa True dopo il primo tentativo di apertura, anche se fallito. }
  LogReady: boolean = False;

{ Tenta di creare/azzerare il file di log in APath.
  Restituisce True e imposta LogStream + LogPath in caso di successo;
  False (con LogStream = nil) altrimenti. Non solleva eccezioni. }
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

{ Inizializzazione lazy e thread-safe del logger.
  Chiamata internamente da ogni funzione pubblica; idempotente.
  PRE: il chiamante deve aver già acquisito LogLock. }
procedure InitLog;
begin
  if LogReady then Exit;
  LogReady := True;
  if TryOpen(ExtractFilePath(ParamStr(0)) + 'cbzmanager.log') then Exit;
  { cartella dell'exe non scrivibile: ripiega sulla temp }
  TryOpen(GetTempDir + 'cbzmanager.log');
end;

{ Restituisce il percorso del file di log effettivamente in uso,
  oppure stringa vuota se l'apertura non è riuscita. }
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

{ Scrive Msg nel log preceduto da timestamp e thread-id.
  Thread-safe; se il log non è disponibile ritorna silenziosamente. }
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

{ Formatta Fmt con Args tramite Format() e scrive il risultato nel log.
  Se la formattazione fallisce (es. placeholder errati), scrive Fmt tal quale. }
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
