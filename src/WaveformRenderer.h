// WaveformRenderer.h — Extracts PCM from media files and computes RMS-based
// waveform data suitable for timeline rendering.
//
// Pattern: mirrors ThumbnailExtractor (FFmpeg decode + libswresample resample
// to 48 kHz stereo float), but instead of producing a QImage it produces a
// QVector<float> of RMS envelope values — one per pixel column — so the QML
// layer can paint whatever shape it wants.
//
// Audio frame layout: interleaved float, 48 kHz stereo, stored in
// Frame::rgba (same as the rest of the pipeline).

#pragma once

#include <QObject>
#include <QImage>
#include <QString>
#include <QVector>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libswresample/swresample.h>
}

class WaveformRenderer : public QObject
{
    Q_OBJECT

public:
    explicit WaveformRenderer(QObject *parent = nullptr);
    ~WaveformRenderer();

    /**
     * Compute the RMS envelope for an audio file.
     *
     * Decodes the entire audio portion of @p mediaPath, resamples to 48 kHz
     * stereo float, and returns @p columns RMS values — one per pixel column.
     *
     * Returns an empty vector if the file has no audio stream or decoding
     * fails.
     */
    QVector<float> computeEnvelope(const QString &mediaPath, int columns);

    /**
     * Pre-compute and cache the envelope for a given media path.
     *
     * Subsequent calls with the same path and column count return the cached
     * result instantly. Cache entries older than 10 minutes are evicted.
     */
    QVector<float> getOrComputeEnvelope(const QString &mediaPath, int columns);

private:
    // Decode audio frames from the file and accumulate into a single PCM buffer.
    QVector<float> decodeAudioToPCM(const QString &mediaPath);

    // Compute RMS of samples[start..start+count-1].
    static float rms(const float *samples, int count);

    // Down-sample the full PCM envelope to @p target columns via averaging.
    QVector<float> downsampleEnvelope(const QVector<float> &full, int targetColumns);

    // ---- Cache ----
    struct CacheEntry {
        QString key;
        QVector<float> envelope;
        qint64 timestamp;   // ms since epoch
    };
    QVector<CacheEntry> cache_;
    static constexpr int kCacheAgeMinutes = 10;
};
