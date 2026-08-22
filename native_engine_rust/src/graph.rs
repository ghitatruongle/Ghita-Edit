//! Processing graph with per-node cache and dirty propagation — a minimal
//! GEGL-like lazy-evaluation pipeline (T1-P6 / optimization point #4).
//!
//! Nodes own their output as `Rc<Vec<u8>>`; `process()` returns the cached
//! buffer when the node is clean, so unchanged subtrees cost zero work. Any
//! `mark_dirty` propagates transitively to dependents (the renderer touches
//! one node — the whole affected subtree recomputes on the next process).

use std::cell::RefCell;
use std::rc::Rc;

use crate::compositor::apply_color_correction_to_buffer;
use crate::filters::apply_filter_to_buffer;
use crate::model::ColorCorrection;

/// What a node computes from its inputs.
#[derive(Clone, Debug)]
pub enum NodeKind {
    /// Copies the source frame (leaf).
    Decode,
    /// Applies a pixel filter (ids 0–22).
    Filter { filter_type: i32, intensity: f32 },
    /// Applies per-clip color correction.
    ColorCorrect(ColorCorrection),
    /// Alpha-blends input[0] over input[1].
    Blend { alpha: f32 },
}

struct GraphNode {
    kind: NodeKind,
    inputs: Vec<usize>,
    cache: RefCell<Option<Rc<Vec<u8>>>>,
    dirty: bool,
}

/// Lazy-evaluation processing graph.
pub struct ProcessingGraph {
    nodes: Vec<GraphNode>,
    output: Option<usize>,
}

impl Default for ProcessingGraph {
    fn default() -> Self {
        Self::new()
    }
}

impl ProcessingGraph {
    pub fn new() -> Self {
        ProcessingGraph { nodes: Vec::new(), output: None }
    }

    pub fn add_node(&mut self, kind: NodeKind, inputs: Vec<usize>) -> usize {
        let id = self.nodes.len();
        self.nodes.push(GraphNode { kind, inputs, cache: RefCell::new(None), dirty: true });
        id
    }

    pub fn set_output(&mut self, id: usize) {
        self.output = Some(id);
    }

    pub fn node_count(&self) -> usize {
        self.nodes.len()
    }

    /// Marks [id] and every transitive dependent dirty.
    pub fn mark_dirty(&mut self, id: usize) {
        if id >= self.nodes.len() {
            return;
        }
        // BFS over dependents (nodes that consume the dirty node transitively).
        let mut stack = vec![id];
        let mut visited = vec![false; self.nodes.len()];
        visited[id] = true;
        while let Some(n) = stack.pop() {
            self.nodes[n].dirty = true;
            for (i, node) in self.nodes.iter().enumerate() {
                if !visited[i] && node.inputs.contains(&n) {
                    visited[i] = true;
                    stack.push(i);
                }
            }
        }
    }

    /// Processes [id] (recursively), returning the cached or freshly computed
    /// frame. Clean nodes return their cache — O(1) after the first pass.
    pub fn process(&mut self, id: usize, width: usize, height: usize, source: &[u8]) -> Option<Rc<Vec<u8>>> {
        if id >= self.nodes.len() {
            return None;
        }
        // Clean → serve from cache.
        {
            let node = &self.nodes[id];
            if !node.dirty {
                if let Some(c) = node.cache.borrow().as_ref() {
                    return Some(Rc::clone(c));
                }
            }
        }

        let frame_bytes = width * height * 4;
        // Clone input ids first so the recursive process() calls don't borrow
        // self while a node reference is alive.
        let input_ids: Vec<usize> = {
            let node = &self.nodes[id];
            node.inputs.clone()
        };
        let inputs: Vec<Rc<Vec<u8>>> = input_ids
            .iter()
            .filter_map(|&in_id| self.process(in_id, width, height, source))
            .collect();

        let result: Vec<u8> = {
            let node = &self.nodes[id];
            match &node.kind {
                NodeKind::Decode => {
                    if source.len() < frame_bytes {
                        return None;
                    }
                    source[..frame_bytes].to_vec()
                }
                NodeKind::Filter { filter_type, intensity } => {
                    let mut buf = match inputs.first() {
                        Some(i) => (**i).clone(),
                        None => return None,
                    };
                    apply_filter_to_buffer(&mut buf, width, height, *filter_type, *intensity);
                    buf
                }
                NodeKind::ColorCorrect(cc) => {
                    let mut buf = match inputs.first() {
                        Some(i) => (**i).clone(),
                        None => return None,
                    };
                    apply_color_correction_to_buffer(&mut buf, width, height, cc);
                    buf
                }
                NodeKind::Blend { alpha } => {
                    // input[0] over input[1]
                    let (top, bottom) = match (inputs.first(), inputs.get(1)) {
                        (Some(t), Some(b)) => (t, b),
                        _ => return None,
                    };
                    let mut buf = (**bottom).clone();
                    crate::compositor::blend_rgba(&mut buf, top, width * height, *alpha);
                    buf
                }
            }
        };

        self.nodes[id].cache.replace(Some(Rc::new(result)));
        self.nodes[id].dirty = false;
        let node = &self.nodes[id];
        node.cache.borrow().as_ref().map(Rc::clone)
    }

