program testrunner;
{$mode objfpc}{$h+}
uses
  consoletestrunner,
  fpcunit,
  testregistry,
  test_uzipeditor,
  test_uservicemerge;
var
  App: TTestRunner;
begin
  App := TTestRunner.Create(nil);
  App.Initialize;
  App.Title := 'CBZManager Tests';
  App.Run;
  App.Free;
end.
