//! A/B harness: runs the identical scenario on the C++ engine DLL (loaded
//! from native_engine/build/libghita_engine.dll) and the Rust engine lib,
//! then byte-compares every rendered frame, waveform, mix result, JSON and
//! return code.
//!
//! Usage:  cargo run -p engine_compare --release
//! Exit 0 = parity within tolerance (max channel diff ≤ 1), 1 = mismatch.

use std::ffi::{c_char, c_int, c_void, CString};
use std::ptr;

use libloading::Library;

const CPP_DLL_CANDIDATES: [&str; 4] = [
    "../../../native_engine/build/libghita_engine.dll", // repo root (from tools/engine_compare)
    "../../native_engine/build/libghita_engine.dll",
    "native_engine/build/libghita_engine.dll",
    "E:/Ghita Edit/native_engine/build/libghita_engine.dll",
];

type FnCreate = unsafe extern "C" fn() -> *mut c_void;
type FnDestroy = unsafe extern "C" fn(*mut c_void);
type FnInit = unsafe extern "C" fn(*mut c_void) -> c_int;
type FnLoad = unsafe extern "C" fn(*mut c_void, *const c_char) -> c_int;
type FnRenderAt = unsafe extern "C" fn(*mut c_void, *mut u8, c_int, c_int, i64) -> bool;
type FnApplyFilter = unsafe extern "C" fn(*mut c_void, c_int, f32);
type FnUpsert = unsafe extern "C" fn(*mut c_void, c_int, *const c_char, i64, i64, i64, c_int, c_int, f32, f32, f32) -> c_int;
type FnSetTrack = unsafe extern "C" fn(*mut c_void, c_int, c_int, c_int, f32) -> c_int;
type FnSetCc = unsafe extern "C" fn(*mut c_void, c_int, f32, f32, f32, f32, f32, f32, f32, f32) -> c_int;
type FnAddKfEx = unsafe extern "C" fn(*mut c_void, c_int, i64, f32, c_int, c_int, f32, f32, f32, f32) -> c_int;
type FnSetBezier = unsafe extern "C" fn(*mut c_void, c_int, c_int, f32, f32, f32, f32) -> c_int;
type FnSetPip = unsafe extern "C" fn(*mut c_void, c_int, f32, f32, f32, f32, f32) -> c_int;
type FnAddRamp = unsafe extern "C" fn(*mut c_void, c_int, f32, f32) -> c_int;
type FnSetTrans = unsafe extern "C" fn(*mut c_void, c_int, c_int, c_int) -> bool;
type FnSetText = unsafe extern "C" fn(*mut c_void, c_int, *const c_char, f32, u32) -> c_int;
type FnMix = unsafe extern "C" fn(*mut c_void, i64, i64, *mut f32, c_int) -> bool;
type FnWaveform = unsafe extern "C" fn(*mut c_void, *mut f32, c_int) -> bool;
type FnMediaInfo = unsafe extern "C" fn(*mut c_void) -> *const c_char;
type FnFilters = unsafe extern "C" fn(*mut c_void) -> *const c_char;
type FnThumb = unsafe extern "C" fn(*mut c_void, c_int, i64, c_int, c_int) -> *mut u8;
type FnGetDur = unsafe extern "C" fn(*mut c_void) -> i64;
type FnGetW = unsafe extern "C" fn(*mut c_void) -> c_int;
type FnGetH = unsafe extern "C" fn(*mut c_void) -> c_int;
type FnStartExport = unsafe extern "C" fn(*mut c_void, *const c_char, c_int, c_int, c_int) -> c_int;
type FnCancelExport = unsafe extern "C" fn(*mut c_void);
type FnIsExporting = unsafe extern "C" fn(*mut c_void) -> bool;
type FnRenderAtEx = unsafe extern "C" fn(*mut c_void, *mut u8, c_int, c_int, i64, c_int) -> bool;

const W: c_int = 64;
const H: c_int = 36;

/// The C++ engine, resolved through libloading (symbols never collide with
/// the statically linked Rust engine — explicit per-handle lookup).
struct CppEngine {
    _lib: Library,
    create: FnCreate,
    destroy: FnDestroy,
    init: FnInit,
    load: FnLoad,
    render_at: FnRenderAt,
    apply_filter: FnApplyFilter,
    upsert: FnUpsert,
    set_track: FnSetTrack,
    set_cc: FnSetCc,
    add_kf_ex: FnAddKfEx,
    set_bezier: FnSetBezier,
    set_pip: FnSetPip,
    add_ramp: FnAddRamp,
    set_trans: FnSetTrans,
    set_text: FnSetText,
    mix: FnMix,
    waveform: FnWaveform,
    media_info: FnMediaInfo,
    filters: FnFilters,
    thumb: FnThumb,
    start_export: FnStartExport,
    cancel_export: FnCancelExport,
    is_exporting: FnIsExporting,
    render_at_ex: FnRenderAtEx,
    get_dur: FnGetDur,
    get_w: FnGetW,
    get_h: FnGetH,
}

