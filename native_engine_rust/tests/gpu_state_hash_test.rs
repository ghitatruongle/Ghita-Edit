#![cfg(feature = "gpu")]
//! v1.5.5-demo (B1 review fix): the GPU dispatch switch changes filter output
//! (±1/255 vs CPU) — it must be folded into the paused-render cache hash so
//! toggling it serves a fresh frame instead of a stale cached one.

use std::ffi::{CStr, CString};

use ghita_engine::c_api::*;

fn cache_misses(ctx: *mut GhitaEngineContext) -> u64 {
    unsafe {
        let p = ghita_engine_cache_stats(ctx);
        assert!(!p.is_null());
        let s = CStr::from_ptr(p).to_str().unwrap();
        // {"hits":H,"misses":M,"entries":E,"rate":R}
        let i = s.find("\"misses\":").expect("misses key") + "\"misses\":".len();
        let rest = &s[i..];
        let end = rest.find([',', '}']).expect("terminator");
        rest[..end].parse().expect("misses value")
    }
}

#[test]
fn gpu_toggle_invalidates_paused_frame_cache() {
    let p = unsafe { ghita_engine_create() };
    assert!(!p.is_null());
    assert_eq!(unsafe { ghita_engine_init(p) }, 0);
    let path = CString::new("missing.mp4").unwrap();
    assert_eq!(
        unsafe { ghita_engine_upsert_clip(p, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) },
        1
    );
    unsafe { ghita_engine_seek(p, 1000) };

    let mut buf = vec![0u8; 64 * 36 * 4];
    unsafe { ghita_engine_set_gpu_enabled(0) };
    assert!(unsafe { ghita_engine_render_frame_at(p, buf.as_mut_ptr(), 64, 36, 1000) });
    let m0 = cache_misses(p);
    // Same state → cache hit, misses unchanged.
    assert!(unsafe { ghita_engine_render_frame_at(p, buf.as_mut_ptr(), 64, 36, 1000) });
    let m1 = cache_misses(p);
    assert_eq!(m0, m1, "same-state render must be a cache hit");

    // Toggle GPU → hash epoch change → fresh render (miss), even though the
    // bytes may be identical (filter 0 never dispatches to the GPU).
    unsafe { ghita_engine_set_gpu_enabled(1) };
    assert!(unsafe { ghita_engine_render_frame_at(p, buf.as_mut_ptr(), 64, 36, 1000) });
    let m2 = cache_misses(p);
    assert!(m2 > m1, "GPU toggle must invalidate the paused frame cache");

    unsafe { ghita_engine_set_gpu_enabled(0) };
    assert!(unsafe { ghita_engine_render_frame_at(p, buf.as_mut_ptr(), 64, 36, 1000) });
    let m3 = cache_misses(p);
    assert!(m3 > m2, "toggling back must invalidate again");

    unsafe { ghita_engine_destroy(p) };
}
