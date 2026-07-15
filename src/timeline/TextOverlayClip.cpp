// src/timeline/TextOverlayClip.cpp
#include "TextOverlayClip.h"
#include <QStringList>
#include <QFontDatabase>
#include <QFont>
#include <QFontMetrics>
#include <QDir>
#include <QFileInfo>

namespace ghita::timeline {

// Resolve a font family name to an actual font file path. Qt 6.7's
// QFontDatabase has no fontFilePath(); on Windows fonts live in
// C:/Windows/Fonts, so we match by family name prefix.
static QString resolveFontPath(const QString& family) {
    const QString fontsDir = "C:/Windows/Fonts";
    QDir dir(fontsDir);
    if (!dir.exists()) return {};

    const QString fam = family.toLower();
    const QStringList entries =
        dir.entryList(QStringList() << "*.ttf" << "*.otf" << "*.ttc", QDir::Files);
    for (const QString& entry : entries) {
        const QString base = QFileInfo(entry).baseName().toLower();
        // Match e.g. "arial" against "arial" / "arialbd" (bold) / "ariali" (italic)
        if (base == fam || base.startsWith(fam)) {
            return fontsDir + "/" + entry;
        }
    }
    return {};
}

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

    // Resolve font file path (Qt 6.7 has no QFontDatabase::fontFilePath).
    QString fontPath = resolveFontPath(fontFamily);
    // Fallback to a default system font if the requested font is not found.
    if (fontPath.isEmpty()) {
        fontPath = resolveFontPath("Arial");
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