impl CppEngine {
    fn load() -> Self {
        unsafe {
            let lib = Library::new(find_cpp_dll()).expect("load C++ DLL");
            macro_rules! sym {
                ($t:ty, $n:literal) => {
                    *lib.get::<$t>(concat!($n, "\0").as_bytes()).unwrap()
                };
            }
            CppEngine {
                create: sym!(FnCreate, "ghita_engine_create"),
                destroy: sym!(FnDestroy, "ghita_engine_destroy"),
                init: sym!(FnInit, "ghita_engine_init"),
                load: sym!(FnLoad, "ghita_engine_load_media"),
                render_at: sym!(FnRenderAt, "ghita_engine_render_frame_at"),
                apply_filter: sym!(FnApplyFilter, "ghita_engine_apply_filter"),
                upsert: sym!(FnUpsert, "ghita_engine_upsert_clip"),
                set_track: sym!(FnSetTrack, "ghita_engine_set_track_state"),
                set_cc: sym!(FnSetCc, "ghita_engine_set_clip_color_correction"),
                add_kf_ex: sym!(FnAddKfEx, "ghita_engine_add_keyframe_ex"),
                set_bezier: sym!(FnSetBezier, "ghita_engine_set_keyframe_bezier"),
                set_pip: sym!(FnSetPip, "ghita_engine_set_clip_pip"),
                add_ramp: sym!(FnAddRamp, "ghita_engine_add_speed_ramp_point"),
                set_trans: sym!(FnSetTrans, "ghita_engine_set_clip_transition"),
                set_text: sym!(FnSetText, "ghita_engine_set_clip_text"),
                mix: sym!(FnMix, "ghita_engine_mix_audio_window"),
                waveform: sym!(FnWaveform, "ghita_engine_get_audio_waveform"),
                media_info: sym!(FnMediaInfo, "ghita_engine_get_media_info"),
                filters: sym!(FnFilters, "ghita_engine_get_available_filters"),
                thumb: sym!(FnThumb, "ghita_engine_get_thumbnail"),
                start_export: sym!(FnStartExport, "ghita_engine_start_export"),
                cancel_export: sym!(FnCancelExport, "ghita_engine_cancel_export"),
                is_exporting: sym!(FnIsExporting, "ghita_engine_is_exporting"),
                render_at_ex: sym!(FnRenderAtEx, "ghita_engine_render_frame_at_ex"),
                get_dur: sym!(FnGetDur, "ghita_engine_get_duration_ms"),
                get_w: sym!(FnGetW, "ghita_engine_get_media_width"),
                get_h: sym!(FnGetH, "ghita_engine_get_media_height"),
                _lib: lib,
            }
        }
    }
}

/// The Rust engine — calls the crate's own C API surface.
struct RustEngine;

