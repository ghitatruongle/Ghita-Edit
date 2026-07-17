#pragma once

#include <QQuickItem>
#include <QOpenGLFunctions>
#include <QOpenGLTexture>

#include <mutex>
#include <vector>

namespace ghita::fx {
class FxController;
}

namespace ghita::engine {
enum class HWBackend;
}

namespace ghita::render {

// PreviewSurface: a QQuickItem that renders the latest decoded video frame
// as an OpenGL texture using Qt's scene graph (QSG). The MediaEngine pushes
// RGBA pixels via setFrame(); the QSG node uploads them on the render thread.
//
// When hardware acceleration is active, setFrame() may also receive a GPU
// texture handle (gpuHandle) which bypasses the RGBA upload entirely,
// rendering the hardware texture directly.
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
    // When gpuHandle > 0, it indicates a pre-existing GPU texture to render
    // directly (hardware-accelerated path), bypassing the RGBA upload.
    Q_INVOKABLE void setFrame(int width, int height,
                              const QByteArray& rgba,
                              quintptr gpuHandle = 0);

    // Expose the current backend status for the UI indicator.
    Q_INVOKABLE void setBackendStatus(
        const QString& backendLabel) { backendLabel_ = backendLabel; }
    QString backendStatus() const { return backendLabel_; }

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
        quintptr gpuHandle = 0;  // non-zero = GPU texture handle
    };
    Pending pending_;
    std::mutex mutex_;
    bool hasFrame_ = false;
    int texW_ = 0, texH_ = 0;

    // Pointer to the FxController for real-time effect application.
    ghita::fx::FxController* fxController_ = nullptr;

    // Human-readable backend status label (e.g. "HW: NVDEC" or "SW: CPU").
    QString backendLabel_;
};

} // namespace ghita::render
