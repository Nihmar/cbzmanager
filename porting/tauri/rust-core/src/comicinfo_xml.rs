/// ComicInfo.xml parsing and generation via `quick-xml`.
///
/// Replaces `ucomicinfo.pas`: `TComicInfo` record, `ParseComicInfoXML`,
/// `GenerateComicInfoXML`, with sentinel values for unset fields.

use quick_xml::{events::Event, Reader};
use std::io::BufReader;

// Sentinel constants (same as Pascal).
const UNSET_INT: i32 = -1;
const UNSET_RATING: f64 = -1.0;

/// ComicInfo metadata fields — mirrors Pascal `TComicInfo` record.
#[derive(Debug, Clone, Default)]
pub struct ComicInfo {
    pub title: String,
    pub series: String,
    pub number: String,
    pub count: i32,
    pub volume: i32,
    pub alternate_series: String,
    pub alternate_number: String,
    pub alternate_count: i32,
    pub summary: String,
    pub notes: String,
    pub year: i32,
    pub month: i32,
    pub day: i32,
    pub writer: String,
    pub penciller: String,
    pub inker: String,
    pub colorist: String,
    pub letterer: String,
    pub cover_artist: String,
    pub editor: String,
    pub publisher: String,
    pub imprint: String,
    pub genre: String,
    pub tags: String,
    pub web: String,
    pub page_count: i32,
    pub language_iso: String,
    pub format: String,
    pub black_and_white: String,
    pub manga: String,
    pub characters: String,
    pub teams: String,
    pub locations: String,
    pub scan_information: String,
    pub story_arc: String,
    pub story_arc_number: String,
    pub series_group: String,
    pub age_rating: String,
    pub community_rating: f64,
}

/// Returns a default ComicInfo with unset fields set to sentinel values.
pub fn default_comicinfo() -> ComicInfo {
    let mut ci = ComicInfo::default();
    ci.count = UNSET_INT;
    ci.volume = UNSET_INT;
    ci.alternate_count = UNSET_INT;
    ci.year = UNSET_INT;
    ci.month = UNSET_INT;
    ci.day = UNSET_INT;
    ci.page_count = UNSET_INT;
    ci.community_rating = UNSET_RATING;
    ci.black_and_white = String::new();
    ci.manga = String::new();
    ci.age_rating = String::new();
    ci
}

/// Helper to safely get element name as an owned String.
fn event_name(e: &quick_xml::name::QName) -> String {
    let bytes = e.as_ref();
    // UTF-8 decode; invalid sequences are replaced with the replacement character.
    String::from_utf8_lossy(bytes).into_owned()
}

/// Parse a single XML element's text content from the root.
fn get_node_text(root: &str, reader: &mut Reader<BufReader<&[u8]>>) -> String {
    let mut text = String::new();
    let mut buf = Vec::new();
    let mut depth = 0;

    loop {
        buf.clear();
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(e)) | Ok(Event::Empty(e)) => {
                if text.is_empty() {
                    let name = event_name(&e.name());
                    if name.starts_with(root) {
                        // Start of target element — begin collecting.
                        depth += 1;
                        if depth > 1 {
                            // Nested — skip but collect content.
                        }
                    }
                }
            }
            Ok(Event::End(e)) => {
                let name = event_name(&e.name());
                if name.starts_with(root) && depth > 0 {
                    depth -= 1;
                    if depth == 0 {
                        break; // Found closing tag of target element.
                    }
                }
            }
            Ok(Event::Text(e)) => {
                if depth > 0 {
                    text.push_str(&e.unescape().unwrap_or_default());
                }
            }
            Ok(Event::Eof) => break,
            _ => {}
        }
    }

    text.trim().to_string()
}

/// Parse a single integer element from XML.
fn get_node_int(root: &str, reader: &mut Reader<BufReader<&[u8]>>) -> i32 {
    let s = get_node_text(root, reader);
    if s.is_empty() {
        return UNSET_INT;
    }
    s.trim().parse::<i32>().unwrap_or(UNSET_INT)
}

