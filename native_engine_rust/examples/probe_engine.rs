//! T6 debug: engine-level load_media + media_info.
fn main() {
    let path = std::env::args().nth(1).expect("usage: probe_engine <file>");
    let e = ghita_engine::engine::GhitaEngine::new();
    assert!(e.initialize());
    let ok = e.load_media(&path);
    let info = e.get_media_info_json();
    let is_synthetic = info.contains("synthetic");
    println!("load_media={ok} synthetic={is_synthetic}");
    println!("media_info={info}");
}