impl RustEngine {
    unsafe fn create(&self) -> *mut c_void {
        ghita_engine::c_api::ghita_engine_create() as *mut c_void
    }
    unsafe fn destroy(&self, c: *mut c_void) {
        ghita_engine::c_api::ghita_engine_destroy(c as *mut ghita_engine::GhitaEngineContext)
    }
    unsafe fn init(&self, c: *mut c_void) -> c_int {
        ghita_engine::c_api::ghita_engine_init(c as *mut ghita_engine::GhitaEngineContext)
    }
    unsafe fn load(&self, c: *mut c_void, p: *const c_char) -> c_int {
        ghita_engine::c_api::ghita_engine_load_media(c as *mut ghita_engine::GhitaEngineContext, p)
    }
    unsafe fn render_at(&self, c: *mut c_void, b: *mut u8, w: c_int, h: c_int, p: i64) -> bool {
        ghita_engine::c_api::ghita_engine_render_frame_at(c as *mut ghita_engine::GhitaEngineContext, b, w, h, p)
    }
    unsafe fn apply_filter(&self, c: *mut c_void, f: c_int, i: f32) {
        ghita_engine::c_api::ghita_engine_apply_filter(c as *mut ghita_engine::GhitaEngineContext, f, i)
    }
    unsafe fn upsert(&self, c: *mut c_void, id: c_int, p: *const c_char, s: i64, d: i64, si: i64, t: c_int, k: c_int, v: f32, o: f32, sp: f32) -> c_int {
        ghita_engine::c_api::ghita_engine_upsert_clip(c as *mut ghita_engine::GhitaEngineContext, id, p, s, d, si, t, k, v, o, sp)
    }
    unsafe fn set_track(&self, c: *mut c_void, t: c_int, m: c_int, v: c_int, vol: f32) -> c_int {
        ghita_engine::c_api::ghita_engine_set_track_state(c as *mut ghita_engine::GhitaEngineContext, t, m, v, vol)
    }
    unsafe fn set_cc(&self, c: *mut c_void, id: c_int, e: f32, co: f32, sa: f32, te: f32, ti: f32, vi: f32, hl: f32, sh: f32) -> c_int {
        ghita_engine::c_api::ghita_engine_set_clip_color_correction(c as *mut ghita_engine::GhitaEngineContext, id, e, co, sa, te, ti, vi, hl, sh)
    }
    unsafe fn add_kf_ex(&self, c: *mut c_void, id: c_int, t: i64, v: f32, pr: c_int, it: c_int, a: f32, b: f32, d: f32, e: f32) -> c_int {
        ghita_engine::c_api::ghita_engine_add_keyframe_ex(c as *mut ghita_engine::GhitaEngineContext, id, t, v, pr, it, a, b, d, e)
    }
    unsafe fn set_bezier(&self, c: *mut c_void, id: c_int, ki: c_int, a: f32, b: f32, d: f32, e: f32) -> c_int {
        ghita_engine::c_api::ghita_engine_set_keyframe_bezier(c as *mut ghita_engine::GhitaEngineContext, id, ki, a, b, d, e)
    }
    unsafe fn set_pip(&self, c: *mut c_void, id: c_int, x: f32, y: f32, w: f32, h: f32, r: f32) -> c_int {
        ghita_engine::c_api::ghita_engine_set_clip_pip(c as *mut ghita_engine::GhitaEngineContext, id, x, y, w, h, r)
    }
    unsafe fn add_ramp(&self, c: *mut c_void, id: c_int, t: f32, s: f32) -> c_int {
        ghita_engine::c_api::ghita_engine_add_speed_ramp_point(c as *mut ghita_engine::GhitaEngineContext, id, t, s)
    }
    unsafe fn set_trans(&self, c: *mut c_void, id: c_int, ty: c_int, d: c_int) -> bool {
        ghita_engine::c_api::ghita_engine_set_clip_transition(c as *mut ghita_engine::GhitaEngineContext, id, ty, d)
    }
    unsafe fn set_text(&self, c: *mut c_void, id: c_int, t: *const c_char, fs: f32, col: u32) -> c_int {
        ghita_engine::c_api::ghita_engine_set_clip_text(c as *mut ghita_engine::GhitaEngineContext, id, t, fs, col)
    }
    unsafe fn mix(&self, c: *mut c_void, s: i64, e: i64, o: *mut f32, n: c_int) -> bool {
        ghita_engine::c_api::ghita_engine_mix_audio_window(c as *mut ghita_engine::GhitaEngineContext, s, e, o, n)
    }
    unsafe fn waveform(&self, c: *mut c_void, o: *mut f32, n: c_int) -> bool {
        ghita_engine::c_api::ghita_engine_get_audio_waveform(c as *mut ghita_engine::GhitaEngineContext, o, n)
    }
    unsafe fn media_info(&self, c: *mut c_void) -> *const c_char {
        ghita_engine::c_api::ghita_engine_get_media_info(c as *mut ghita_engine::GhitaEngineContext)
    }
    unsafe fn filters(&self, c: *mut c_void) -> *const c_char {
        ghita_engine::c_api::ghita_engine_get_available_filters(c as *mut ghita_engine::GhitaEngineContext)
    }
    unsafe fn thumb(&self, c: *mut c_void, id: c_int, t: i64, w: c_int, h: c_int) -> *mut u8 {
        ghita_engine::c_api::ghita_engine_get_thumbnail(c as *mut ghita_engine::GhitaEngineContext, id, t, w, h)
    }
    unsafe fn start_export(&self, c: *mut c_void, p: *const c_char, w: c_int, h: c_int, f: c_int) -> c_int {
        ghita_engine::c_api::ghita_engine_start_export(c as *mut ghita_engine::GhitaEngineContext, p, w, h, f)
    }
    unsafe fn cancel_export(&self, c: *mut c_void) {
        ghita_engine::c_api::ghita_engine_cancel_export(c as *mut ghita_engine::GhitaEngineContext)
    }
    unsafe fn is_exporting(&self, c: *mut c_void) -> bool {
        ghita_engine::c_api::ghita_engine_is_exporting(c as *mut ghita_engine::GhitaEngineContext)
    }
    unsafe fn render_at_ex(&self, c: *mut c_void, b: *mut u8, w: c_int, h: c_int, p: i64, fx: c_int) -> bool {
        ghita_engine::c_api::ghita_engine_render_frame_at_ex(c as *mut ghita_engine::GhitaEngineContext, b, w, h, p, fx)
    }
    unsafe fn get_dur(&self, c: *mut c_void) -> i64 {
        ghita_engine::c_api::ghita_engine_get_duration_ms(c as *mut ghita_engine::GhitaEngineContext)
    }
    unsafe fn get_w(&self, c: *mut c_void) -> c_int {
        ghita_engine::c_api::ghita_engine_get_media_width(c as *mut ghita_engine::GhitaEngineContext)
    }
    unsafe fn get_h(&self, c: *mut c_void) -> c_int {
        ghita_engine::c_api::ghita_engine_get_media_height(c as *mut ghita_engine::GhitaEngineContext)
    }
}

