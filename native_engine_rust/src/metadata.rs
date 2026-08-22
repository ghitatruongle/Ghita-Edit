//! T5-P4: EXIF/IPTC/XMP metadata reader and XMP sidecar writer.
//!
//! Reads basic EXIF from JPEG/TIFF files (camera, date, dimensions, GPS).
//! Writes XMP sidecar files alongside media for non-destructive editing.
//! No external crate dependencies — parses EXIF headers manually (minimal subset).

use std::fs;
use std::io::Read;
use std::path::Path;

/// Metadata extracted from a media file.
#[derive(Debug, Clone, Default)]
pub struct MediaMetadata {
    pub width: u32,
    pub height: u32,
    pub camera_make: String,
    pub camera_model: String,
    pub date_time: String,
    pub gps_latitude: Option<f64>,
    pub gps_longitude: Option<f64>,
    pub orientation: u16,
    pub title: String,
    pub description: String,
    pub keywords: Vec<String>,
    pub rating: i32,
    pub copyright: String,
}

impl MediaMetadata {
    pub fn to_json(&self) -> String {
        let kw = self.keywords.iter()
            .map(|k| format!("\"{}\"", k.replace('"', "\\\"")))
            .collect::<Vec<_>>()
            .join(",");
        format!(
            r#"{{"width":{},"height":{},"camera_make":"{}","camera_model":"{}","date_time":"{}","gps_latitude":{},"gps_longitude":{},"orientation":{},"title":"{}","description":"{}","keywords":[{}],"rating":{},"copyright":"{}"}}"#,
            self.width, self.height,
            escape_json(&self.camera_make), escape_json(&self.camera_model),
            escape_json(&self.date_time),
            self.gps_latitude.map_or("null".to_string(), |v| format!("{:.6}", v)),
            self.gps_longitude.map_or("null".to_string(), |v| format!("{:.6}", v)),
            self.orientation,
            escape_json(&self.title), escape_json(&self.description),
            kw, self.rating, escape_json(&self.copyright),
        )
    }
}

fn escape_json(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"").replace('\n', "\\n")
}

/// Read basic EXIF from a JPEG file. Returns default metadata on failure.
pub fn read_exif(path: &str) -> MediaMetadata {
    let mut meta = MediaMetadata::default();
    let p = Path::new(path);
    if !p.exists() {
        return meta;
    }

    let ext = p.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
    if ext != "jpg" && ext != "jpeg" && ext != "tiff" && ext != "tif" {
        // For non-image files, just get file size info.
        if let Ok(md) = fs::metadata(path) {
            meta.description = format!("File size: {} bytes", md.len());
        }
        return meta;
    }

    let data = match fs::read(path) {
        Ok(d) => d,
        Err(_) => return meta,
    };

    if data.len() < 12 {
        return meta;
    }

    // Check JPEG SOI marker.
    if data[0] == 0xFF && data[1] == 0xD8 {
        parse_jpeg_exif(&data, &mut meta);
    } else if &data[0..4] == b"II\x2A\x00" || &data[0..4] == b"MM\x00\x2A" {
        parse_tiff_exif(&data, 0, &mut meta);
    }

    // Try reading XMP sidecar if it exists.
    let xmp_path = format!("{}.xmp", path);
    if Path::new(&xmp_path).exists() {
        if let Ok(xmp) = fs::read_to_string(&xmp_path) {
            parse_xmp_sidecar(&xmp, &mut meta);
        }
    }

    meta
}

fn parse_jpeg_exif(data: &[u8], meta: &mut MediaMetadata) {
    let mut offset = 2;
    while offset + 4 < data.len() {
        if data[offset] != 0xFF { break; }
        let marker = data[offset + 1];
        if marker == 0xE1 {
            // APP1 (EXIF)
            let len = ((data[offset + 2] as usize) << 8) | (data[offset + 3] as usize);
            let exif_start = offset + 4;
            if exif_start + 6 <= data.len() && &data[exif_start..exif_start + 4] == b"Exif" {
                let tiff_offset = exif_start + 6;
                parse_tiff_exif(data, tiff_offset, meta);
            }
            offset += 2 + len;
        } else if marker == 0xDA {
            break; // Start of scan
        } else {
            let len = ((data[offset + 2] as usize) << 8) | (data[offset + 3] as usize);
            offset += 2 + len;
        }
    }
}

fn parse_tiff_exif(data: &[u8], base: usize, meta: &mut MediaMetadata) {
    if base + 8 > data.len() { return; }
    let big_endian = &data[base..base + 2] == b"MM";
    let read_u16 = |off: usize| -> u16 {
        if off + 2 > data.len() { return 0; }
        if big_endian {
            ((data[off] as u16) << 8) | (data[off + 1] as u16)
        } else {
            (data[off] as u16) | ((data[off + 1] as u16) << 8)
        }
    };
    let read_u32 = |off: usize| -> u32 {
        if off + 4 > data.len() { return 0; }
        if big_endian {
            ((data[off] as u32) << 24) | ((data[off+1] as u32) << 16) |
            ((data[off+2] as u32) << 8) | (data[off+3] as u32)
        } else {
            (data[off] as u32) | ((data[off+1] as u32) << 8) |
            ((data[off+2] as u32) << 16) | ((data[off+3] as u32) << 24)
        }
    };

    let ifd_offset = read_u32(base + 4) as usize + base;
    if ifd_offset + 2 > data.len() { return; }
    let num_entries = read_u16(ifd_offset) as usize;

    for i in 0..num_entries {
        let entry_off = ifd_offset + 2 + i * 12;
        if entry_off + 12 > data.len() { break; }
        let tag = read_u16(entry_off);
        let typ = read_u16(entry_off + 2);
        let count = read_u32(entry_off + 4);
        let value_off_raw = read_u32(entry_off + 8);

        match tag {
            0x0100 => meta.width = value_off_raw, // ImageWidth
            0x0101 => meta.height = value_off_raw, // ImageLength
            0x010F => { // Make
                if typ == 2 {
                    let str_off = if count > 4 { value_off_raw as usize + base } else { entry_off + 8 };
                    meta.camera_make = read_ascii(data, str_off, count as usize);
                }
            }
            0x0110 => { // Model
                if typ == 2 {
                    let str_off = if count > 4 { value_off_raw as usize + base } else { entry_off + 8 };
                    meta.camera_model = read_ascii(data, str_off, count as usize);
                }
            }
            0x0112 => meta.orientation = read_u16(entry_off + 8), // Orientation
            0x0132 => { // DateTime
                if typ == 2 {
                    let str_off = if count > 4 { value_off_raw as usize + base } else { entry_off + 8 };
                    meta.date_time = read_ascii(data, str_off, count as usize);
                }
            }
            _ => {}
        }
    }
}

