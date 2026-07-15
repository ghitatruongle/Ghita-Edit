#pragma once

#include <cstdint>
#include <string_view>

namespace ghita::engine {

// Hardware acceleration backends supported by Ghita Edit.
// The Decoder selects one at runtime based on availability and OS.
enum class HWBackend : uint8_t {
    None,       // pure software (CPU) decode
    NVDEC,      // NVIDIA CUDA/NVDEC
    QuickSync,  // Intel QuickSync (QSV)
    AMF,        // AMD AMF
    VAAPI,      // Video Acceleration API (Linux)
};

inline std::string_view to_string(HWBackend b) {
    switch (b) {
        case HWBackend::None:      return "software";
        case HWBackend::NVDEC:     return "nvdec";
        case HWBackend::QuickSync: return "quicksync";
        case HWBackend::AMF:       return "amf";
        case HWBackend::VAAPI:     return "vaapi";
    }
    return "unknown";
}

} // namespace ghita::engine