/// Parse a single double element from XML.
fn get_node_double(root: &str, reader: &mut Reader<BufReader<&[u8]>>) -> f64 {
    let s = get_node_text(root, reader);
    if s.is_empty() {
        return UNSET_RATING;
    }
    s.trim().replace(',', ".").parse::<f64>().unwrap_or(UNSET_RATING)
}

/// Parse ComicInfo XML string into a `ComicInfo` struct.
///
/// Uses `quick-xml` to read the XML. Returns a default ComicInfo if parsing fails.
pub fn parse_comicinfo_xml(xml: &[u8]) -> ComicInfo {
    let mut reader = Reader::from_reader(BufReader::new(xml));

    // Skip past the root <ComicInfo> tag.
    let mut buf = Vec::new();
    loop {
        buf.clear();
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(e)) | Ok(Event::Empty(e)) => {
                let name = event_name(&e.name());
                if name.starts_with("ComicInfo") {
                    break; // Found root element.
                }
            }
            Ok(Event::Eof) => return default_comicinfo(),
            _ => {}
        }
    }

    let mut ci = default_comicinfo();

    ci.title = get_node_text("Title", &mut reader);
    ci.series = get_node_text("Series", &mut reader);
    ci.number = get_node_text("Number", &mut reader);
    ci.count = get_node_int("Count", &mut reader);
    ci.volume = get_node_int("Volume", &mut reader);
    ci.alternate_series = get_node_text("AlternateSeries", &mut reader);
    ci.alternate_number = get_node_text("AlternateNumber", &mut reader);
    ci.alternate_count = get_node_int("AlternateCount", &mut reader);
    ci.summary = get_node_text("Summary", &mut reader);
    ci.notes = get_node_text("Notes", &mut reader);
    ci.year = get_node_int("Year", &mut reader);
    ci.month = get_node_int("Month", &mut reader);
    ci.day = get_node_int("Day", &mut reader);
    ci.writer = get_node_text("Writer", &mut reader);
    ci.penciller = get_node_text("Penciller", &mut reader);
    ci.inker = get_node_text("Inker", &mut reader);
    ci.colorist = get_node_text("Colorist", &mut reader);
    ci.letterer = get_node_text("Letterer", &mut reader);
    ci.cover_artist = get_node_text("CoverArtist", &mut reader);
    ci.editor = get_node_text("Editor", &mut reader);
    ci.publisher = get_node_text("Publisher", &mut reader);
    ci.imprint = get_node_text("Imprint", &mut reader);
    ci.genre = get_node_text("Genre", &mut reader);
    ci.tags = get_node_text("Tags", &mut reader);
    ci.web = get_node_text("Web", &mut reader);
    ci.page_count = get_node_int("PageCount", &mut reader);
    ci.language_iso = get_node_text("LanguageISO", &mut reader);
    ci.format = get_node_text("Format", &mut reader);
    ci.black_and_white = get_node_text("BlackAndWhite", &mut reader);
    ci.manga = get_node_text("Manga", &mut reader);
    ci.characters = get_node_text("Characters", &mut reader);
    ci.teams = get_node_text("Teams", &mut reader);
    ci.locations = get_node_text("Locations", &mut reader);
    ci.scan_information = get_node_text("ScanInformation", &mut reader);
    ci.story_arc = get_node_text("StoryArc", &mut reader);
    ci.story_arc_number = get_node_text("StoryArcNumber", &mut reader);
    ci.series_group = get_node_text("SeriesGroup", &mut reader);
    ci.age_rating = get_node_text("AgeRating", &mut reader);
    ci.community_rating = get_node_double("CommunityRating", &mut reader);

    ci
}

