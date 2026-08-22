//! Data model mirroring native_engine/include/ghita_engine.h.
//! Field orders and enum values are ABI/behavior-critical — do not reorder.

/// Transition effects supported for timeline clips (values match C++).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(i32)]
pub enum TransitionType {
    None = 0,
    FadeIn = 1,
    FadeOut = 2,
    Crossfade = 3,
    Slide = 4,
    Wipe = 5,
    Zoom = 6,
    Dissolve = 7,
    Radial = 8,
}

impl TransitionType {
    pub fn from_i32(v: i32) -> Self {
        match v {
            1 => TransitionType::FadeIn,
            2 => TransitionType::FadeOut,
            3 => TransitionType::Crossfade,
            4 => TransitionType::Slide,
            5 => TransitionType::Wipe,
            6 => TransitionType::Zoom,
            7 => TransitionType::Dissolve,
            8 => TransitionType::Radial,
            _ => TransitionType::None,
        }
    }
}

/// Keyframe interpolation types for animation curves (legacy enum, matches C++).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(i32)]
pub enum KeyframeInterpolation {
    Linear = 0,
    EaseIn = 1,
    EaseOut = 2,
    Hold = 3,
}

impl KeyframeInterpolation {
    pub fn from_i32(v: i32) -> Self {
        match v {
            1 => KeyframeInterpolation::EaseIn,
            2 => KeyframeInterpolation::EaseOut,
            3 => KeyframeInterpolation::Hold,
            _ => KeyframeInterpolation::Linear,
        }
    }
}

/// Kind of a native timeline clip (matches C++ NativeClipKind).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(i32)]
pub enum NativeClipKind {
    Video = 0,
    Audio = 1,
    Image = 2,
    Text = 3,
    Sticker = 4,
    /// v1.5.0 T3 (#14): standalone effect element (adjustment-layer like).
    Effect = 5,
}

impl NativeClipKind {
    pub fn from_i32(v: i32) -> Option<Self> {
        match v {
            0 => Some(NativeClipKind::Video),
            1 => Some(NativeClipKind::Audio),
            2 => Some(NativeClipKind::Image),
            3 => Some(NativeClipKind::Text),
            4 => Some(NativeClipKind::Sticker),
            5 => Some(NativeClipKind::Effect),
            _ => None,
        }
    }
}

/// Media metadata structure returned by getMediaInfo (mirrors C++ MediaInfo).
#[derive(Clone, Debug, Default)]
pub struct MediaInfo {
    pub file_path: String,
    pub duration_ms: i64,
    pub width: i32,
    pub height: i32,
    pub fps: f64,
    pub bitrate: i64,
    pub video_codec: String,
    pub audio_codec: String,
    pub audio_sample_rate: i32,
    pub audio_channels: i32,
    pub has_video: bool,
    pub has_audio: bool,
}

