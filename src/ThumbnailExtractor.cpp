// ThumbnailExtractor.cpp
#include "ThumbnailExtractor.h"
#include <QFile>
#include <QDir>

ThumbnailExtractor::ThumbnailExtractor(QObject *parent)
    : QObject(parent)
{
}

ThumbnailExtractor::~ThumbnailExtractor()
{
}

void ThumbnailExtractor::extractThumbnail(const QString &videoPath, const QString &outputPath, int timeMs, int index)
{
    QImage frame = decodeFrame(videoPath, timeMs);
    if (!frame.isNull()) {
        QDir dir = QFileInfo(outputPath).absoluteDir();
        if (!dir.exists()) {
            dir.mkpath(".");
        }
        if (frame.save(outputPath, "PNG")) {
            emit thumbnailExtracted(index, outputPath);
        }
    }
}

QImage ThumbnailExtractor::decodeFrame(const QString &videoPath, int timeMs)
{
    AVFormatContext *formatContext = avformat_alloc_context();
    if (!formatContext)
        return QImage();

    std::string videoPathStr = videoPath.toStdString();
    if (avformat_open_input(&formatContext, videoPathStr.c_str(), nullptr, nullptr) < 0) {
        avformat_free_context(formatContext);
        return QImage();
    }

    if (avformat_find_stream_info(formatContext, nullptr) < 0) {
        avformat_close_input(&formatContext);
        return QImage();
    }

    // Find video stream
    int videoStreamIndex = -1;
    for (unsigned int i = 0; i < formatContext->nb_streams; i++) {
        if (formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoStreamIndex = i;
            break;
        }
    }

    if (videoStreamIndex == -1) {
        avformat_close_input(&formatContext);
        return QImage();
    }

    AVStream *videoStream = formatContext->streams[videoStreamIndex];
    AVCodecParameters *codecPar = videoStream->codecpar;

    const AVCodec *codec = avcodec_find_decoder(codecPar->codec_id);
    if (!codec) {
        avformat_close_input(&formatContext);
        return QImage();
    }

    AVCodecContext *codecContext = avcodec_alloc_context3(codec);
    if (avcodec_parameters_to_context(codecContext, codecPar) < 0) {
        avcodec_free_context(&codecContext);
        avformat_close_input(&formatContext);
        return QImage();
    }

    if (avcodec_open2(codecContext, codec, nullptr) < 0) {
        avcodec_free_context(&codecContext);
        avformat_close_input(&formatContext);
        return QImage();
    }

    // Seek to time
    int64_t timestamp = av_rescale_q(timeMs, AV_TIME_BASE_Q, videoStream->time_base);
    av_seek_frame(formatContext, videoStreamIndex, timestamp, AVSEEK_FLAG_BACKWARD);

    AVPacket *packet = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    AVFrame *rgbFrame = av_frame_alloc();

    QImage result;

    while (av_read_frame(formatContext, packet) >= 0) {
        if (packet->stream_index != videoStreamIndex) {
            av_packet_unref(packet);
            continue;
        }

        if (avcodec_send_packet(codecContext, packet) >= 0) {
            if (avcodec_receive_frame(codecContext, frame) >= 0) {
                // Convert to RGB
                struct SwsContext *swsContext = sws_getContext(
                    frame->width, frame->height, codecContext->pix_fmt,
                    frame->width, frame->height, AV_PIX_FMT_RGB24,
                    SWS_BILINEAR, nullptr, nullptr, nullptr);

                if (swsContext) {
                    int numBytes = av_image_get_buffer_size(AV_PIX_FMT_RGB24, frame->width, frame->height, 1);
                    uint8_t *buffer = (uint8_t *)av_malloc(numBytes);
                    if (av_image_fill_arrays(rgbFrame->data, rgbFrame->linesize, buffer,
                                             AV_PIX_FMT_RGB24, frame->width, frame->height, 1) < 0) {
                        av_free(buffer);
                        sws_freeContext(swsContext);
                        av_frame_unref(frame);
                        av_packet_unref(packet);
                        continue;
                    }

                    sws_scale(swsContext, frame->data, frame->linesize, 0, frame->height,
                              rgbFrame->data, rgbFrame->linesize);

                    result = QImage(rgbFrame->data[0], frame->width, frame->height,
                                   rgbFrame->linesize[0], QImage::Format_RGB888).copy();

                    av_free(buffer);
                    sws_freeContext(swsContext);
                }

                av_frame_unref(frame);
                break;
            }
        }
        av_packet_unref(packet);
    }

    av_frame_free(&rgbFrame);
    av_frame_free(&frame);
    av_packet_free(&packet);
    avcodec_free_context(&codecContext);
    avformat_close_input(&formatContext);

    return result;
}
