unit ucomicinfo;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type
  TComicInfo = record
    Title: string;
    Series: string;
    Number: string;
    Count: integer;
    Volume: integer;
    AlternateSeries: string;
    AlternateNumber: string;
    AlternateCount: integer;
    Summary: string;
    Notes: string;
    Year: integer;
    Month: integer;
    Day: integer;
    Writer: string;
    Penciller: string;
    Inker: string;
    Colorist: string;
    Letterer: string;
    CoverArtist: string;
    Editor: string;
    Publisher: string;
    Imprint: string;
    Genre: string;
    Tags: string;
    Web: string;
    PageCount: integer;
    LanguageISO: string;
    Format: string;
    BlackAndWhite: string;
    Manga: string;
    Characters: string;
    Teams: string;
    Locations: string;
    ScanInformation: string;
    StoryArc: string;
    StoryArcNumber: string;
    SeriesGroup: string;
    AgeRating: string;
    CommunityRating: double;
  end;

function DefaultComicInfo: TComicInfo;
function ParseComicInfoXML(const AXML: string): TComicInfo;
function GenerateComicInfoXML(const AData: TComicInfo): string;
function ReadComicInfoFromCBZ(const AFilePath: string): TComicInfo;
procedure WriteComicInfoToCBZ(const AFilePath: string;
  const AData: TComicInfo; ABackup: boolean);

implementation

uses
  DOM, XMLRead, uzipcore, uservicebase;

const
  UNSET_INT = -1;
  UNSET_RATING = -1.0;

function DefaultComicInfo: TComicInfo;
begin
  Result := Default(TComicInfo);
  Result.Count := UNSET_INT;
  Result.Volume := UNSET_INT;
  Result.AlternateCount := UNSET_INT;
  Result.Year := UNSET_INT;
  Result.Month := UNSET_INT;
  Result.Day := UNSET_INT;
  Result.PageCount := UNSET_INT;
  Result.CommunityRating := UNSET_RATING;
  Result.BlackAndWhite := '';
  Result.Manga := '';
  Result.AgeRating := '';
end;

function GetNodeText(AParent: TDOMNode; const AName: string): string;
var
  Node: TDOMNode;
begin
  Result := '';
  Node := AParent.FindNode(DOMString(AName));
  if (Node <> nil) and (Node.FirstChild <> nil) then
    Result := string(Node.FirstChild.NodeValue);
end;

function GetNodeInt(AParent: TDOMNode; const AName: string): integer;
var
  S: string;
  V, Err: integer;
begin
  Result := UNSET_INT;
  S := Trim(GetNodeText(AParent, AName));
  if S = '' then Exit;
  Val(S, V, Err);
  if Err = 0 then Result := V;
end;

function GetNodeDouble(AParent: TDOMNode; const AName: string): double;
var
  S: string;
begin
  Result := UNSET_RATING;
  S := Trim(GetNodeText(AParent, AName));
  if S = '' then Exit;
  try
    Result := StrToFloat(S, DefaultFormatSettings);
  except
    try
      Result := StrToFloat(StringReplace(S, '.', DefaultFormatSettings.DecimalSeparator, []), DefaultFormatSettings);
    except
      Result := UNSET_RATING;
    end;
  end;
end;

function ParseComicInfoXML(const AXML: string): TComicInfo;
var
  Doc: TXMLDocument;
  SS: TStringStream;
  Root: TDOMNode;
