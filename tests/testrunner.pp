program testrunner;
{$mode objfpc}{$h+}
uses
  { LCL programs must link the widgetset's registration unit, otherwise the
    linker reports undefined WSRegister* symbols. }
  interfaces,
  consoletestrunner,
  fpcunit,
  testregistry,
  test_uzipeditor,
  test_uservicemerge,
  test_uclimode,
  test_uservicevalidate,
  test_uservicecomicinfo,
  test_ucomicinfo,
  test_upageeditmodel;
var
  App: TTestRunner;
begin
  App := TTestRunner.Create(nil);
  App.Initialize;
  App.Title := 'CBZManager Tests';
  App.Run;
  App.Free;
end.
