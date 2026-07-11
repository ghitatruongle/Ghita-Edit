// ThumbnailExtractor.h
#pragma once

#include <QObject>
#include <QImage>
#include <QString>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}

class ThumbnailExtractor : public QObject
{
    Q_OBJECT

public:
    explicit ThumbnailExtractor(QObject *parent = nullptr);
    ~ThumbnailExtractor();

public slots:
    void extractThumbnail(const QString &videoPath, const QString &outputPath, int timeMs);

signals:
    void thumbnailExtracted(int index, const QString &path);

private:
    QImage decodeFrame(const QString &videoPath, int timeMs);
};