/// Escape XML special characters.
fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// Generate ComicInfo XML string from a `ComicInfo` struct.
///
/// Element order matches Pascal `GenerateComicInfoXML` for round-trip fidelity.
/// Uses sorted element names as per the Pascal implementation's fixed order.
pub fn generate_comicinfo_xml(ci: &ComicInfo) -> Vec<u8> {
    let mut xml = String::from(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n\
         <ComicInfo xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\"\r\n"
    );
    xml.push_str(
        "  xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">\r\n",
    );

    // Elements in Pascal's fixed order.
    append_elem(&mut xml, "Title", &ci.title);
    append_elem(&mut xml, "Series", &ci.series);
    append_elem(&mut xml, "Number", &ci.number);
    append_int_elem(&mut xml, "Count", ci.count);
    append_int_elem(&mut xml, "Volume", ci.volume);
    append_elem(&mut xml, "AlternateSeries", &ci.alternate_series);
    append_elem(&mut xml, "AlternateNumber", &ci.alternate_number);
    append_int_elem(&mut xml, "AlternateCount", ci.alternate_count);
    append_elem(&mut xml, "Summary", &ci.summary);
    append_elem(&mut xml, "Notes", &ci.notes);
    append_int_elem(&mut xml, "Year", ci.year);
    append_int_elem(&mut xml, "Month", ci.month);
    append_int_elem(&mut xml, "Day", ci.day);
    append_elem(&mut xml, "Writer", &ci.writer);
    append_elem(&mut xml, "Penciller", &ci.penciller);
    append_elem(&mut xml, "Inker", &ci.inker);
    append_elem(&mut xml, "Colorist", &ci.colorist);
    append_elem(&mut xml, "Letterer", &ci.letterer);
    append_elem(&mut xml, "CoverArtist", &ci.cover_artist);
    append_elem(&mut xml, "Editor", &ci.editor);
    append_elem(&mut xml, "Publisher", &ci.publisher);
    append_elem(&mut xml, "Imprint", &ci.imprint);
    append_elem(&mut xml, "Genre", &ci.genre);
    append_elem(&mut xml, "Tags", &ci.tags);
    append_elem(&mut xml, "Web", &ci.web);
    append_int_elem(&mut xml, "PageCount", ci.page_count);
    append_elem(&mut xml, "LanguageISO", &ci.language_iso);
    append_elem(&mut xml, "Format", &ci.format);
    append_elem(&mut xml, "BlackAndWhite", &ci.black_and_white);
    append_elem(&mut xml, "Manga", &ci.manga);
    append_elem(&mut xml, "Characters", &ci.characters);
    append_elem(&mut xml, "Teams", &ci.teams);
    append_elem(&mut xml, "Locations", &ci.locations);
    append_elem(&mut xml, "ScanInformation", &ci.scan_information);
    append_elem(&mut xml, "StoryArc", &ci.story_arc);
    append_elem(&mut xml, "StoryArcNumber", &ci.story_arc_number);
    append_elem(&mut xml, "SeriesGroup", &ci.series_group);
    append_elem(&mut xml, "AgeRating", &ci.age_rating);
    append_double_elem(&mut xml, "CommunityRating", ci.community_rating);

    xml.push_str("</ComicInfo>\r\n");
    xml.into_bytes()
}

fn append_elem(s: &mut String, tag: &str, value: &str) {
    if !value.is_empty() {
        s.push_str(&format!("  <{}>{}</{}>\r\n", tag, xml_escape(value), tag));
    }
}

fn append_int_elem(s: &mut String, tag: &str, value: i32) {
    if value != UNSET_INT {
        s.push_str(&format!("  <{}>{}</{}>\r\n", tag, value, tag));
    }
}

fn append_double_elem(s: &mut String, tag: &str, value: f64) {
    if value > UNSET_RATING + 0.5 {
        let formatted = format!("{:.1}", value);
        s.push_str(&format!("  <{}>{}</{}>\r\n", tag, formatted, tag));
    }
}
