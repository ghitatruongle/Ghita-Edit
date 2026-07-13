// src/timeline/TextOverlayClip.h
#pragma once

#include <QString>
#include <QColor>
#include "Clip.h"

namespace ghita::timeline {

struct TextOverlayClip {
    enum class Alignment { Left, Center, Right };
    enum class Animation { None, FadeIn, FadeOut, Typewriter, SlideUp };

    QString text;
    QString fontFamily = "Arial";
    int fontSize = 48;
    QColor color = Qt::white;
    Alignment alignment = Alignment::Center;

    // Position (relative to frame center, in pixels)
    float posX = 0.0f;
    float posY = 0.0f;

    // Animation
    Animation animation = Animation::None;
    int animationDurationMs = 500;

    // Build FFmpeg drawtext filter string
    QString buildFilterString(int frameWidth, int frameHeight) const;
};

} // namespace ghita::timeline