// ---------------------------------------------------------------------------
// Scenario (identical call sequence for both engines)
// ---------------------------------------------------------------------------

struct Scenario {
    frames: Vec<(String, Vec<u8>)>,
    floats: Vec<(String, Vec<f32>)>,
    strings: Vec<(String, String)>,
    return_codes: Vec<(String, i32)>,
}

trait EngineOps {
    unsafe fn run(&self) -> Scenario;
}

impl EngineOps for CppEngine {
    unsafe fn run(&self) -> Scenario {
        let mut sc = Scenario::new();
        let ctx = (self.create)();
        assert!(!ctx.is_null());
        sc.codes(("init".into(), (self.init)(ctx)));
        let path = CString::new("missing_ab_test.mp4").unwrap();
        sc.codes(("load_missing".into(), (self.load)(ctx, path.as_ptr())));

        for pos in [0i64, 100, 2000, 30000, 59999] {
            let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
            assert!((self.render_at)(ctx, a.as_mut_ptr(), W, H, pos));
            sc.frames.push((format!("legacy@{pos}"), a));
        }
        for f in [1i32, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22] {
            (self.apply_filter)(ctx, f, 0.7);
            let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
            assert!((self.render_at)(ctx, a.as_mut_ptr(), W, H, 5000));
            sc.frames.push((format!("legacy_filter{f}"), a));
        }
        (self.apply_filter)(ctx, 0, 0.0);

        let p1 = CString::new("media1.mp4").unwrap();
        let p2 = CString::new("media2.mp4").unwrap();
        let p3 = CString::new("media3.mp4").unwrap();
        sc.codes(("upsert1".into(), (self.upsert)(ctx, 1, p1.as_ptr(), 0, 4000, 0, 0, 0, 1.0, 1.0, 1.0)));
        sc.codes(("upsert2".into(), (self.upsert)(ctx, 2, p2.as_ptr(), 2000, 4000, 0, 1, 0, 1.0, 0.8, 1.5)));
        sc.codes(("upsert3".into(), (self.upsert)(ctx, 3, p3.as_ptr(), 4000, 3000, 0, 0, 0, 1.0, 1.0, 1.0)));
        sc.codes(("upsert4_audio".into(), (self.upsert)(ctx, 4, p3.as_ptr(), 0, 5000, 0, 2, 1, 1.0, 1.0, 1.0)));
        sc.codes(("set_track0".into(), (self.set_track)(ctx, 0, 0, 1, 1.0)));
        sc.codes(("set_track1".into(), (self.set_track)(ctx, 1, 0, 1, 0.9)));

        sc.codes(("kf1a".into(), (self.add_kf_ex)(ctx, 1, 0, 0.0, 0, 0, 0.0, 0.0, 0.0, 0.0)));
        sc.codes(("kf1b".into(), (self.add_kf_ex)(ctx, 1, 4000, 1.0, 0, 0, 0.0, 0.0, 0.0, 0.0)));
        sc.codes(("kf2a".into(), (self.add_kf_ex)(ctx, 2, 2000, 1.0, 2, 0, 0.0, 0.0, 0.0, 0.0)));
        sc.codes(("kf2b".into(), (self.add_kf_ex)(ctx, 2, 6000, 2.0, 2, 0, 0.0, 0.0, 0.0, 0.0)));
        sc.codes(("kf3a".into(), (self.add_kf_ex)(ctx, 3, 4000, 0.0, 0, 2, 0.3, 0.6, 0.7, 0.9)));
        sc.codes(("kf3b".into(), (self.add_kf_ex)(ctx, 3, 7000, 1.0, 0, 0, 0.0, 0.0, 0.0, 0.0)));
        sc.codes(("bezier".into(), (self.set_bezier)(ctx, 3, 0, 0.2, 0.8, 0.4, 0.9)));
        sc.codes(("cc".into(), (self.set_cc)(ctx, 2, 0.2, 0.15, -0.1, 0.3, -0.2, 0.1, 0.25, -0.15)));
        sc.codes(("pip".into(), (self.set_pip)(ctx, 2, 0.1, 0.1, 0.5, 0.5, 0.0)));
        sc.codes(("ramp1".into(), (self.add_ramp)(ctx, 2, 0.0, 1.0)));
        sc.codes(("ramp2".into(), (self.add_ramp)(ctx, 2, 1.0, 2.0)));
        sc.codes(("trans3".into(), (self.set_trans)(ctx, 3, 1, 500) as i32));
        sc.codes(("trans1".into(), (self.set_trans)(ctx, 1, 3, 400) as i32));

        for pos in [0i64, 500, 1500, 2200, 2500, 3000, 4200, 5000, 6000, 6500] {
            let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
            assert!((self.render_at)(ctx, a.as_mut_ptr(), W, H, pos));
            sc.frames.push((format!("timeline@{pos}"), a));
        }

        let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
        assert!((self.render_at_ex)(ctx, a.as_mut_ptr(), W, H, 2500, 1));
        sc.frames.push(("timeline_ex_fx".into(), a));
        let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
        assert!((self.render_at_ex)(ctx, a.as_mut_ptr(), W, H, 2500, 0));
        sc.frames.push(("timeline_ex_raw".into(), a));

        let t1 = CString::new("Hello AB Test").unwrap();
        sc.codes(("text_upsert".into(), (self.upsert)(ctx, 5, p3.as_ptr(), 0, 2000, 0, 3, 3, 1.0, 1.0, 1.0)));
        sc.codes(("text_set".into(), (self.set_text)(ctx, 5, t1.as_ptr(), 28.0, 0xFFFF8800)));
        let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
        assert!((self.render_at)(ctx, a.as_mut_ptr(), W, H, 1000));
        sc.frames.push(("text_clip".into(), a));

        let mut ma = vec![0.0f32; 882];
        sc.codes(("mix".into(), (self.mix)(ctx, 0, 100, ma.as_mut_ptr(), 882) as i32));
        sc.floats.push(("mix_audio_window".into(), ma));
        let mut wa = vec![0.0f32; 200];
        assert!((self.waveform)(ctx, wa.as_mut_ptr(), 200));
        sc.floats.push(("waveform".into(), wa));

        sc.strings.push(("media_info".into(), cstr_to_string((self.media_info)(ctx))));
        sc.strings.push(("filters_json".into(), cstr_to_string((self.filters)(ctx))));

        let ta = (self.thumb)(ctx, 1, 1500, 32, 18);
        assert!(!ta.is_null(), "CPP thumbnail must not be null");
        sc.frames.push(("thumbnail".into(), std::slice::from_raw_parts(ta, 32 * 18 * 4).to_vec()));

        let out = CString::new("ab_export_cpp.raw").unwrap();
        sc.codes(("start_export".into(), (self.start_export)(ctx, out.as_ptr(), W, H, 10)));
        assert!((self.is_exporting)(ctx));
        (self.cancel_export)(ctx);
        assert!(!(self.is_exporting)(ctx));

        (self.destroy)(ctx);
        sc
    }
}

