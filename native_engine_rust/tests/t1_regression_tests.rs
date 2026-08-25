//! v1.5.0-T1 regression tests — memory-safety fixes at the FFI boundary.
//!
//! Covers:
//! * selection/mask exports rejecting invalid geometry instead of panicking
//!   or aborting (they previously ran without catch_unwind guards);
//! * export flags resetting after a run so a failed export can never brick
//!   `is_exporting`, and cancel_export staying race-safe.

use std::ptr;

use ghita_engine::c_api::*;
use ghita_engine::engine::GhitaEngine;

// Selection FFI ---------------------------------------------------------------

#[test]
fn t1_selection_rect_rejects_nonpositive_dims() {
    assert_eq!(unsafe { ghita_engine_set_selection_rect(-1, 64, 0, 0, 8, 8, 0) }, -1);
    assert_eq!(unsafe { ghita_engine_set_selection_rect(64, 0, 0, 0, 8, 8, 0) }, -1);
    assert_eq!(unsafe { ghita_engine_set_selection_rect(64, 64, 0, 0, -5, 8, 0) }, -1);
    // A valid call still works and reports success.
    assert_eq!(unsafe { ghita_engine_set_selection_rect(64, 64, 0, 0, 10, 10, 0) }, 0);
    unsafe { ghita_engine_clear_selection() };
}

#[test]
fn t1_selection_ellipse_rejects_nonpositive_dims() {
    assert_eq!(unsafe { ghita_engine_set_selection_ellipse(0, 32, 16, 16, 4, 4, 0) }, -1);
    assert_eq!(unsafe { ghita_engine_set_selection_ellipse(32, 32, 16, 16, 4, 4, 0) }, 0);
    unsafe { ghita_engine_clear_selection() };
}

#[test]
fn t1_selection_lasso_rejects_bad_input() {
    assert_eq!(
        unsafe { ghita_engine_set_selection_lasso(32, 32, ptr::null(), ptr::null(), 3, 0) },
        -1
    );
    let xs = [0i32, 20, 10];
    let ys = [0i32, 5, 25];
    assert_eq!(
        unsafe { ghita_engine_set_selection_lasso(32, 32, xs.as_ptr(), ys.as_ptr(), 3, 0) },
        0
    );
    unsafe { ghita_engine_clear_selection() };
}

#[test]
fn t1_magic_wand_rejects_null_and_huge_dims() {
    // Null image / non-positive dims must fail fast — previously an i32
    // `width * height * 4` overflow built a garbage-length slice.
    assert_eq!(unsafe { ghita_engine_set_selection_magic_wand(-1, -1, 0, 0, 0.0, ptr::null(), 0) }, -1);
    assert_eq!(unsafe { ghita_engine_set_selection_magic_wand(i32::MAX, i32::MAX, 0, 0, 0.0, ptr::null(), 0) }, -1);
    // Valid tiny image (4×4 RGBA).
    let img = [128u8; 4 * 4 * 4];
    assert_eq!(unsafe { ghita_engine_set_selection_magic_wand(4, 4, 0, 0, 0.0, img.as_ptr(), 0) }, 0);
    unsafe { ghita_engine_clear_selection() };
}

#[test]
fn t1_get_mask_buffer_tolerates_negative_size() {
    assert_eq!(unsafe { ghita_engine_set_selection_rect(16, 16, 0, 0, 8, 8, 0) }, 0);
    // A negative buf_size used to wrap into a huge usize; it must copy
    // nothing while still reporting the mask length.
    let len = unsafe { ghita_engine_get_mask_buffer(ptr::null_mut(), -5) };
    assert_eq!(len, 16 * 16);
    let mut out = [7u8; 16 * 16];
    let len2 = unsafe { ghita_engine_get_mask_buffer(out.as_mut_ptr(), -5) };
    assert_eq!(len2, 16 * 16);
    assert!(out.iter().all(|&b| b == 7), "no bytes may be written");
    unsafe { ghita_engine_clear_selection() };
}

// Export flag hygiene -----------------------------------------------------------

#[test]
fn t1_export_flags_reset_after_cancelled_run() {
    let e = GhitaEngine::new();
    assert!(e.initialize());
    // The synthetic default timeline makes the run long enough to cancel
    // midway. Cancel joins the thread; the critical property is that
    // is_exporting ends DOWN — a stuck true flag bricked every future export.
    assert!(e.start_export_ex("t1_cancel_out.bin", 320, 240, 30, "h264", 1_000_000, false));
    assert!(e.is_exporting());
    e.cancel_export();
    assert!(!e.is_exporting(), "is_exporting must reset after cancel");
    // Not bricked: a fresh start claims the export slot again.
    assert!(e.start_export_ex("t1_cancel_out2.bin", 320, 240, 30, "h264", 1_000_000, false));
    e.cancel_export();
    assert!(!e.is_exporting());
    let _ = std::fs::remove_file("t1_cancel_out.bin");
    let _ = std::fs::remove_file("t1_cancel_out2.bin");
}

#[test]
fn t1_cancel_export_without_active_run_is_safe() {
    let e = GhitaEngine::new();
    assert!(e.initialize());
    // No export was ever started — cancel must be a silent no-op (it used to
    // check is_exporting before taking the join mutex: TOCTOU).
    e.cancel_export();
    assert!(!e.is_exporting());
}
