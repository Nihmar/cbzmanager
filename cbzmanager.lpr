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
  { you can add units after this }
  uZipEditor,
  uWebP,
  uImgUtil,
  uLog,
  uloaderthread,
  udlgrows,
  udlgvalidate,
  udlgcomicinfo,
  udlgwebp,
  udlgmerge,
  udlgconvertresults,
  udlgseqbuilder,
  ucomicinfo,
  udlgcomicinfoeditor;

  {$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  {$PUSH}
  {$WARN 5044 OFF}
  Application.MainFormOnTaskbar := True;
  {$POP}
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
