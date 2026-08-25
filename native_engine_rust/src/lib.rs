//! # Ghita Engine (Rust) — Track 1 (Rust Core)
//!
//! Drop-in replacement for the C++20 `native_engine` — same C ABI exported
//! from the `cdylib`, zero Dart changes required. See
//! `docs/rust_engine_abi.md` for the ABI contract.
//!
//! Phase map (plan_v1.5.0.md → T1):
//! - P1 scaffold: this crate + c_api.rs (all 65 `ghita_engine_*` symbols,
//!   panic containment, thread-local buffers, null-on-OOM create)
//! - P2 data model + timeline ops: model.rs + engine.rs
//! - P3 synthetic engine: synth.rs + render/mix/waveform in engine.rs
//! - P4 filters 0–22 + color correction + text stub + thumbnails:
//!   filters.rs, compositor.rs, gdi.rs
//! - P5 (feature `parallel`): tile-based multi-threaded filters via rayon
//! - P6 (feature `gpu`): wgpu compositor + graph cache (gpu.rs, graph.rs)

pub mod c_api;
pub mod compositor;
pub mod dsp;
pub mod engine;
pub mod filters;
pub mod fx;
pub mod gdi;
pub mod model;
pub mod synth;

#[cfg(feature = "ffmpeg")]
pub mod audio_t4;

#[cfg(feature = "ffmpeg")]
pub mod fft_tools;

#[cfg(feature = "ffmpeg")]
pub mod media;

#[cfg(feature = "gpu")]
pub mod gpu;

// T5-P1: SQLite project format + media library database.
#[cfg(feature = "sqlite")]
pub mod project_db;

// T5-P4: EXIF/IPTC/XMP metadata reader + XMP sidecar writer.
pub mod metadata;

// T5-P6: Smart processing cache with dirty propagation.
pub mod processing_cache;
// T6-P1: Pixel-level selection tools and layer mask operations.
pub mod selection;
// T6-P3: Color management — sRGB/linear, HDR tonemap, film simulation.
pub mod color_mgmt;

// T6-P4: Brush engines — pixel/smudge/stabilizer.
pub mod brush_engine;
// T6-P5: AI tools — NLM denoise, bicubic upscale, color segmentation, hash dedup.
pub mod ai_tools;
// T6-P2: Clone/heal/path paint tools.
pub mod paint_tools;

// v1.5.0-T5 (P4): the f32_pipeline module was REMOVED — its filter-id table
// diverged from the shipped u8 reference (15/16/18-20 mapped to the wrong
// filters), only 5/22 filters had parity tests, it had ZERO production
// callers, and no benchmark showed a win (f32 does strictly more arithmetic
// per pixel). Per the plan's own decision tree ("benchmark thua thì xóa"),
// deletion eliminates the drift permanently.

pub use c_api::{VERSION_STRING, GhitaEngineContext};
pub use engine::GhitaEngine;
