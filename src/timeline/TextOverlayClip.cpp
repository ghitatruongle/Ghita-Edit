// src/timeline/TextOverlayClip.cpp
#include "TextOverlayClip.h"
#include <QStringList>
#include <QFontDatabase>
#include <QFont>

namespace ghita::timeline {

QString TextOverlayClip::buildFilterString(int frameWidth, int frameHeight) const {
    // Approximate text width using font metrics for alignment calculations
    QFont font(fontFamily.isEmpty() ? "Arial" : fontFamily, fontSize);
    QFontMetrics fm(font);
    int textWidth = fm.horizontalAdvance(text);

    // Calculate x position based on alignment
    int x;
    switch (alignment) {
        case Alignment::Left:
            x = static_cast<int>(posX);
            break;
        case Alignment::Center:
            x = static_cast<int>(frameWidth / 2 + posX - textWidth / 2);
            break;
        case Alignment::Right:
            x = static_cast<int>(frameWidth + posX - textWidth);
            break;
    }

    int y = static_cast<int>(frameHeight / 2 + posY);

    // Resolve font file path using QFontDatabase
    QString fontPath;
    QFontDatabase fontDb;
    QStringList families = fontDb.families();
    if (families.contains(fontFamily)) {
        QString resolvedFamily = fontFamily;
        QStringList styles = fontDb.styles(resolvedFamily);
        if (!styles.isEmpty()) {
            fontPath = fontDb.fontFilePath(resolvedFamily, styles.first());
        }
    }
    // Fallback to a default system font if the requested font is not found
    if (fontPath.isEmpty()) {
        QFont defaultFont("Arial", fontSize);
        fontPath = QFontDatabase().fontFilePath(defaultFont.family(), "Regular");
    }

    // Escape special characters for FFmpeg
    QString escapedText = text;
    escapedText.replace("'", "'\\''");
    escapedText.replace(":", "\\:");
    escapedText.replace("%", "%%");

    // Build filter string
    QString filter = QString(
        "drawtext=text='%1':"
        "fontsize=%2:"
        "fontcolor=%3:"
        "x=%4:y=%5:"
        "fontfile='%6'"
    ).arg(escapedText)
     .arg(fontSize)
     .arg(color.name())
     .arg(x)
     .arg(y)
     .arg(fontPath);

    return filter;
}

} // namespace ghita::timeline