    /// Renders the graph output (None when no output is set).
    pub fn render(&mut self, width: usize, height: usize, source: &[u8]) -> Option<Rc<Vec<u8>>> {
        let out = self.output?;
        self.process(out, width, height, source)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pattern(w: usize, h: usize) -> Vec<u8> {
        let mut buf = vec![0u8; w * h * 4];
        for y in 0..h {
            for x in 0..w {
                let i = (y * w + x) * 4;
                buf[i] = (x * 3 % 256) as u8;
                buf[i + 1] = (y * 5 % 256) as u8;
                buf[i + 2] = 200;
                buf[i + 3] = 255;
            }
        }
        buf
    }

    #[test]
    fn cache_hit_returns_same_rc() {
        let src = pattern(32, 18);
        let mut g = ProcessingGraph::new();
        let decode = g.add_node(NodeKind::Decode, vec![]);
        let filter = g.add_node(NodeKind::Filter { filter_type: 1, intensity: 1.0 }, vec![decode]);
        g.set_output(filter);

        let a = g.render(32, 18, &src).expect("render");
        let b = g.render(32, 18, &src).expect("render");
        // Second pass must hit the cache (same allocation).
        assert!(Rc::ptr_eq(&a, &b), "clean node must serve the cached buffer");
        // Grayscale applied.
        let px = &a[0..4];
        let y = (0.299 * px[0] as f32 + 0.587 * px[1] as f32 + 0.114 * px[2] as f32) as u8;
        assert_eq!(px[0], y);
        assert_eq!(px[1], y);
        assert_eq!(px[2], y);
    }

    #[test]
    fn dirty_propagation_recomputes() {
        let src = pattern(32, 18);
        let mut g = ProcessingGraph::new();
        let decode = g.add_node(NodeKind::Decode, vec![]);
        let filter = g.add_node(NodeKind::Filter { filter_type: 1, intensity: 1.0 }, vec![decode]);
        let cc = g.add_node(NodeKind::ColorCorrect(ColorCorrection::default()), vec![filter]);
        g.set_output(cc);

        let a = g.render(32, 18, &src).expect("render");
        // Mutate the filter node → propagates through cc → recompute.
        g.mark_dirty(filter);
        let b = g.render(32, 18, &src).expect("render");
        assert!(!Rc::ptr_eq(&a, &b), "dirty subtree must recompute");
        // Idempotent: same params → same pixels.
        assert_eq!(*a, *b);
    }

    #[test]
    fn blend_two_sources() {
        let mut src = pattern(16, 9);
        for px in src.chunks_exact_mut(4) {
            px[0] = 255;
            px[1] = 0;
            px[2] = 0; // red bottom
        }
        let mut top = vec![0u8; 16 * 9 * 4];
        for px in top.chunks_exact_mut(4) {
            px[0] = 0;
            px[1] = 0;
            px[2] = 255; // blue top
        }
        let mut g = ProcessingGraph::new();
        let d1 = g.add_node(NodeKind::Decode, vec![]);
        let d2 = g.add_node(NodeKind::Decode, vec![]);
        let blend = g.add_node(NodeKind::Blend { alpha: 0.5 }, vec![d2, d1]);
        g.set_output(blend);

        // Process inputs individually then the blend (simulate two sources).
        let _ = g.process(d1, 16, 9, &src);
        let _ = g.process(d2, 16, 9, &top);
        let out = g.render(16, 9, &src).expect("render");
        // 50% blue over red → purple-ish (127, 0, 127)
        let px = &out[0..4];
        assert_eq!(px[0], 127);
        assert_eq!(px[1], 0);
        assert_eq!(px[2], 127);
    }

    #[test]
    fn mark_dirty_invalid_id_is_noop() {
        let mut g = ProcessingGraph::new();
        g.mark_dirty(99);
        assert_eq!(g.node_count(), 0);
    }
}
