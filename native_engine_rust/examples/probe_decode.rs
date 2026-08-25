//! T6 debug: exercise the PRODUCTION MediaDecoder path on an input file.
//! Usage: cargo run --features ffmpeg --example probe_decode -- <file>

fn main() {
    let path = std::env::args().nth(1).expect("usage: probe_decode <file>");
    let mut d = ghita_engine::synth::MediaDecoder::new();
    let opened = d.open(&path);
    println!("open={} has_ffmpeg={} {}x{} dur={}ms",
             opened, d.has_ffmpeg, d.width, d.height, d.duration_ms);

    let (w, h) = (64usize, 64usize);
    let mut buf = vec![0u8; w * h * 4];
    let ok = d.decode_frame(&mut buf, w, h, 100, 0, 1.0);
    println!("decode_frame@100ms ok={ok}");
    // Count distinct colors — solid input must stay solid if truly decoded;
    // synthetic fallback draws a multi-color gradient/circles.
    let mut set = std::collections::HashSet::new();
    for px in buf.chunks_exact(4) {
        set.insert((px[0], px[1], px[2]));
    }
    println!("distinct colors = {}", set.len());
}