/// JSON string escaping — byte-identical to the C++ `esc` lambda in MediaInfo::toJson.
pub fn json_escape(s: &str) -> String {
    let mut out = String::new();
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

impl MediaInfo {
    /// Serialize to JSON — must match C++ byte-for-byte (Dart parses it).
    pub fn to_json(&self) -> String {
        format!(
            "{{\"filePath\":\"{}\",\"durationMs\":{},\"width\":{},\"height\":{},\"fps\":{},\"bitrate\":{},\"videoCodec\":\"{}\",\"audioCodec\":\"{}\",\"audioSampleRate\":{},\"audioChannels\":{},\"hasVideo\":{},\"hasAudio\":{}}}",
            json_escape(&self.file_path),
            self.duration_ms,
            self.width,
            self.height,
            self.fps,
            self.bitrate,
            json_escape(&self.video_codec),
            json_escape(&self.audio_codec),
            self.audio_sample_rate,
            self.audio_channels,
            if self.has_video { "true" } else { "false" },
            if self.has_audio { "true" } else { "false" },
        )
    }
}

/// Keyframe for animation curves (mirrors C++ Keyframe).
#[derive(Clone, Debug)]
pub struct Keyframe {
    pub time_ms: i64,
    pub value: f32,
    /// 0=opacity, 1=position X offset (fraction), 2=scale, 3=rotation (stored), 4=filter intensity
    pub property: i32,
    /// Interpolation toward the NEXT keyframe of the same property: 0=linear, 1=step, 2=bezier
    pub interpolation: i32,
    pub cp1x: f32,
    pub cp1y: f32,
    pub cp2x: f32,
    pub cp2y: f32,
}

impl Keyframe {
    pub fn new(time_ms: i64, value: f32) -> Self {
        Keyframe {
            time_ms,
            value,
            property: 0,
            interpolation: 0,
            cp1x: 0.0,
            cp1y: 0.0,
            cp2x: 0.0,
            cp2y: 0.0,
        }
    }
}

/// Picture-in-picture geometry (mirrors C++ PipGeometry). Fractions of the frame.
#[derive(Clone, Copy, Debug)]
pub struct PipGeometry {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    pub rotation: f32,
}

impl Default for PipGeometry {
    fn default() -> Self {
        PipGeometry { x: 0.0, y: 0.0, w: 1.0, h: 1.0, rotation: 0.0 }
    }
}

/// Speed-ramp point (mirrors C++ SpeedRampPoint).
#[derive(Clone, Copy, Debug)]
pub struct SpeedRampPoint {
    pub t: f32,
    pub speed: f32,
}

/// Transition configuration for a clip.
#[derive(Clone, Copy, Debug)]
pub struct NativeTransition {
    pub kind: TransitionType,
    pub duration_ms: i32,
}

impl Default for NativeTransition {
    fn default() -> Self {
        NativeTransition { kind: TransitionType::None, duration_ms: 500 }
    }
}

/// Per-clip color correction (mirrors C++ ColorCorrection field order!).
#[derive(Clone, Copy, Debug, Default)]
pub struct ColorCorrection {
    pub exposure: f32,
    pub contrast: f32,
    pub saturation: f32,
    pub temperature: f32,
    pub tint: f32,
    pub vibrance: f32,
    pub highlights: f32,
    pub shadows: f32,
}

/// v1.5.0 T3 (#4): clip blend modes.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(i32)]
pub enum BlendMode {
    Normal = 0,
    Multiply = 1,
    Screen = 2,
    Overlay = 3,
    Add = 4,
}

impl BlendMode {
    pub fn from_i32(v: i32) -> Self {
        match v {
            1 => BlendMode::Multiply,
            2 => BlendMode::Screen,
            3 => BlendMode::Overlay,
            4 => BlendMode::Add,
            _ => BlendMode::Normal,
        }
    }
}

/// v1.5.0 T3 (#5): geometric masks.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(i32)]
pub enum MaskType {
    None = 0,
    Rect = 1,
    Ellipse = 2,
    Diamond = 3,
    Star = 4,
    Heart = 5,
    CinematicBars = 6,
}

impl MaskType {
    pub fn from_i32(v: i32) -> Self {
        match v {
            1 => MaskType::Rect,
            2 => MaskType::Ellipse,
            3 => MaskType::Diamond,
            4 => MaskType::Star,
            5 => MaskType::Heart,
            6 => MaskType::CinematicBars,
            _ => MaskType::None,
        }
    }
}

/// v1.5.0 T3 (#10): timeline bookmark (markers on the ruler).
#[derive(Clone, Debug)]
pub struct Bookmark {
    pub id: i32,
    pub time_ms: i64,
    pub color: u32,
    pub note: String,
}

/// A clip in the native timeline (mirrors C++ NativeClip + T3 extensions).
#[derive(Clone, Debug)]
pub struct NativeClip {
    pub id: i32,
    pub file_path: String,
    pub start_ms: i64,
    pub duration_ms: i64,
    pub source_in_ms: i64,
    pub track_index: i32,
    pub filter_type: i32,
    pub filter_intensity: f32,
    pub volume: f32,
    pub opacity: f32,
    pub speed: f32,
    pub kind: NativeClipKind,
    pub text_content: String,
    pub text_font_size: f32,
    pub text_color: u32,
    pub cc: ColorCorrection,
    pub transition: NativeTransition,
    pub keyframes: Vec<Keyframe>,
    pub keyframe_interpolation: i32,
    pub pip: PipGeometry,
    pub speed_curve: Vec<SpeedRampPoint>,
    // v1.5.0 T3 extensions.
    pub blend_mode: BlendMode,
    pub mask_type: MaskType,
    pub mask_feather: f32,
    pub mask_stroke: f32,
    pub maintain_pitch: bool,
    pub font_family: String,
}

impl NativeClip {
    pub fn new(id: i32) -> Self {
        NativeClip {
            id,
            file_path: String::new(),
            start_ms: 0,
            duration_ms: 0,
            source_in_ms: 0,
            track_index: 0,
            filter_type: 0,
            filter_intensity: 1.0,
            volume: 1.0,
            opacity: 1.0,
            speed: 1.0,
            kind: NativeClipKind::Video,
            text_content: String::new(),
            text_font_size: 48.0,
            text_color: 0xFFFFFFFF,
            cc: ColorCorrection::default(),
            transition: NativeTransition::default(),
            keyframes: Vec::new(),
            keyframe_interpolation: 0,
            pip: PipGeometry::default(),
            speed_curve: Vec::new(),
            blend_mode: BlendMode::Normal,
            mask_type: MaskType::None,
            mask_feather: 0.0,
            mask_stroke: 0.0,
            maintain_pitch: false,
            font_family: String::new(),
        }
    }
}

/// Per-track render state (mirrors C++ NativeTrackState).
#[derive(Clone, Copy, Debug)]
pub struct NativeTrackState {
    pub muted: bool,
    pub visible: bool,
    pub volume: f32,
}

impl Default for NativeTrackState {
    fn default() -> Self {
        NativeTrackState { muted: false, visible: true, volume: 1.0 }
    }
}

/// Available filters table — the single source of truth for getAvailableFiltersJson.
pub struct FilterDef {
    pub id: i32,
    pub name: &'static str,
    pub category: &'static str,
}

pub const FILTERS: [FilterDef; 23] = [
    FilterDef { id: 0, name: "None", category: "basic" },
    FilterDef { id: 1, name: "Grayscale", category: "basic" },
    FilterDef { id: 2, name: "Sepia", category: "basic" },
    FilterDef { id: 3, name: "Invert", category: "basic" },
    FilterDef { id: 4, name: "Brightness", category: "adjust" },
    FilterDef { id: 5, name: "Blur", category: "blur" },
    FilterDef { id: 6, name: "Edge Detect", category: "artistic" },
    FilterDef { id: 7, name: "Color Grading", category: "color" },
    FilterDef { id: 8, name: "Adjust", category: "color" },
    FilterDef { id: 9, name: "Pixelate", category: "artistic" },
    FilterDef { id: 10, name: "Mosaic", category: "artistic" },
    FilterDef { id: 11, name: "VHS Effect", category: "artistic" },
    FilterDef { id: 12, name: "Glitch", category: "artistic" },
    FilterDef { id: 13, name: "Chromatic Aberration", category: "artistic" },
    FilterDef { id: 14, name: "Vignette", category: "adjust" },
    FilterDef { id: 15, name: "Film Grain", category: "artistic" },
    FilterDef { id: 16, name: "Light Leak", category: "artistic" },
    FilterDef { id: 17, name: "Sharpen", category: "adjust" },
    FilterDef { id: 18, name: "Posterize", category: "artistic" },
    FilterDef { id: 19, name: "Duotone", category: "color" },
    FilterDef { id: 20, name: "Background Blur", category: "blur" },
    FilterDef { id: 21, name: "Skin Retouch", category: "beauty" },
    FilterDef { id: 22, name: "Chroma Key", category: "keying" },
];

pub fn filters_json() -> String {
    let mut s = String::from("[");
    for (i, f) in FILTERS.iter().enumerate() {
        if i > 0 {
            s.push(',');
        }
        s.push_str(&format!(
            "{{\"id\":{},\"name\":\"{}\",\"category\":\"{}\"}}",
            f.id, f.name, f.category
        ));
    }
    s.push(']');
    s
}
