#include "SnapEngine.h"
#include <cmath>

namespace ghita::timeline {

SnapEngine::SnapEngine(QObject* parent) : QObject(parent) {}

void SnapEngine::setThresholdMs(int ms) {
    if (thresholdMs_ == ms) return;
    thresholdMs_ = ms;
    emit thresholdChanged();
}

qint64 SnapEngine::snap(qint64 candidateMs, const QVariantList& targets) const {
    qint64 bestDist = thresholdMs_ + 1;
    qint64 bestSnap = candidateMs;

    for (const auto& v : targets) {
        qint64 target = v.toLongLong();
        qint64 dist = std::abs(candidateMs - target);
        if (dist < bestDist) {
            bestDist = dist;
            bestSnap = target;
        }
    }

    return bestSnap;
}

qint64 SnapEngine::snapToTimeline(qint64 candidateMs,
                                   const QVariantList& targets) const {
    return snap(candidateMs, targets);
}

} // namespace ghita::timeline