impl EngineOps for RustEngine {
    unsafe fn run(&self) -> Scenario {
        let mut sc = Scenario::new();
        let ctx = self.create();
        assert!(!ctx.is_null());
        sc.codes(("init".into(), self.init(ctx)));
        let path = CString::new("missing_ab_test.mp4").unwrap();
        sc.codes(("load_missing".into(), self.load(ctx, path.as_ptr())));

        for pos in [0i64, 100, 2000, 30000, 59999] {
            let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
            assert!(self.render_at(ctx, a.as_mut_ptr(), W, H, pos));
            sc.frames.push((format!("legacy@{pos}"), a));
        }
        for f in [1i32, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22] {
            self.apply_filter(ctx, f, 0.7);
            let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
            assert!(self.render_at(ctx, a.as_mut_ptr(), W, H, 5000));
            sc.frames.push((format!("legacy_filter{f}"), a));
        }
        self.apply_filter(ctx, 0, 0.0);

        let p1 = CString::new("media1.mp4").unwrap();
        let p2 = CString::new("media2.mp4").unwrap();
        let p3 = CString::new("media3.mp4").unwrap();
        sc.codes(("upsert1".into(), self.upsert(ctx, 1, p1.as_ptr(), 0, 4000, 0, 0, 0, 1.0, 1.0, 1.0)));
        sc.codes(("upsert2".into(), self.upsert(ctx, 2, p2.as_ptr(), 2000, 4000, 0, 1, 0, 1.0, 0.8, 1.5)));
        sc.codes(("upsert3".into(), self.upsert(ctx, 3, p3.as_ptr(), 4000, 3000, 0, 0, 0, 1.0, 1.0, 1.0)));
        sc.codes(("upsert4_audio".into(), self.upsert(ctx, 4, p3.as_ptr(), 0, 5000, 0, 2, 1, 1.0, 1.0, 1.0)));
        sc.codes(("set_track0".into(), self.set_track(ctx, 0, 0, 1, 1.0)));
        sc.codes(("set_track1".into(), self.set_track(ctx, 1, 0, 1, 0.9)));

        sc.codes(("kf1a".into(), self.add_kf_ex(ctx, 1, 0, 0.0, 0, 0, 0.0, 0.0, 0.0, 0.0)));
        sc.codes(("kf1b".into(), self.add_kf_ex(ctx, 1, 4000, 1.0, 0, 0, 0.0, 0.0, 0.0, 0.0)));
        sc.codes(("kf2a".into(), self.add_kf_ex(ctx, 2, 2000, 1.0, 2, 0, 0.0, 0.0, 0.0, 0.0)));
        sc.codes(("kf2b".into(), self.add_kf_ex(ctx, 2, 6000, 2.0, 2, 0, 0.0, 0.0, 0.0, 0.0)));
        sc.codes(("kf3a".into(), self.add_kf_ex(ctx, 3, 4000, 0.0, 0, 2, 0.3, 0.6, 0.7, 0.9)));
        sc.codes(("kf3b".into(), self.add_kf_ex(ctx, 3, 7000, 1.0, 0, 0, 0.0, 0.0, 0.0, 0.0)));
        sc.codes(("bezier".into(), self.set_bezier(ctx, 3, 0, 0.2, 0.8, 0.4, 0.9)));
        sc.codes(("cc".into(), self.set_cc(ctx, 2, 0.2, 0.15, -0.1, 0.3, -0.2, 0.1, 0.25, -0.15)));
        sc.codes(("pip".into(), self.set_pip(ctx, 2, 0.1, 0.1, 0.5, 0.5, 0.0)));
        sc.codes(("ramp1".into(), self.add_ramp(ctx, 2, 0.0, 1.0)));
        sc.codes(("ramp2".into(), self.add_ramp(ctx, 2, 1.0, 2.0)));
        sc.codes(("trans3".into(), self.set_trans(ctx, 3, 1, 500) as i32));
        sc.codes(("trans1".into(), self.set_trans(ctx, 1, 3, 400) as i32));

        for pos in [0i64, 500, 1500, 2200, 2500, 3000, 4200, 5000, 6000, 6500] {
            let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
            assert!(self.render_at(ctx, a.as_mut_ptr(), W, H, pos));
            sc.frames.push((format!("timeline@{pos}"), a));
        }

        let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
        assert!(self.render_at_ex(ctx, a.as_mut_ptr(), W, H, 2500, 1));
        sc.frames.push(("timeline_ex_fx".into(), a));
        let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
        assert!(self.render_at_ex(ctx, a.as_mut_ptr(), W, H, 2500, 0));
        sc.frames.push(("timeline_ex_raw".into(), a));

        let t1 = CString::new("Hello AB Test").unwrap();
        sc.codes(("text_upsert".into(), self.upsert(ctx, 5, p3.as_ptr(), 0, 2000, 0, 3, 3, 1.0, 1.0, 1.0)));
        sc.codes(("text_set".into(), self.set_text(ctx, 5, t1.as_ptr(), 28.0, 0xFFFF8800)));
        let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
        assert!(self.render_at(ctx, a.as_mut_ptr(), W, H, 1000));
        sc.frames.push(("text_clip".into(), a));

        let mut ma = vec![0.0f32; 882];
        sc.codes(("mix".into(), self.mix(ctx, 0, 100, ma.as_mut_ptr(), 882) as i32));
        sc.floats.push(("mix_audio_window".into(), ma));
        let mut wa = vec![0.0f32; 200];
        assert!(self.waveform(ctx, wa.as_mut_ptr(), 200));
        sc.floats.push(("waveform".into(), wa));

        sc.strings.push(("media_info".into(), cstr_to_string(self.media_info(ctx))));
        sc.strings.push(("filters_json".into(), cstr_to_string(self.filters(ctx))));

        let ta = self.thumb(ctx, 1, 1500, 32, 18);
        assert!(!ta.is_null(), "RUST thumbnail must not be null");
        sc.frames.push(("thumbnail".into(), std::slice::from_raw_parts(ta, 32 * 18 * 4).to_vec()));

        let out = CString::new("ab_export_rust.raw").unwrap();
        sc.codes(("start_export".into(), self.start_export(ctx, out.as_ptr(), W, H, 10)));
        assert!(self.is_exporting(ctx));
        self.cancel_export(ctx);
        assert!(!self.is_exporting(ctx));

        self.destroy(ctx);
        sc
    }
}

