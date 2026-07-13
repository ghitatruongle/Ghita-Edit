// MediaBinModel.cpp
#include "MediaBinModel.h"
#include "ThumbnailExtractor.h"
#include <QFileInfo>
#include <QFile>
#include <QDir>
#include <QDebug>

MediaBinModel::MediaBinModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_extractor(new ThumbnailExtractor())
    , m_extractorThread(new QThread(this))
{
    m_extractor->moveToThread(m_extractorThread);
    connect(m_extractor, &ThumbnailExtractor::thumbnailExtracted,
            this, &MediaBinModel::onThumbnailExtracted);
    m_extractorThread->start();
}

MediaBinModel::~MediaBinModel()
{
    m_extractorThread->quit();
    m_extractorThread->wait();
    delete m_extractor;
}

int MediaBinModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent);
    return m_items.count();
}

QVariant MediaBinModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.count())
        return QVariant();

    const MediaItem &item = m_items.at(index.row());

    switch (role) {
    case FilePathRole:
        return item.filePath;
    case FileNameRole:
        return item.fileName;
    case DurationMsRole:
        return item.durationMs;
    case ThumbnailPathRole:
        return item.thumbnailPath;
    case ThumbnailReadyRole:
        return item.thumbnailReady;
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> MediaBinModel::roleNames() const
{
    return {
        {FilePathRole, "filePath"},
        {FileNameRole, "fileName"},
        {DurationMsRole, "durationMs"},
        {ThumbnailPathRole, "thumbnailPath"},
        {ThumbnailReadyRole, "thumbnailReady"}
    };
}

bool MediaBinModel::addMedia(const QString &filePath)
{
    QFileInfo info(filePath);
    if (!info.exists()) {
        qWarning() << "MediaBinModel: File not found:" << filePath;
        emit mediaError("File not found: " + filePath);
        return false;
    }

    // Check if already added
    for (const auto &item : m_items) {
        if (item.filePath == filePath) {
            qWarning() << "MediaBinModel: File already in bin:" << filePath;
            emit mediaError("File already imported: " + info.fileName());
            return false;
        }
    }

    int itemIndex = m_items.size();
    beginInsertRows(QModelIndex(), itemIndex, itemIndex);

    MediaItem item;
    item.filePath = filePath;
    item.fileName = info.fileName();
    item.durationMs = 0;  // Will be filled by engine
    item.thumbnailPath = "";
    item.thumbnailReady = false;
    m_items.append(item);

    endInsertRows();
    emit countChanged();
    emit mediaAdded(itemIndex);

    // Extract thumbnail asynchronously
    QString thumbPath = QDir::tempPath() + "/ghita-edit/thumbnails/" +
                       QString::number(itemIndex) + ".png";
    QDir().mkpath(QDir::tempPath() + "/ghita-edit/thumbnails/");

    QMetaObject::invokeMethod(m_extractor, "extractThumbnail",
                              Qt::QueuedConnection,
                              Q_ARG(QString, filePath),
                              Q_ARG(QString, thumbPath),
                              Q_ARG(int, 0),
                              Q_ARG(int, itemIndex));

    return true;
}

void MediaBinModel::removeMedia(int index)
{
    if (index < 0 || index >= m_items.count())
        return;

    beginRemoveRows(QModelIndex(), index, index);
    m_items.removeAt(index);
    endRemoveRows();

    emit countChanged();
}

void MediaBinModel::clear()
{
    if (m_items.isEmpty())
        return;

    beginResetModel();
    m_items.clear();
    endResetModel();

    emit countChanged();
}

int MediaBinModel::count() const
{
    return m_items.count();
}

void MediaBinModel::onThumbnailExtracted(int index, const QString &path)
{
    if (index < 0 || index >= m_items.count())
        return;

    m_items[index].thumbnailPath = path;
    m_items[index].thumbnailReady = true;

    QModelIndex modelIndex = createIndex(index, 0);
    emit dataChanged(modelIndex, modelIndex, {ThumbnailPathRole, ThumbnailReadyRole});
    emit thumbnailReady(index, path);
}
