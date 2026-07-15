#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariant>

namespace ghita::audio {

class AudioEngine;

class AudioMixerController : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(float masterVolume READ masterVolume WRITE setMasterVolume NOTIFY changed)
    Q_PROPERTY(QVariantList trackStates READ trackStates NOTIFY changed)

public:
    explicit AudioMixerController(AudioEngine* engine, QObject* parent = nullptr);

    float masterVolume() const;
    QVariantList trackStates() const;

    Q_INVOKABLE void setTrackVolume(int trackIndex, float linearGain);
    Q_INVOKABLE float trackVolume(int trackIndex) const;

    Q_INVOKABLE void setTrackPan(int trackIndex, float pan);
    Q_INVOKABLE float trackPan(int trackIndex) const;

    Q_INVOKABLE void setTrackMute(int trackIndex, bool muted);
    Q_INVOKABLE bool isTrackMuted(int trackIndex) const;

public slots:
    void setMasterVolume(float linearGain);

signals:
    void changed();

private:
    AudioEngine* engine_;
    float masterGain_ = 1.0f;
};

} // namespace ghita::audio