impl Scenario {
    fn new() -> Self {
        Scenario { frames: Vec::new(), floats: Vec::new(), strings: Vec::new(), return_codes: Vec::new() }
    }
    fn codes(&mut self, kv: (String, i32)) {
        self.return_codes.push(kv);
    }
}

unsafe fn cstr_to_string(p: *const c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    std::ffi::CStr::from_ptr(p).to_str().unwrap_or_default().to_string()
}

/// Resolves the C++ engine DLL path (first existing candidate wins).
fn find_cpp_dll() -> &'static str {
    for c in CPP_DLL_CANDIDATES {
        if std::path::Path::new(c).exists() {
            return c;
        }
    }
    CPP_DLL_CANDIDATES[0]
}

fn compare_frames(name: &str, a: &[u8], b: &[u8]) -> bool {
    assert_eq!(a.len(), b.len(), "{name}: size mismatch");
    let mut max_diff = 0i32;
    let mut diff_pixels = 0usize;
    for (x, y) in a.iter().zip(b.iter()) {
        let d = (*x as i32 - *y as i32).abs();
        if d > 0 {
            diff_pixels += 1;
            max_diff = max_diff.max(d);
        }
    }
    let ok = max_diff <= 1;
    println!(
        "{:<34} max_diff={:<3} diff_pixels={:<8} total={:<6} {}",
        name, max_diff, diff_pixels, a.len() / 4, if ok { "OK" } else { "MISMATCH" }
    );
    ok
}

