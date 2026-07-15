#pragma once

#include <QObject>

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

signals:
    void selectedClipIdChanged();
    void selectedClipKindChanged();

private:
    int id_ = -1;
    int kind_ = -1;
};

} // namespace ghita::app
