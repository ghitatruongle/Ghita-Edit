// MediaBinModel.h
#pragma once

#include <QAbstractListModel>
#include <QUrl>
#include <QImage>
#include <QThread>
#include <QMutex>

struct MediaItem {
    QString filePath;
    QString fileName;
    qint64 durationMs;
    QString thumbnailPath;
    bool thumbnailReady;
};

class ThumbnailExtractor;

class MediaBinModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        FilePathRole = Qt::UserRole + 1,
        FileNameRole,
        DurationMsRole,
        ThumbnailPathRole,
        ThumbnailReadyRole
    };

    explicit MediaBinModel(QObject *parent = nullptr);
    ~MediaBinModel();

    // QAbstractListModel interface
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Custom methods
    Q_INVOKABLE void addMedia(const QString &filePath);
    Q_INVOKABLE void removeMedia(int index);
    Q_INVOKABLE void clear();
    int count() const;

signals:
    void countChanged();
    void thumbnailReady(int index, const QString &path);

private slots:
    void onThumbnailExtracted(int index, const QString &path);

private:
    QList<MediaItem> m_items;
    ThumbnailExtractor *m_extractor;
    QThread *m_extractorThread;
};
