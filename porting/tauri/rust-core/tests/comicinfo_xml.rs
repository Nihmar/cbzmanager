//! Round-trip and parse-robustness tests for ComicInfo XML.

mod common;

use rust_core::comicinfo_xml::{
    default_comicinfo, generate_comicinfo_xml, parse_comicinfo_xml, ComicInfo,
};

/// A representative ComicInfo XML with several fields populated and some left
/// out entirely (Volume is absent, CommunityRating is absent).
const SAMPLE_XML: &[u8] = b"<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n\
<ComicInfo xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">\r\n\
  <Title>My Test Title</Title>\r\n\
  <Series>Test Series</Series>\r\n\
  <Number>42</Number>\r\n\
  <Count>100</Count>\r\n\
  <Volume>3</Volume>\r\n\
  <Year>2021</Year>\r\n\
  <Month>6</Month>\r\n\
  <Day>15</Day>\r\n\
  <Writer>Jane Doe</Writer>\r\n\
  <Genre>Adventure</Genre>\r\n\
</ComicInfo>";

fn assert_round_trip_fields(_ci: &ComicInfo, generated: &[u8]) {
    // Parsing the freshly-generated XML must reproduce the original fields.
    let re = parse_comicinfo_xml(generated);
    assert_eq!(re.title, "My Test Title");
    assert_eq!(re.series, "Test Series");
    assert_eq!(re.number, "42");
    assert_eq!(re.count, 100);
    assert_eq!(re.volume, 3);
    assert_eq!(re.year, 2021);
    assert_eq!(re.month, 6);
    assert_eq!(re.day, 15);
    assert_eq!(re.writer, "Jane Doe");
    assert_eq!(re.genre, "Adventure");
}

#[test]
fn parses_populated_fields() {
    let ci = parse_comicinfo_xml(SAMPLE_XML);
    assert_eq!(ci.title, "My Test Title");
    assert_eq!(ci.series, "Test Series");
    assert_eq!(ci.number, "42");
    assert_eq!(ci.count, 100);
    assert_eq!(ci.volume, 3);
    assert_eq!(ci.year, 2021);
    assert_eq!(ci.month, 6);
    assert_eq!(ci.day, 15);
    assert_eq!(ci.writer, "Jane Doe");
    assert_eq!(ci.genre, "Adventure");

    // Fields absent from the XML fall back to defaults (empty strings / sentinels).
    assert_eq!(ci.editor, "");
    assert_eq!(ci.community_rating, default_comicinfo().community_rating);
}

#[test]
fn generate_then_parse_round_trips() {
    let ci = parse_comicinfo_xml(SAMPLE_XML);
    let generated = generate_comicinfo_xml(&ci);
    assert_round_trip_fields(&ci, &generated);
}

#[test]
fn generate_emits_expected_elements_in_order() {
    let mut ci = default_comicinfo();
    ci.title = "Alpha".to_string();
    ci.count = 12;
    let xml = String::from_utf8(generate_comicinfo_xml(&ci)).unwrap();

    assert!(xml.contains("<Title>Alpha</Title>"), "title present: {xml}");
    assert!(xml.contains("<Count>12</Count>"), "count present: {xml}");

    // Pascal's fixed element order means Title precedes Count.
    let title_pos = xml.find("Title").unwrap();
    let count_pos = xml.find("Count").expect("count present for ordering");
    assert!(title_pos < count_pos, "Title must come before Count (fixed order)");
}

#[test]
fn parses_xml_with_special_characters() {
    // generate escapes; parse must unescape them back to the original text.
    let mut ci = default_comicinfo();
    ci.summary = "5 & <2, 3 > 1".to_string();
    let generated = generate_comicinfo_xml(&ci);
    let re = parse_comicinfo_xml(&generated);
    assert_eq!(re.summary, "5 & <2, 3 > 1", "special chars survive round-trip");
}

#[test]
fn empty_doc_returns_default() {
    // A completely empty buffer falls back to the default ComicInfo.
    let ci = parse_comicinfo_xml(b"");
    assert_eq!(ci.title, "");
    assert_eq!(ci.count, default_comicinfo().count);
}
