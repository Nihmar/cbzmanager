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

function CollectZipEntries(const FileName: string): TZipEntries;

procedure WriteZipFromEntriesDeflated(const FileName: string;
  const Entries: TZipEntries);

procedure FreeZipEntries(var Entries: TZipEntries);

function FormatPageName(PageNum, Padding: integer; const Ext: string): string;

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

end.