fn compare_floats(name: &str, a: &[f32], b: &[f32], tol: f32) -> bool {
    assert_eq!(a.len(), b.len());
    let mut max_d = 0.0f32;
    for (x, y) in a.iter().zip(b.iter()) {
        max_d = max_d.max((x - y).abs());
    }
    let ok = max_d <= tol;
    println!("{:<34} max_diff={:<10.8} {}", name, max_d, if ok { "OK" } else { "MISMATCH" });
    ok
}

const MEDIA_MP4: &str = "../../../test_video.mp4";
const MEDIA_WAV: &str = "../../../test_sine.wav";

/// Real-media A/B: decode parity (test_video.mp4), WAV direct-reader parity
/// (test_sine.wav), timeline mix, JSON and a small real export.
unsafe fn run_media_scenario(cpp: &CppEngine, rust: &RustEngine) -> bool {
    let mut any_failed = false;
    let mut frames: Vec<(String, Vec<u8>)> = Vec::new();
    let mut floats: Vec<(String, Vec<f32>)> = Vec::new();
    let mut strings: Vec<(String, String)> = Vec::new();

    let cc = (cpp.create)();
    let rc = rust.create();
    assert!(!cc.is_null() && !rc.is_null());
    assert_eq!((cpp.init)(cc), rust.init(rc));

    let mp4 = CString::new(MEDIA_MP4).unwrap();
    let wav = CString::new(MEDIA_WAV).unwrap();
    let load_cpp = (cpp.load)(cc, mp4.as_ptr());
    let load_rust = rust.load(rc, mp4.as_ptr());
    assert_eq!(load_cpp, load_rust, "load_media return must match");

    // Metadata parity.
    assert_eq!((cpp.get_dur)(cc), rust.get_dur(rc), "duration");
    assert_eq!((cpp.get_w)(cc), rust.get_w(rc), "width");
    assert_eq!((cpp.get_h)(cc), rust.get_h(rc), "height");

    // Decode parity at several positions.
    for pos in [0i64, 200, 700, 1500, 3000] {
        let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
        let mut b = vec![0u8; (W as usize) * (H as usize) * 4];
        assert!((cpp.render_at)(cc, a.as_mut_ptr(), W, H, pos));
        assert!(rust.render_at(rc, b.as_mut_ptr(), W, H, pos));
        frames.push((format!("real_decode@{pos}"), a));
        frames.push((format!("real_decode@{pos}"), b));
    }

    // Media info JSON parity (real file metadata).
    strings.push(("real_media_info".into(), cstr_to_string((cpp.media_info)(cc))));
    strings.push(("real_media_info".into(), cstr_to_string(rust.media_info(rc))));

    // WAV direct-reader parity: waveform of test_sine.wav.
    assert_eq!((cpp.load)(cc, wav.as_ptr()), rust.load(rc, wav.as_ptr()));
    let mut wa = vec![0.0f32; 400];
    let mut wb = vec![0.0f32; 400];
    assert!((cpp.waveform)(cc, wa.as_mut_ptr(), 400));
    assert!(rust.waveform(rc, wb.as_mut_ptr(), 400));
    floats.push(("real_waveform".into(), wa));
    floats.push(("real_waveform".into(), wb));

    // Timeline: video clip + audio clip → mix + composite parity.
    let p1 = CString::new(MEDIA_MP4).unwrap();
    let p2 = CString::new(MEDIA_WAV).unwrap();
    assert_eq!((cpp.upsert)(cc, 1, p1.as_ptr(), 0, 2000, 0, 0, 0, 1.0, 1.0, 1.0), rust.upsert(rc, 1, p1.as_ptr(), 0, 2000, 0, 0, 0, 1.0, 1.0, 1.0));
    assert_eq!((cpp.upsert)(cc, 2, p2.as_ptr(), 0, 2000, 0, 1, 1, 1.0, 1.0, 1.0), rust.upsert(rc, 2, p2.as_ptr(), 0, 2000, 0, 1, 1, 1.0, 1.0, 1.0));
    for pos in [0i64, 300, 900, 1800] {
        let mut a = vec![0u8; (W as usize) * (H as usize) * 4];
        let mut b = vec![0u8; (W as usize) * (H as usize) * 4];
        assert!((cpp.render_at)(cc, a.as_mut_ptr(), W, H, pos));
        assert!(rust.render_at(rc, b.as_mut_ptr(), W, H, pos));
        frames.push((format!("real_timeline@{pos}"), a));
        frames.push((format!("real_timeline@{pos}"), b));
    }
    let mut ma = vec![0.0f32; 882];
    let mut mb = vec![0.0f32; 882];
    let ra = (cpp.mix)(cc, 0, 100, ma.as_mut_ptr(), 882);
    let rb = rust.mix(rc, 0, 100, mb.as_mut_ptr(), 882);
    assert_eq!(ra, rb, "mix return must match");
    floats.push(("real_mix_window".into(), ma));
    floats.push(("real_mix_window".into(), mb));

    // Real export (H.264 64×36 10fps) — both must complete with real sizes.
    let out_cpp = CString::new("ab_media_cpp.mp4").unwrap();
    let out_rust = CString::new("ab_media_rust.mp4").unwrap();
    assert_eq!((cpp.start_export)(cc, out_cpp.as_ptr(), W, H, 10), 0);
    assert_eq!(rust.start_export(rc, out_rust.as_ptr(), W, H, 10), 0);
    for _ in 0..2000 {
        if !(cpp.is_exporting)(cc) && !rust.is_exporting(rc) {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    assert!(!(cpp.is_exporting)(cc) && !rust.is_exporting(rc), "both exports must finish");

    (cpp.destroy)(cc);
    rust.destroy(rc);

    // Compare (tolerance 1 for frames, exact for floats/strings).
    assert_eq!(frames.len() % 2, 0);
    for pair in frames.chunks(2) {
        let (n, a, b) = (&pair[0].0, &pair[0].1, &pair[1].1);
        let ok = compare_frames(n, a, b);
        any_failed |= !ok;
    }
    for pair in floats.chunks(2) {
        let (n, a, b) = (&pair[0].0, &pair[0].1, &pair[1].1);
        let ok = compare_floats(n, a, b, 1e-6);
        any_failed |= !ok;
    }
    for pair in strings.chunks(2) {
        let (n, a) = &pair[0];
        let (_, b) = &pair[1];
        assert_eq!(n, &pair[1].0, "string pair names must match");
        let ok = a == b;
        if !ok {
            any_failed = true;
            println!("{n}: JSON differs");
            println!("  cpp : {a}");
            println!("  rust: {b}");
        } else {
            println!("{n}: identical ({} bytes)", a.len());
        }
    }
    any_failed
}

fn main() {
    assert!(
        std::path::Path::new(find_cpp_dll()).exists(),
        "C++ DLL not found (tried {:?}) — build native_engine first (MinGW)",
        CPP_DLL_CANDIDATES
    );

    unsafe {
        let cpp = CppEngine::load();
        let cpp_sc = cpp.run();
        let rust_sc = RustEngine.run();

        println!("== A/B parity: Rust vs C++ (synthetic, no FFmpeg) ==");
        let mut any_failed = false;

        // Return codes must match exactly.
        assert_eq!(cpp_sc.return_codes.len(), rust_sc.return_codes.len(), "return code count differs");
        for ((n1, a), (n2, b)) in cpp_sc.return_codes.iter().zip(rust_sc.return_codes.iter()) {
            assert_eq!(n1, n2);
            let ok = a == b;
            if !ok {
                any_failed = true;
            }
            println!("{:<22} cpp={:<4} rust={:<4} {}", n1, a, b, if ok { "OK" } else { "MISMATCH" });
        }

        // Frames: byte-level with tolerance ≤ 1.
        assert_eq!(cpp_sc.frames.len(), rust_sc.frames.len(), "frame count differs");
        for ((n1, a), (n2, b)) in cpp_sc.frames.iter().zip(rust_sc.frames.iter()) {
            assert_eq!(n1, n2);
            let ok = compare_frames(n1, a, b);
            any_failed |= !ok;
        }

        // Floats (waveform/mix).
        assert_eq!(cpp_sc.floats.len(), rust_sc.floats.len());
        for ((n1, a), (n2, b)) in cpp_sc.floats.iter().zip(rust_sc.floats.iter()) {
            assert_eq!(n1, n2);
            let ok = compare_floats(n1, a, b, 1e-6);
            any_failed |= !ok;
        }

        // Strings (JSON) must be byte-identical.
        assert_eq!(cpp_sc.strings.len(), rust_sc.strings.len());
        for ((n1, a), (n2, b)) in cpp_sc.strings.iter().zip(rust_sc.strings.iter()) {
            assert_eq!(n1, n2);
            let ok = a == b;
            if !ok {
                any_failed = true;
                println!("{:<22} JSON differs", n1);
                println!("  cpp : {a}");
                println!("  rust: {b}");
            } else {
                println!("{:<22} identical ({} bytes)", n1, a.len());
            }
        }

        let media_ok = if std::path::Path::new(MEDIA_MP4).exists() && std::path::Path::new(MEDIA_WAV).exists() {
            println!("
== A/B real-media: Rust vs C++ (FFmpeg decode/encode) ==");
            !run_media_scenario(&cpp, &RustEngine)
        } else {
            println!("
== real-media scenario SKIPPED (test_video.mp4 / test_sine.wav missing) ==");
            true
        };
        any_failed |= !media_ok;

        let _ = ptr::null::<c_void>();
        println!();
        if any_failed {
            println!("RESULT: FAIL — parity mismatches found");
            std::process::exit(1);
        } else {
            println!("RESULT: PASS — full parity within tolerance (max channel diff ≤ 1)");
            std::process::exit(0);
        }
    }
}
