#pragma once

#include <QQuickItem>
#include <QOpenGLFunctions>
#include <QOpenGLTexture>

#include <mutex>
#include <vector>

namespace ghita::fx {
class FxController;
}

namespace ghita::render {

// PreviewSurface: a QQuickItem that renders the latest decoded video frame
// as an OpenGL texture using Qt's scene graph (QSG). The MediaEngine pushes
// RGBA pixels via setFrame(); the QSG node uploads them on the render thread.
//
// M0: texture upload happens on the GUI render thread (QSG), which is the
// correct place for GL work. Decoding itself runs on a worker thread.
//
// M4.5: Real-time effect preview -- effects from FxController are applied to
// the RGBA frame before texture upload, so the user sees live feedback.
class PreviewSurface : public QQuickItem, protected QOpenGLFunctions {
    Q_OBJECT
    Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY hasFrameChanged)

public:
    PreviewSurface(QQuickItem* parent = nullptr);
    ~PreviewSurface() override;

    bool hasFrame() const { return hasFrame_; }

    // Thread-safe: store the latest RGBA frame to be uploaded on next paint.
    Q_INVOKABLE void setFrame(int width, int height,
                              const QByteArray& rgba);

    // Set a pointer to the FxController so effects can be applied during paint.
    // Call this from QML or Application before the first frame arrives.
    Q_INVOKABLE void setFxController(ghita::fx::FxController* fx) { fxController_ = fx; }

signals:
    void hasFrameChanged(bool);

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode,
                             UpdatePaintNodeData* data) override;

private:
    struct Pending {
        int width = 0, height = 0;
        std::vector<uint8_t> rgba;
    };
    Pending pending_;
    std::mutex mutex_;
    bool hasFrame_ = false;
    int texW_ = 0, texH_ = 0;

    // Pointer to the FxController for real-time effect application.
    ghita::fx::FxController* fxController_ = nullptr;
};

} // namespace ghita::render
