unit test_udlgpageview;
{$mode objfpc}{$h+}
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TPageViewTest = class(TTestCase)
  private
    FTempDir: string;
    FAppInitialized: boolean;
    procedure EnsureApp;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure PageView_LoadsPage;
    procedure PageView_MissingEntryShowsNoImage;
  end;

implementation

uses
  Forms,
  udlgpageview,
  test_helpers,
  FileUtil;

{ TPageViewTest }

procedure TPageViewTest.SetUp;
begin
  FTempDir := CreateTempDir('cbzpv_');
  EnsureApp;
end;

procedure TPageViewTest.TearDown;
begin
  if DirectoryExists(FTempDir) then
    DeleteDirectory(FTempDir, False);
end;

{ Initialize the LCL widgetset once, offscreen (make test exports
  QT_QPA_PLATFORM=offscreen).  Forms can only be created after this. }
procedure TPageViewTest.EnsureApp;
begin
  if FAppInitialized then Exit;
  FAppInitialized := True;
  RequireDerivedFormResource := True;
  Application.Initialize;
end;

function MakePageCBZ(const ADir, AName: string): string;
var
  Png: TMemoryStream;
begin
  Result := ADir + AName;
  Png := CreateMinimalPNGStream;
  CreateCBZ(Result, [Png], ['page_0001.png']);
  Png.Free;
end;

procedure TPageViewTest.PageView_LoadsPage;
var
  View: TdlgPageView;
  Path: string;
  i: integer;
begin
  { Loading an existing entry must decode it and fit it to the viewport;
    the title keeps the caller-provided caption. }
  Path := MakePageCBZ(FTempDir, 'book.cbz');
  View := TdlgPageView.Create(nil);
  try
    View.LoadPage(Path, 'page_0001.png', 'book.cbz — page_0001.png');
    for i := 1 to 50 do
    begin
      Application.ProcessMessages;
      if View.ImgPreview.Picture.Graphic <> nil then Break;
      Sleep(100);
    end;
    AssertNotNull('page decoded into preview', View.ImgPreview.Picture.Graphic);
    AssertEquals('title kept', 'book.cbz — page_0001.png', View.LblTitle.Caption);
  finally
    View.Free;
  end;
end;

procedure TPageViewTest.PageView_MissingEntryShowsNoImage;
var
  View: TdlgPageView;
  Path: string;
  i: integer;
begin
  { A missing entry must degrade to the 'No image' state instead of
    showing a stale frame or raising. }
  Path := MakePageCBZ(FTempDir, 'emptybook.cbz');
  View := TdlgPageView.Create(nil);
  try
    View.LoadPage(Path, 'page_9999.png', 'emptybook.cbz — page_9999.png');
    for i := 1 to 50 do
    begin
      Application.ProcessMessages;
      if View.LblTitle.Caption = 'No image' then Break;
      Sleep(100);
    end;
    AssertEquals('no-image state reached', 'No image', View.LblTitle.Caption);
    AssertNull('no stale image', View.ImgPreview.Picture.Graphic);
  finally
    View.Free;
  end;
end;

initialization
  RegisterTest(TPageViewTest);
end.