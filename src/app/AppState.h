#pragma once

#include <QObject>
#include <QString>

namespace ghita::app {

// AppState: small UI-shared state that doesn't belong in the timeline model.
// Holds the currently selected clip (id + kind) so the preview overlay layer,
// the right-hand text/sticker editor, and the keyframe lane stay in sync.
class AppState : public QObject {
    Q_OBJECT

    Q_PROPERTY(int selectedClipId READ selectedClipId WRITE setSelectedClipId
               NOTIFY selectedClipIdChanged)
    Q_PROPERTY(int selectedClipKind READ selectedClipKind WRITE setSelectedClipKind
               NOTIFY selectedClipKindChanged)
    Q_PROPERTY(bool hasCopiedClip READ hasCopiedClip WRITE setHasCopiedClip
               NOTIFY hasCopiedClipChanged)
    Q_PROPERTY(qint64 copiedClipId READ copiedClipId WRITE setCopiedClipId
               NOTIFY copiedClipIdChanged)

public:
    explicit AppState(QObject* parent = nullptr) : QObject(parent) {}

    int selectedClipId() const { return id_; }
    void setSelectedClipId(int v) {
        if (v == id_) return;
        id_ = v;
        emit selectedClipIdChanged();
    }

    int selectedClipKind() const { return kind_; }
    void setSelectedClipKind(int v) {
        if (v == kind_) return;
        kind_ = v;
        emit selectedClipKindChanged();
    }

    bool hasCopiedClip() const { return hasCopied_; }
    void setHasCopiedClip(bool v) {
        if (v == hasCopied_) return;
        hasCopied_ = v;
        emit hasCopiedClipChanged();
    }

    qint64 copiedClipId() const { return copiedId_; }
    void setCopiedClipId(qint64 v) {
        if (v == copiedId_) return;
        copiedId_ = v;
        emit copiedClipIdChanged();
    }

signals:
    void selectedClipIdChanged();
    void selectedClipKindChanged();
    void hasCopiedClipChanged();
    void copiedClipIdChanged();

private:
    int id_ = -1;
    int kind_ = -1;
    bool hasCopied_ = false;
    qint64 copiedId_ = -1;
};

} // namespace ghita::app
