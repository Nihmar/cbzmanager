unit test_ucomicinfo;
{$mode objfpc}{$h+}
interface
uses
  fpcunit, testregistry,
  Classes, SysUtils;

type
  TComicInfoTest = class(TTestCase)
  published
    procedure ParseEmpty;
    procedure ParseMinimal;
    procedure ParseAllFields;
    procedure GenerateEmpty;
    procedure Roundtrip;
    procedure RoundtripIntFields;
    procedure RoundtripRating;
    procedure XmlEscaping;
  end;

implementation

uses
  ucomicinfo;

procedure TComicInfoTest.ParseEmpty;
var
  CI: TComicInfo;
begin
  CI := ParseComicInfoXML('');
  AssertEquals('Title empty', '', CI.Title);
  AssertEquals('Count unset', -1, CI.Count);
end;

procedure TComicInfoTest.ParseMinimal;
var
  CI: TComicInfo;
begin
  CI := ParseComicInfoXML(
    '<?xml version="1.0"?><ComicInfo><Title>Test</Title></ComicInfo>');
  AssertEquals('Title', 'Test', CI.Title);
  AssertEquals('Series empty', '', CI.Series);
end;

procedure TComicInfoTest.ParseAllFields;
var
  CI: TComicInfo;
  XML: string;
begin
  XML := '<?xml version="1.0"?><ComicInfo>' +
    '<Title>My Comic</Title>' +
    '<Series>My Series</Series>' +
    '<Number>5</Number>' +
    '<Count>10</Count>' +
    '<Volume>2</Volume>' +
    '<Summary>A test summary</Summary>' +
    '<Year>2024</Year>' +
    '<Month>3</Month>' +
    '<Day>15</Day>' +
    '<Writer>John Doe</Writer>' +
    '<Publisher>Test Pub</Publisher>' +
    '<Genre>Action</Genre>' +
    '<LanguageISO>en</LanguageISO>' +
    '<PageCount>42</PageCount>' +
    '<CommunityRating>4.5</CommunityRating>' +
    '</ComicInfo>';
  CI := ParseComicInfoXML(XML);
  AssertEquals('Title', 'My Comic', CI.Title);
  AssertEquals('Series', 'My Series', CI.Series);
  AssertEquals('Number', '5', CI.Number);
  AssertEquals('Count', 10, CI.Count);
  AssertEquals('Volume', 2, CI.Volume);
  AssertEquals('Summary', 'A test summary', CI.Summary);
  AssertEquals('Year', 2024, CI.Year);
  AssertEquals('Month', 3, CI.Month);
  AssertEquals('Day', 15, CI.Day);
  AssertEquals('Writer', 'John Doe', CI.Writer);
  AssertEquals('Publisher', 'Test Pub', CI.Publisher);
  AssertEquals('Genre', 'Action', CI.Genre);
  AssertEquals('LanguageISO', 'en', CI.LanguageISO);
  AssertEquals('PageCount', 42, CI.PageCount);
  AssertTrue('CommunityRating', Abs(CI.CommunityRating - 4.5) < 0.01);
end;

procedure TComicInfoTest.GenerateEmpty;
var
  CI: TComicInfo;
  XML: string;
begin
  CI := DefaultComicInfo;
  XML := GenerateComicInfoXML(CI);
  AssertTrue('Has XML header', Pos('<?xml', XML) > 0);
  AssertTrue('Has ComicInfo tag', Pos('<ComicInfo', XML) > 0);
  AssertTrue('Has closing tag', Pos('</ComicInfo>', XML) > 0);
  AssertTrue('No Title tag', Pos('<Title>', XML) = 0);
end;

procedure TComicInfoTest.Roundtrip;
var
  CI, CI2: TComicInfo;
  XML: string;
begin
  CI := DefaultComicInfo;
  CI.Title := 'Roundtrip Test';
  CI.Series := 'Test Series';
  CI.Number := '12';
  CI.Writer := 'Jane Smith';
  CI.Publisher := 'Acme Comics';
  CI.Genre := 'Fantasy';
  CI.LanguageISO := 'it';
  XML := GenerateComicInfoXML(CI);
  CI2 := ParseComicInfoXML(XML);
  AssertEquals('Title', CI.Title, CI2.Title);
  AssertEquals('Series', CI.Series, CI2.Series);
  AssertEquals('Number', CI.Number, CI2.Number);
  AssertEquals('Writer', CI.Writer, CI2.Writer);
  AssertEquals('Publisher', CI.Publisher, CI2.Publisher);
  AssertEquals('Genre', CI.Genre, CI2.Genre);
  AssertEquals('LanguageISO', CI.LanguageISO, CI2.LanguageISO);
end;

procedure TComicInfoTest.RoundtripIntFields;
var
  CI, CI2: TComicInfo;
  XML: string;
begin
  CI := DefaultComicInfo;
  CI.Count := 50;
  CI.Volume := 3;
  CI.Year := 2023;
  CI.Month := 11;
  CI.Day := 7;
  CI.PageCount := 200;
  XML := GenerateComicInfoXML(CI);
  CI2 := ParseComicInfoXML(XML);
  AssertEquals('Count', 50, CI2.Count);
  AssertEquals('Volume', 3, CI2.Volume);
  AssertEquals('Year', 2023, CI2.Year);
  AssertEquals('Month', 11, CI2.Month);
  AssertEquals('Day', 7, CI2.Day);
  AssertEquals('PageCount', 200, CI2.PageCount);
end;

procedure TComicInfoTest.RoundtripRating;
var
  CI, CI2: TComicInfo;
  XML: string;
begin
  CI := DefaultComicInfo;
  CI.CommunityRating := 3.7;
  XML := GenerateComicInfoXML(CI);
  CI2 := ParseComicInfoXML(XML);
  AssertTrue('Rating roundtrip', Abs(CI2.CommunityRating - 3.7) < 0.01);
end;

procedure TComicInfoTest.XmlEscaping;
var
  CI, CI2: TComicInfo;
  XML: string;
begin
  CI := DefaultComicInfo;
  CI.Title := 'Tom & Jerry <"Special">';
  XML := GenerateComicInfoXML(CI);
  AssertTrue('Ampersand escaped', Pos('&amp;', XML) > 0);
  AssertTrue('Less-than escaped', Pos('&lt;', XML) > 0);
  CI2 := ParseComicInfoXML(XML);
  AssertEquals('Title roundtrip with escapes', CI.Title, CI2.Title);
end;

initialization
  RegisterTest(TComicInfoTest);

end.
