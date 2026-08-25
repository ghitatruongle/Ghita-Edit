//! T6 debug: print exact FFmpeg failure stage for an input file.
//! Usage: cargo run --features ffmpeg --example probe_png -- <file>

#[cfg(feature = "ffmpeg")]
fn main() {
    use ffmpeg_sys_next::*;
    let path = std::env::args().nth(1).expect("usage: probe_png <file>");
    unsafe {
        let mut fmt: *mut AVFormatContext = std::ptr::null_mut();
        let c = std::ffi::CString::new(path.clone()).unwrap();
        let ret = avformat_open_input(&mut fmt, c.as_ptr(), std::ptr::null_mut(), std::ptr::null_mut());
        println!("open_input ret = {ret} ({})", err(ret));
        if ret != 0 {
            return;
        }
        let r2 = avformat_find_stream_info(fmt, std::ptr::null_mut());
        println!("find_stream_info ret = {r2} ({})", err(r2));
        let nb = (*fmt).nb_streams;
        println!("nb_streams = {nb}");
        for i in 0..nb {
            let st = *(*fmt).streams.add(i as usize);
            let par = (*st).codecpar;
            println!(
                "  stream {i}: type={} codec_id={} {}x{}",
                (*par).codec_type as i32,
                (*par).codec_id as i32,
                (*par).width,
                (*par).height
            );
        }
        unsafe extern "C" fn err(code: i32) -> String {
            let mut buf = [0i8; 256];
            if av_strerror(code, buf.as_mut_ptr() as *mut _, 256) == 0 {
                let cstr = std::ffi::CStr::from_ptr(buf.as_ptr() as *const _);
                cstr.to_string_lossy().into_owned()
            } else {
                format!("code {code}")
            }
        }
    }
}

#[cfg(not(feature = "ffmpeg"))]
fn main() {
    println!("build with --features ffmpeg");
}
