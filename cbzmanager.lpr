program cbzmanager;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  main,
  uclimode,
  { you can add units after this }
  uzipcore,
  usettings,
  uZipEditor,
  uWebP,
  uImgUtil,
  uLog,
  uloaderthread,
  upreviewloader,
  udlgrows,
  udlgvalidate,
  udlgvalidateopts,
  udlgcomicinfo,
  udlgwebp,
  udlgmerge,
  udlgconvertresults,
  udlgseqbuilder,
  ucomicinfo,
  udlgcomicinfoeditor,
  udlgbase,
  uarchive,
  uservicecbr,
  udlgcbr;

  {$R *.res}

begin
  { Headless (CLI) mode: when launched with a known command as the first
    argument, run the service layer directly and exit before any GUI or
    widgetset initialization.  Unknown or missing arguments fall through
    to the normal GUI startup. }
  if IsHeadlessCommand(ParamStr(1)) then
    Halt(RunHeadlessFromParams);

  RequireDerivedFormResource := True;
  Application.Scaled:=True;
  {$PUSH}
  {$WARN 5044 OFF}
  Application.MainFormOnTaskbar := True;
  {$POP}
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