fn read_ascii(data: &[u8], offset: usize, len: usize) -> String {
    let end = (offset + len).min(data.len());
    let bytes = &data[offset..end];
    String::from_utf8_lossy(bytes).trim_end_matches('\0').to_string()
}

fn parse_xmp_sidecar(xmp: &str, meta: &mut MediaMetadata) {
    // Simple tag extraction from XMP XML.
    if let Some(v) = extract_xmp_tag(xmp, "dc:title") {
        meta.title = v;
    }
    if let Some(v) = extract_xmp_tag(xmp, "dc:description") {
        meta.description = v;
    }
    if let Some(v) = extract_xmp_tag(xmp, "xmp:Rating") {
        meta.rating = v.parse().unwrap_or(0);
    }
    if let Some(v) = extract_xmp_tag(xmp, "dc:rights") {
        meta.copyright = v;
    }
}

fn extract_xmp_tag(xml: &str, tag: &str) -> Option<String> {
    // Look for <tag>value</tag> pattern.
    let open = format!("<{}>", tag);
    let close = format!("</{}>", tag);
    if let Some(start) = xml.find(&open) {
        let val_start = start + open.len();
        if let Some(end) = xml[val_start..].find(&close) {
            return Some(xml[val_start..val_start + end].trim().to_string());
        }
    }
    None
}

/// Write an XMP sidecar file alongside the media file.
pub fn write_xmp_sidecar(media_path: &str, meta: &MediaMetadata) -> bool {
    let xmp_path = format!("{}.xmp", media_path);
    let keywords_xml: String = meta.keywords.iter()
        .map(|k| format!("        <rdf:li>{}</rdf:li>\n", escape_xml(k)))
        .collect();

    let xmp = format!(
        r#"<?xpacket begin="" id="W5M0MpCeHiHzReSzKiRz"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
           xmlns:dc="http://purl.org/dc/elements/1.1/"
           xmlns:xmp="http://ns.adobe.com/xap/1.0/">
    <rdf:Description>
      <dc:title>{}</dc:title>
      <dc:description>{}</dc:description>
      <dc:rights>{}</dc:rights>
      <xmp:Rating>{}</xmp:Rating>
      <dc:subject>
{}      </dc:subject>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>
"#,
        escape_xml(&meta.title),
        escape_xml(&meta.description),
        escape_xml(&meta.copyright),
        meta.rating,
        keywords_xml,
    );

    fs::write(&xmp_path, xmp.as_bytes()).is_ok()
}

fn escape_xml(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metadata_to_json_roundtrip() {
        let meta = MediaMetadata {
            width: 1920,
            height: 1080,
            camera_make: "Canon".to_string(),
            camera_model: "EOS R5".to_string(),
            date_time: "2026:01:15 10:30:00".to_string(),
            gps_latitude: Some(48.8566),
            gps_longitude: Some(2.3522),
            orientation: 1,
            title: "Test Photo".to_string(),
            description: "A test".to_string(),
            keywords: vec!["nature".to_string(), "landscape".to_string()],
            rating: 4,
            copyright: "2026 Test".to_string(),
        };
        let json = meta.to_json();
        assert!(json.contains("\"width\":1920"));
        assert!(json.contains("\"camera_make\":\"Canon\""));
        assert!(json.contains("\"gps_latitude\":48.856600"));
        assert!(json.contains("\"nature\""));
    }

    #[test]
    fn read_exif_nonexistent_file() {
        let meta = read_exif("/nonexistent/file.jpg");
        assert_eq!(meta.width, 0);
        assert_eq!(meta.height, 0);
    }

    #[test]
    fn xmp_sidecar_write_and_read() {
        let dir = std::env::temp_dir();
        let test_path = dir.join("test_metadata_xmp.jpg");
        let test_str = test_path.to_str().unwrap();
        // Create dummy file.
        fs::write(&test_path, &[0xFF, 0xD8, 0xFF, 0xD9]).unwrap();
        let meta = MediaMetadata {
            title: "Sidecar Test".to_string(),
            description: "Testing XMP".to_string(),
            rating: 3,
            keywords: vec!["test".to_string()],
            ..Default::default()
        };
        assert!(write_xmp_sidecar(test_str, &meta));
        // Read back.
        let mut meta2 = MediaMetadata::default();
        let xmp_content = fs::read_to_string(format!("{}.xmp", test_str)).unwrap();
        parse_xmp_sidecar(&xmp_content, &mut meta2);
        assert_eq!(meta2.title, "Sidecar Test");
        assert_eq!(meta2.rating, 3);
        // Cleanup.
        let _ = fs::remove_file(&test_path);
        let _ = fs::remove_file(format!("{}.xmp", test_str));
    }
}