begin
  Result := DefaultComicInfo;
  if Trim(AXML) = '' then Exit;
  Doc := nil;
  SS := TStringStream.Create(AXML);
  try
    ReadXMLFile(Doc, SS);
    if Doc = nil then Exit;
    Root := Doc.DocumentElement;
    if Root = nil then Exit;

    Result.Title := GetNodeText(Root, 'Title');
    Result.Series := GetNodeText(Root, 'Series');
    Result.Number := GetNodeText(Root, 'Number');
    Result.Count := GetNodeInt(Root, 'Count');
    Result.Volume := GetNodeInt(Root, 'Volume');
    Result.AlternateSeries := GetNodeText(Root, 'AlternateSeries');
    Result.AlternateNumber := GetNodeText(Root, 'AlternateNumber');
    Result.AlternateCount := GetNodeInt(Root, 'AlternateCount');
    Result.Summary := GetNodeText(Root, 'Summary');
    Result.Notes := GetNodeText(Root, 'Notes');
    Result.Year := GetNodeInt(Root, 'Year');
    Result.Month := GetNodeInt(Root, 'Month');
    Result.Day := GetNodeInt(Root, 'Day');
    Result.Writer := GetNodeText(Root, 'Writer');
    Result.Penciller := GetNodeText(Root, 'Penciller');
    Result.Inker := GetNodeText(Root, 'Inker');
    Result.Colorist := GetNodeText(Root, 'Colorist');
    Result.Letterer := GetNodeText(Root, 'Letterer');
    Result.CoverArtist := GetNodeText(Root, 'CoverArtist');
    Result.Editor := GetNodeText(Root, 'Editor');
    Result.Publisher := GetNodeText(Root, 'Publisher');
    Result.Imprint := GetNodeText(Root, 'Imprint');
    Result.Genre := GetNodeText(Root, 'Genre');
    Result.Tags := GetNodeText(Root, 'Tags');
    Result.Web := GetNodeText(Root, 'Web');
    Result.PageCount := GetNodeInt(Root, 'PageCount');
    Result.LanguageISO := GetNodeText(Root, 'LanguageISO');
    Result.Format := GetNodeText(Root, 'Format');
    Result.BlackAndWhite := GetNodeText(Root, 'BlackAndWhite');
    Result.Manga := GetNodeText(Root, 'Manga');
    Result.Characters := GetNodeText(Root, 'Characters');
    Result.Teams := GetNodeText(Root, 'Teams');
    Result.Locations := GetNodeText(Root, 'Locations');
    Result.ScanInformation := GetNodeText(Root, 'ScanInformation');
    Result.StoryArc := GetNodeText(Root, 'StoryArc');
    Result.StoryArcNumber := GetNodeText(Root, 'StoryArcNumber');
    Result.SeriesGroup := GetNodeText(Root, 'SeriesGroup');
    Result.AgeRating := GetNodeText(Root, 'AgeRating');
    Result.CommunityRating := GetNodeDouble(Root, 'CommunityRating');
  finally
    Doc.Free;
    SS.Free;
  end;
end;

