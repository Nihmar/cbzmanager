unit uheadlesscmd;

{
  uheadlesscmd – headless-command detection plus the environment needed to
  reach it.

  Why the initialization block: the LCL widgetset is brought up by the
  Interfaces unit while the program loads, i.e. BEFORE cbzmanager.lpr's begin
  block can test the command line.  On a machine with no display Qt aborts at
  that point, so the headless branch never runs and `cbzmanager validate ...`
  dies with SIGABRT.  Selecting the offscreen platform here keeps the CLI
  usable on servers and in CI; this unit must stay before Interfaces in the
  .lpr uses clause (after cthreads) for the initialization order to hold.

  No dependency on the widgetset or the services, so it is safe to initialize
  first.
}

{$mode objfpc}{$H+}

interface

{ True when AFirstArg asks for the headless CLI: a known command, --help or
  --version. }
function IsHeadlessCommand(const AFirstArg: string): boolean;

implementation

{$IFDEF WINDOWS}
uses
  SysUtils;   { SetEnvironmentVariable }
{$ENDIF}

{$IFDEF UNIX}
{ libc setenv: Qt reads the environment through libc, while FPC caches its
  own environment list, so the RTL's helpers would not be seen by Qt. }
function c_setenv(name, value: PAnsiChar; overwrite: longint): longint;
  cdecl; external 'c' name 'setenv';
{$ENDIF}

function IsHeadlessCommand(const AFirstArg: string): boolean;
begin
  Result := (AFirstArg = 'validate') or (AFirstArg = 'convert-webp') or
            (AFirstArg = 'merge') or (AFirstArg = 'cbr-to-cbz') or
            (AFirstArg = '--help') or (AFirstArg = '-h') or
            (AFirstArg = 'help') or (AFirstArg = '--version');
end;

initialization
  if (ParamCount > 0) and IsHeadlessCommand(ParamStr(1)) then
  begin
    {$IFDEF WINDOWS}
    SetEnvironmentVariable('QT_QPA_PLATFORM', 'offscreen');
    {$ENDIF}
    {$IFDEF UNIX}
    c_setenv('QT_QPA_PLATFORM', 'offscreen', 1);
    {$ENDIF}
  end;

end.
