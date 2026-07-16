// MediaBinModel.cpp
#include "MediaBinModel.h"
#include "ThumbnailExtractor.h"
#include "engine/Decoder.h"

#include <QFileInfo>
#include <QFile>
#include <QDir>
#include <QDebug>

extern "C" {
#include <libavformat/avformat.h>
}

namespace {

// Probe a file to determine if it contains video, audio, or both.
int probeMediaType(const QString &path) {
    avformat_network_init();
    AVFormatContext *fmtCtx = nullptr;
    int ret = avformat_open_input(&fmtCtx, path.toUtf8().constData(), nullptr, nullptr);
    if (ret < 0 || !fmtCtx) {
        avformat_close_input(&fmtCtx);
        avformat_network_deinit();
        // Fall back to extension-based heuristic.
        QString ext = QFileInfo(path).suffix().toLower();
        QSet<QString> videoExts = {"mp4","mkv","avi","mov","wmv","flv","webm","m4v","mpg","mpeg","3gp"};
        QSet<QString> audioExts = {"mp3","wav","aac","m4a","flac","ogg","wma","opus"};
        if (videoExts.contains(ext)) return 1;       // video
        if (audioExts.contains(ext)) return 2;       // audio
        return 0; // unknown
    }
    if (avformat_find_stream_info(fmtCtx, nullptr) < 0) {
        avformat_close_input(&fmtCtx);
        avformat_network_deinit();
        return 0;
    }
    bool hasVideo = false, hasAudio = false;
    for (unsigned i = 0; i < fmtCtx->nb_streams; ++i) {
        auto type = fmtCtx->streams[i]->codecpar->codec_type;
        if (type == AVMEDIA_TYPE_VIDEO) hasVideo = true;
        if (type == AVMEDIA_TYPE_AUDIO) hasAudio = true;
    }
    avformat_close_input(&fmtCtx);
    avformat_network_deinit();
    if (hasVideo && hasAudio) return 3;  // both
    if (hasVideo) return 1;              // video
    if (hasAudio) return 2;              // audio
    return 0;                            // unknown
}

} // namespace

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
    case MediaTypeRole:
        return item.mediaType;
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
        {ThumbnailReadyRole, "thumbnailReady"},
        {MediaTypeRole, "mediaType"}
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
    item.mediaType = probeMediaType(filePath);
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
