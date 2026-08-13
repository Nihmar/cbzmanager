program testrunner;
{$mode objfpc}{$h+}
uses
  { LCL programs must link the widgetset's registration unit, otherwise the
    linker reports undefined WSRegister* symbols. }
  cthreads,
  interfaces,
  consoletestrunner,
  fpcunit,
  testregistry,
  test_uzipeditor,
  test_uservicemerge,
  test_uclimode,
  test_udlgseqbuilder,
  test_udlgpageview,
  test_udlgpageeditor,
  test_udlgcbr,
  test_udlgwebp,
  test_udlgvalidate,
  test_udlgvalidateopts,
  test_udlgcomicinfoeditor,
  test_udlgmerge,
  test_ubatchedit,
  test_udlgbatchedit,
  test_uloaderthread,
  test_uservicevalidate,
  test_uservicecomicinfo,
  test_ucomicinfo,
  test_uthreadservice,
  test_userviceconvert,
  test_uservicecbr,
  test_upageeditmodel,
  test_uimageedit;
var
  App: TTestRunner;
begin
  App := TTestRunner.Create(nil);
  App.Initialize;
  App.Title := 'CBZManager Tests';
  App.Run;
  App.Free;
end.
