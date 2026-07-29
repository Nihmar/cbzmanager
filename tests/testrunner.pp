program testrunner;
{$mode objfpc}{$h+}
uses
  consoletestrunner,
  fpcunit,
  testregistry,
  test_uzipeditor,
  test_uservicemerge,
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
