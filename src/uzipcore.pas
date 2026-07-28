unit uzipcore;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type
  TZipEntryData = record
    Name: string;
    Data: TMemoryStream;
  end;
  TZipEntries = array of TZipEntryData;

const
  COMICINFO_XML = 'ComicInfo.xml';

  { Fixed zero-padding width used by page-renumber operations (e.g.
    "page_0001.jpg"). }
  PAGE_PAD_DEFAULT = 4;

  { Minimum zero-padding width for count-derived page numbering (merge and
    page-filter).  PagePaddingFor widens it when the page count needs more
    digits so every page in one archive shares a single width. }
  PAGE_PAD_MIN = 3;

function CollectZipEntries(const FileName: string): TZipEntries;

procedure WriteZipFromEntriesDeflated(const FileName: string;
  const Entries: TZipEntries);

procedure FreeZipEntries(var Entries: TZipEntries);

function FormatPageName(PageNum, Padding: integer; const Ext: string): string;

{ Padding width to use for an archive of APageCount pages: PAGE_PAD_MIN,
  widened when the count needs more digits so every page shares one width. }
function PagePaddingFor(APageCount: integer): integer;

{ Returns the index of the ComicInfo.xml entry in AEntries, or -1 if absent.
  Case-insensitive match on the entry name. }
function FindComicInfoIndex(const AEntries: TZipEntries): integer;

{ Removes every ComicInfo.xml entry from AEntries in place, freeing the
  dropped streams and compacting the surviving entries toward the front of
  the array (their Data ownership is preserved).  Returns the number of
  entries removed. }
function StripComicInfo(var AEntries: TZipEntries): integer;

implementation

uses
  Zipper, zstream;

type
  TZipCollector = class
  private
    FEntries: TZipEntries;
    procedure DoCreateStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
    procedure DoDoneStream(Sender: TObject; var AStream: TStream;
      AItem: TFullZipFileEntry);
  end;

procedure TZipCollector.DoCreateStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
begin
  AStream := TMemoryStream.Create;
end;

procedure TZipCollector.DoDoneStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
var
  n: integer;
begin
  n := Length(FEntries);
  SetLength(FEntries, n + 1);
  FEntries[n].Name := AItem.ArchiveFileName;
  FEntries[n].Data := TMemoryStream(AStream);
  AStream := nil;
end;

function CollectZipEntries(const FileName: string): TZipEntries;
var
  Collector: TZipCollector;
  UnZipper: TUnZipper;
begin
  Result := nil;
  Collector := TZipCollector.Create;
  try
    UnZipper := TUnZipper.Create;
    try
      UnZipper.OnCreateStream := @Collector.DoCreateStream;
      UnZipper.OnDoneStream := @Collector.DoDoneStream;
      UnZipper.UnZipAllFiles(FileName);
    finally
      UnZipper.Free;
    end;
    Result := Collector.FEntries;
    Collector.FEntries := nil;
  finally
    Collector.Free;
  end;
end;

procedure FreeZipEntries(var Entries: TZipEntries);
var
  i: integer;
begin
  for i := 0 to High(Entries) do
    Entries[i].Data.Free;
  Entries := nil;
end;

procedure WriteZipFromEntriesDeflated(const FileName: string;
  const Entries: TZipEntries);
var
  ZW: TZipper;
  ZEntries: TZipFileEntries;
  i: integer;
begin
  ZW := TZipper.Create;
  try
    ZEntries := TZipFileEntries.Create(TZipFileEntry);
    try
      for i := 0 to High(Entries) do
      begin
        Entries[i].Data.Position := 0;
        with ZEntries.AddFileEntry(Entries[i].Data, Entries[i].Name) do
          CompressionLevel := clmax;
      end;
      ZW.ZipFiles(FileName, ZEntries);
    finally
      ZEntries.Free;
    end;
  finally
    ZW.Free;
  end;
end;

function FormatPageName(PageNum, Padding: integer; const Ext: string): string;
begin
  Result := 'page_' + Format('%.*d', [Padding, PageNum]) + Ext;
end;

function PagePaddingFor(APageCount: integer): integer;
var
  Digits: integer;
begin
  Result := PAGE_PAD_MIN;
  Digits := Length(IntToStr(APageCount));
  if Digits > Result then
    Result := Digits;
end;

function FindComicInfoIndex(const AEntries: TZipEntries): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to High(AEntries) do
    if SameText(AEntries[i].Name, COMICINFO_XML) then
      Exit(i);
end;

function StripComicInfo(var AEntries: TZipEntries): integer;
var
  j, k: integer;
begin
  k := 0;
  for j := 0 to High(AEntries) do
  begin
    if SameText(AEntries[j].Name, COMICINFO_XML) then
    begin
      AEntries[j].Data.Free;      { free the dropped ComicInfo stream }
      AEntries[j].Data := nil;
      Continue;
    end;
    if j <> k then
    begin
      AEntries[k] := AEntries[j];  { shift survivor toward the front }
      AEntries[j].Data := nil;     { ownership transferred to slot k }
    end;
    Inc(k);
  end;
  Result := Length(AEntries) - k;
  SetLength(AEntries, k);
end;

end.
