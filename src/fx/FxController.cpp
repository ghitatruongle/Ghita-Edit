#include "fx/FxController.h"

// FxController is a header-heavy QObject; this translation unit exists so the
// meta-object compiler (AUTOMOC) has an owning source file and the vtable is
// emitted. All logic lives in the header.
namespace ghita::fx {
} // namespace ghita::fx
