#include "PreviewSurface.h"

#include <QSGGeometryNode>
#include <QSGGeometry>
#include <QSGTextureMaterial>
#include <QQuickWindow>
#include <QImage>

#include <QDebug>
#include <cstring>

#include "fx/FxController.h"

namespace ghita::render {

// Internal QSG node that owns a texture and a textured quad.
class TextureNode : public QSGGeometryNode {
public:
    TextureNode() {
        // Unit quad (0..1) with UVs.
        QSGGeometry* g = new QSGGeometry(
            QSGGeometry::defaultAttributes_TexturedPoint2D(), 4);
        g->setDrawingMode(QSGGeometry::DrawTriangleStrip);
        QSGGeometry::TexturedPoint2D* v = g->vertexDataAsTexturedPoint2D();
        v[0].set(0, 0, 0, 0);
        v[1].set(1, 0, 1, 0);
        v[2].set(0, 1, 0, 1);
        v[3].set(1, 1, 1, 1);
        setGeometry(g);
        setMaterial(&material_);
        setFlag(QSGNode::OwnsGeometry, true);
    }

    void setTexture(QSGTexture* tex) {
        tex->setFiltering(QSGTexture::Linear);
        tex->setHorizontalWrapMode(QSGTexture::ClampToEdge);
        tex->setVerticalWrapMode(QSGTexture::ClampToEdge);
        // Delete the old texture to avoid GPU memory leak.
        QSGTexture* old = material_.texture();
        material_.setTexture(tex);
        markDirty(DirtyMaterial);
        delete old;
    }

    QSGTextureMaterial material_;
};

PreviewSurface::PreviewSurface(QQuickItem* parent)
    : QQuickItem(parent) {
    setFlag(QQuickItem::ItemHasContents, true);
}

PreviewSurface::~PreviewSurface() = default;

void PreviewSurface::setFrame(int width, int height,
                              const QByteArray& rgba,
                              quintptr gpuHandle) {
    if (width <= 0 || height <= 0) return;
    {
        std::lock_guard<std::mutex> lk(mutex_);
        pending_.width = width;
        pending_.height = height;
        if (gpuHandle == 0) {
            // Normal RGBA path.
            pending_.rgba.assign(reinterpret_cast<const uint8_t*>(rgba.constData()),
                                 reinterpret_cast<const uint8_t*>(rgba.constData()) + rgba.size());
            pending_.gpuHandle = 0;
        } else {
            // Hardware-accelerated path: GPU texture handle provided.
            pending_.rgba.clear();
            pending_.gpuHandle = gpuHandle;
        }
    }
    if (!hasFrame_) {
        hasFrame_ = true;
        emit hasFrameChanged(true);
    }
    update(); // schedule a repaint -> updatePaintNode on render thread
}

QSGNode* PreviewSurface::updatePaintNode(QSGNode* oldNode,
                                         UpdatePaintNodeData* /*data*/) {
    auto* node = static_cast<TextureNode*>(oldNode);
    if (!node)
        node = new TextureNode();

    // Pull the latest pending frame.
    std::vector<uint8_t> pixels;
    quintptr gpuHandle = 0;
    int w = 0, h = 0;
    {
        std::lock_guard<std::mutex> lk(mutex_);
        pixels.swap(pending_.rgba);
        gpuHandle = pending_.gpuHandle;
        w = pending_.width;
        h = pending_.height;
        pending_.width = pending_.height = 0;
        pending_.gpuHandle = 0;
    }

    if (w <= 0 || h <= 0) {
        return node;
    }

    if (gpuHandle != 0) {
        // Hardware-accelerated path: use the provided GPU texture handle
        // directly. The handle is assumed to be a GLuint created externally
        // by the hardware decoder. We create a QSGTexture from it.
        QOpenGLFunctions glFuncs;
        initializeOpenGLFunctions();
        GLuint texId = static_cast<GLuint>(gpuHandle);

        // Create a texture wrapper that reuses the existing GL texture.
        QSGTexture* qsgTex = window()->createTextureFromId(texId, QSize(w, h));
        if (qsgTex) {
            node->setTexture(qsgTex);
            texW_ = w;
            texH_ = h;
        }
        return node;
    }

    // Standard software decode path: upload RGBA to a QSG texture.
    if (!pixels.empty()) {
        QImage img(w, h, QImage::Format_RGBA8888);
        std::memcpy(img.bits(), pixels.data(), pixels.size());

        // Apply real-time effects if FxController is connected.
        if (fxController_) {
            fxController_->applyEffectsToImage(img);
        }

        // Upload the (possibly effect-processed) image as a QSG texture.
        QSGTexture* qsgTex = window()->createTextureFromImage(img);
        if (qsgTex) {
            node->setTexture(qsgTex);
            texW_ = w;
            texH_ = h;
        }
    }

    return node;
}

} // namespace ghita::render
