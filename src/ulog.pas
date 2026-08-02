unit uLog;

{
  uLog — Minimal thread-safe file logger.
  ---------------------------------------------------------------------------
  Writes timestamped, thread-id annotated messages to the "cbzmanager.log"
  file, created next to the executable (or in the system temp directory if
  the executable's folder is not writable).

  The file is truncated at every application start.
  The stream stays open for the whole session: a written line is a line the
  application really reached. Writes are not buffered in user space, so the
  log survives even a process crash.

  All writes are serialized by a critical section: logging is safe from any
  thread with no deadlock risk.

  The module never raises exceptions towards the caller: if a write fails
  the error is silently ignored.
}

{$mode ObjFPC}{$H+}

interface

type
  { Callback invoked for every log message written.  Called from the logging
    thread inside the critical section — keep it fast (e.g. TThread.Queue). }
  TLogObserver = procedure(const AMsg: string) of object;

{ Path of the log file actually in use. }
function LogFileName: string;

{
  Registers / removes an observer that receives every log message.
  Only one observer at a time — later registrations overwrite. }
procedure RegisterLogObserver(AObserver: TLogObserver);
procedure UnregisterLogObserver;

{ Writes a line with the timestamp and the calling thread id. }
procedure Log(const Msg: string);
procedure Log(const Fmt: string; const Args: array of const);

implementation

uses
  Classes, SysUtils;

var
  { Shared mutex: serializes InitLog and all writes. }
  LogLock: TRTLCriticalSection;
  { Stream kept open for the whole session; nil if not initialized or failed. }
  LogStream: TFileStream = nil;
  { Actual log file path (may be in the temp dir). }
  LogPath: string = '';
  { Becomes True after the first open attempt, even if it failed. }
  LogReady: boolean = False;
  { Registered observer (nil = none).  Called inside LogLock. }
  LogObserver: TLogObserver = nil;

{
  Attempts to create/truncate the log file at APath.
  Returns True and sets LogStream + LogPath on success;
  False (with LogStream = nil) otherwise. Never raises. }
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

{
  Lazy, thread-safe initialization of the logger.
  Called internally by every public function; idempotent.
  PRE: the caller must already hold LogLock. }
procedure InitLog;
begin
  if LogReady then Exit;
  LogReady := True;
  if TryOpen(ExtractFilePath(ParamStr(0)) + 'cbzmanager.log') then Exit;
  { executable folder not writable: fall back to the temp dir }
  TryOpen(GetTempDir + 'cbzmanager.log');
end;

{
  Returns the path of the log file actually in use,
  or an empty string if it could not be opened. }
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

{
  Registers an observer that will receive every log message (timestamp
  included). The callback is invoked inside LogLock — it must be fast. }
procedure RegisterLogObserver(AObserver: TLogObserver);
begin
  EnterCriticalSection(LogLock);
  try
    LogObserver := AObserver;
  finally
    LeaveCriticalSection(LogLock);
  end;
end;

{ Removes the registered observer.  Thread-safe and idempotent. }
procedure UnregisterLogObserver;
begin
  EnterCriticalSection(LogLock);
  try
    LogObserver := nil;
  finally
    LeaveCriticalSection(LogLock);
  end;
end;

{
  Writes Msg to the log preceded by timestamp and thread-id.
  Thread-safe; returns silently if the log is unavailable. }
procedure Log(const Msg: string);
var
  Line: rawbytestring;
  Obs: TLogObserver;
begin
  EnterCriticalSection(LogLock);
  try
    InitLog;
    Obs := LogObserver;  // snapshot inside the lock
    if LogStream = nil then
    begin
      if not Assigned(Obs) then Exit;
      // Still notify the observer even if the file log is unavailable.
      // Use the raw message sans timestamp so the UI can still show it.
      // We can't build Line below, so just deliver the raw Msg.
      Obs(Msg);
      Exit;
    end;
    Line := rawbytestring(FormatDateTime('hh:nn:ss.zzz', Now) + ' [t' +
      IntToStr(PtrUInt(GetCurrentThreadId)) + '] ' + Msg + LineEnding);
    try
      LogStream.WriteBuffer(Line[1], Length(Line));
    except
      { logging must never make the caller fail }
    end;
    if Assigned(Obs) then
      Obs(string(Line));
  finally
    LeaveCriticalSection(LogLock);
  end;
end;

{
  Formats Fmt with Args via Format() and writes the result to the log.
  If formatting fails (e.g. wrong placeholders), writes Fmt as-is. }
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