function XmlEsc(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

procedure AppendElem(var S: string; const ATag, AValue: string);
begin
  if AValue <> '' then
    S := S + '  <' + ATag + '>' + XmlEsc(AValue) + '</' + ATag + '>' + LineEnding;
end;

procedure AppendIntElem(var S: string; const ATag: string; AValue: integer);
begin
  if AValue <> UNSET_INT then
    S := S + '  <' + ATag + '>' + IntToStr(AValue) + '</' + ATag + '>' + LineEnding;
end;

procedure AppendDoubleElem(var S: string; const ATag: string; AValue: double);
var
  Fmt: TFormatSettings;
begin
  if AValue > UNSET_RATING + 0.5 then
  begin
    Fmt := DefaultFormatSettings;
    Fmt.DecimalSeparator := '.';
    S := S + '  <' + ATag + '>' + FormatFloat('0.#', AValue, Fmt) +
      '</' + ATag + '>' + LineEnding;
  end;
end;

function GenerateComicInfoXML(const AData: TComicInfo): string;
begin
  Result := '<?xml version="1.0" encoding="utf-8"?>' + LineEnding;
  Result := Result + '<ComicInfo xmlns:xsd="http://www.w3.org/2001/XMLSchema"' +
    ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' + LineEnding;

  AppendElem(Result, 'Title', AData.Title);
  AppendElem(Result, 'Series', AData.Series);
  AppendElem(Result, 'Number', AData.Number);
  AppendIntElem(Result, 'Count', AData.Count);
  AppendIntElem(Result, 'Volume', AData.Volume);
  AppendElem(Result, 'AlternateSeries', AData.AlternateSeries);
  AppendElem(Result, 'AlternateNumber', AData.AlternateNumber);
  AppendIntElem(Result, 'AlternateCount', AData.AlternateCount);
  AppendElem(Result, 'Summary', AData.Summary);
  AppendElem(Result, 'Notes', AData.Notes);
  AppendIntElem(Result, 'Year', AData.Year);
  AppendIntElem(Result, 'Month', AData.Month);
  AppendIntElem(Result, 'Day', AData.Day);
  AppendElem(Result, 'Writer', AData.Writer);
  AppendElem(Result, 'Penciller', AData.Penciller);
  AppendElem(Result, 'Inker', AData.Inker);
  AppendElem(Result, 'Colorist', AData.Colorist);
  AppendElem(Result, 'Letterer', AData.Letterer);
  AppendElem(Result, 'CoverArtist', AData.CoverArtist);
  AppendElem(Result, 'Editor', AData.Editor);
  AppendElem(Result, 'Publisher', AData.Publisher);
  AppendElem(Result, 'Imprint', AData.Imprint);
  AppendElem(Result, 'Genre', AData.Genre);
  AppendElem(Result, 'Tags', AData.Tags);
  AppendElem(Result, 'Web', AData.Web);
  AppendIntElem(Result, 'PageCount', AData.PageCount);
  AppendElem(Result, 'LanguageISO', AData.LanguageISO);
  AppendElem(Result, 'Format', AData.Format);
  AppendElem(Result, 'BlackAndWhite', AData.BlackAndWhite);
  AppendElem(Result, 'Manga', AData.Manga);
  AppendElem(Result, 'Characters', AData.Characters);
  AppendElem(Result, 'Teams', AData.Teams);
  AppendElem(Result, 'Locations', AData.Locations);
  AppendElem(Result, 'ScanInformation', AData.ScanInformation);
  AppendElem(Result, 'StoryArc', AData.StoryArc);
  AppendElem(Result, 'StoryArcNumber', AData.StoryArcNumber);
  AppendElem(Result, 'SeriesGroup', AData.SeriesGroup);
  AppendElem(Result, 'AgeRating', AData.AgeRating);
  AppendDoubleElem(Result, 'CommunityRating', AData.CommunityRating);

  Result := Result + '</ComicInfo>' + LineEnding;
end;

function ReadComicInfoFromCBZ(const AFilePath: string): TComicInfo;
var
  Entries: TZipEntries;
  i: integer;
  XML: string;
begin
  Result := DefaultComicInfo;
  Entries := CollectZipEntries(AFilePath);
  try
    for i := 0 to High(Entries) do
      if SameText(Entries[i].Name, COMICINFO_XML) then
      begin
        Entries[i].Data.Position := 0;
        SetLength(XML, Entries[i].Data.Size);
        if Length(XML) > 0 then
          Entries[i].Data.Read(XML[1], Length(XML));
        Result := ParseComicInfoXML(XML);
        Break;
      end;
  finally
    FreeZipEntries(Entries);
  end;
end;

procedure WriteComicInfoToCBZ(const AFilePath: string;
  const AData: TComicInfo; ABackup: boolean);
var
  Entries: TZipEntries;
  XML: string;
  i, k, Idx: integer;
  Found: boolean;
begin
  Entries := CollectZipEntries(AFilePath);
  try
    XML := GenerateComicInfoXML(AData);
    Found := False;
    Idx := -1;
    for i := 0 to High(Entries) do
      if SameText(Entries[i].Name, COMICINFO_XML) then
      begin
        Found := True;
        Idx := i;
        Break;
      end;

    if Found then
    begin
      Entries[Idx].Data.Free;
      Entries[Idx].Data := TMemoryStream.Create;
      if Length(XML) > 0 then
        Entries[Idx].Data.Write(XML[1], Length(XML));
      Entries[Idx].Data.Position := 0;
    end
    else
    begin
      k := Length(Entries);
      SetLength(Entries, k + 1);
      Entries[k].Name := COMICINFO_XML;
      Entries[k].Data := TMemoryStream.Create;
      if Length(XML) > 0 then
        Entries[k].Data.Write(XML[1], Length(XML));
      Entries[k].Data.Position := 0;
    end;

    if not ReplaceCBZ(AFilePath, Entries) then
      raise Exception.CreateFmt('Failed to write %s', [ExtractFileName(AFilePath)]);
    if not ABackup then
      DeleteFile(ChangeFileExt(AFilePath, '') + '_OLD.cbz');
  finally
    FreeZipEntries(Entries);
  end;
end;

end.
