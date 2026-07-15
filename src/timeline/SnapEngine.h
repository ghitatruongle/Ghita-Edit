#pragma once

#include <QObject>
#include <QVariantList>
#include <cstdint>

namespace ghita::timeline {

// SnapEngine: computes snap points from clip edges and playhead position.
//
// When the user drags a clip or trims an edge, the SnapEngine suggests
// a nearby "snapped" position if one is within the threshold. This gives
// that satisfying magnetic feel in professional editors.
class SnapEngine : public QObject {
    Q_OBJECT
    Q_PROPERTY(int thresholdMs READ thresholdMs WRITE setThresholdMs NOTIFY thresholdChanged)

public:
    explicit SnapEngine(QObject* parent = nullptr);

    int thresholdMs() const { return thresholdMs_; }
    void setThresholdMs(int ms);

    // Given a candidate position and a list of snap targets, returns the
    // snapped position if one is within threshold, otherwise returns the
    // original position unchanged.
    Q_INVOKABLE qint64 snap(qint64 candidateMs, const QVariantList& targets) const;

    // Convenience: snap using targets from a TimelineModel.
    Q_INVOKABLE qint64 snapToTimeline(qint64 candidateMs,
                                       const QVariantList& targets) const;

signals:
    void thresholdChanged();

private:
    int thresholdMs_ = 10; // default: snap within 10 ms
};

} // namespace ghita::timeline
