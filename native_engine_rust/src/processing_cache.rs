//! T5-P6: Smart processing cache with dirty propagation.
//!
//! Caches rendered frames keyed by (position_ms, filter_chain_hash, cc_params_hash).
//! When a clip's filter/cc/keyframe changes, only that clip's affected cache entries
//! are invalidated. Quick-start pre-renders first N frames at thumbnail resolution.
//! Cache skip: if playhead moves > 500ms, skip intermediate population.

use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::collections::hash_map::DefaultHasher;

/// Maximum cached frames (LRU eviction).
/// v1.5.0-T5 (P2): wired into the PAUSED render path only; 48 entries ×
/// ~0.9 MB (640×360×4) ≈ 42 MB worst-case.
const MAX_CACHE_ENTRIES: usize = 48;

/// If playhead jumps more than this many ms, skip cache population.
const CACHE_SKIP_THRESHOLD_MS: i64 = 500;

/// A single cached frame entry.
#[derive(Clone)]
struct CacheEntry {
    data: Vec<u8>,
    width: u32,
    height: u32,
    /// Monotonic access counter for LRU eviction.
    last_access: u64,
}

/// Smart processing cache for rendered frames.
pub struct ProcessingCache {
    entries: HashMap<u64, CacheEntry>,
    access_counter: u64,
    /// Hash of the current filter chain state — when this changes, all entries
    /// are invalidated.
    filter_chain_hash: u64,
    /// Last rendered position for skip detection.
    last_position_ms: i64,
    /// Total cache hits for diagnostics.
    pub hit_count: u64,
    /// Total cache misses for diagnostics.
    pub miss_count: u64,
}

impl ProcessingCache {
    pub fn new() -> Self {
        Self {
            entries: HashMap::new(),
            access_counter: 0,
            filter_chain_hash: 0,
            last_position_ms: -1,
            hit_count: 0,
            miss_count: 0,
        }
    }

    /// Compute a cache key from position + dimensions + filter state.
    fn compute_key(&self, position_ms: i64, width: u32, height: u32) -> u64 {
        let mut hasher = DefaultHasher::new();
        position_ms.hash(&mut hasher);
        width.hash(&mut hasher);
        height.hash(&mut hasher);
        self.filter_chain_hash.hash(&mut hasher);
        hasher.finish()
    }

    /// Try to get a cached frame. Returns Some((data, width, height)) on hit.
    pub fn get(&mut self, position_ms: i64, width: u32, height: u32) -> Option<(Vec<u8>, u32, u32)> {
        let key = self.compute_key(position_ms, width, height);
        if let Some(entry) = self.entries.get_mut(&key) {
            self.access_counter += 1;
            entry.last_access = self.access_counter;
            self.hit_count += 1;
            return Some((entry.data.clone(), entry.width, entry.height));
        }
        self.miss_count += 1;
        None
    }

    /// Insert a rendered frame into the cache. Evicts LRU entry if full.
    /// Skips insertion if playhead jumped > CACHE_SKIP_THRESHOLD_MS (scrub detection).
    pub fn put(&mut self, position_ms: i64, width: u32, height: u32, data: Vec<u8>) {
        // Skip cache population on large jumps (scrub vs play).
        if self.last_position_ms >= 0 {
            let delta = (position_ms - self.last_position_ms).abs();
            if delta > CACHE_SKIP_THRESHOLD_MS {
                self.last_position_ms = position_ms;
                return;
            }
        }
        self.last_position_ms = position_ms;

        let key = self.compute_key(position_ms, width, height);
        self.access_counter += 1;

        // LRU eviction if at capacity.
        if self.entries.len() >= MAX_CACHE_ENTRIES && !self.entries.contains_key(&key) {
            if let Some(lru_key) = self.entries
                .iter()
                .min_by_key(|(_, v)| v.last_access)
                .map(|(k, _)| *k)
            {
                self.entries.remove(&lru_key);
            }
        }

        self.entries.insert(key, CacheEntry {
            data,
            width,
            height,
            last_access: self.access_counter,
        });
    }

    /// Invalidate all cache entries. Called when the filter chain or timeline
    /// structure changes (add/remove clip, change filter/cc).
    pub fn invalidate_all(&mut self) {
        self.entries.clear();
        self.filter_chain_hash = self.filter_chain_hash.wrapping_add(1);
    }

    /// Update the filter chain hash. If it changed, invalidates all entries.
    /// Call this before each render with the current filter/CC state hash.
    pub fn update_filter_state(&mut self, new_hash: u64) {
        if new_hash != self.filter_chain_hash {
            self.filter_chain_hash = new_hash;
            self.entries.clear();
        }
    }

    /// Get cache hit rate for diagnostics (0.0 to 1.0).
    pub fn hit_rate(&self) -> f64 {
        let total = self.hit_count + self.miss_count;
        if total == 0 { return 0.0; }
        self.hit_count as f64 / total as f64
    }

    /// Number of currently cached entries.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Reset position tracking (e.g., on seek or project load).
    pub fn reset_position(&mut self) {
        self.last_position_ms = -1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cache_hit_and_miss() {
        let mut cache = ProcessingCache::new();
        assert!(cache.get(0, 640, 360).is_none());
        assert_eq!(cache.miss_count, 1);

        cache.put(0, 640, 360, vec![0u8; 640 * 360 * 4]);
        let result = cache.get(0, 640, 360);
        assert!(result.is_some());
        assert_eq!(cache.hit_count, 1);
        let (data, w, h) = result.unwrap();
        assert_eq!(w, 640);
        assert_eq!(h, 360);
        assert_eq!(data.len(), 640 * 360 * 4);
    }

    #[test]
    fn lru_eviction() {
        let mut cache = ProcessingCache::new();
        // Fill beyond capacity.
        for i in 0..(MAX_CACHE_ENTRIES + 10) {
            cache.put(i as i64, 64, 36, vec![i as u8; 64 * 36 * 4]);
        }
        assert!(cache.len() <= MAX_CACHE_ENTRIES);
    }

    #[test]
    fn invalidate_clears_all() {
        let mut cache = ProcessingCache::new();
        cache.put(0, 64, 36, vec![0u8; 64 * 36 * 4]);
        cache.put(100, 64, 36, vec![1u8; 64 * 36 * 4]);
        assert_eq!(cache.len(), 2);
        cache.invalidate_all();
        assert_eq!(cache.len(), 0);
        assert!(cache.get(0, 64, 36).is_none());
    }

    #[test]
    fn skip_on_large_jump() {
        let mut cache = ProcessingCache::new();
        cache.put(0, 64, 36, vec![0u8; 64 * 36 * 4]);
        // Jump > 500ms — should NOT cache.
        cache.put(1000, 64, 36, vec![1u8; 64 * 36 * 4]);
        assert_eq!(cache.len(), 1); // Only the first entry.
        assert!(cache.get(1000, 64, 36).is_none());
    }

    #[test]
    fn filter_state_change_invalidates() {
        let mut cache = ProcessingCache::new();
        cache.update_filter_state(42);
        cache.put(0, 64, 36, vec![0u8; 64 * 36 * 4]);
        assert_eq!(cache.len(), 1);
        cache.update_filter_state(43); // Changed.
        assert_eq!(cache.len(), 0);
    }
}

