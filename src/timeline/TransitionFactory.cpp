// src/timeline/TransitionFactory.cpp
#include "Transition.h"
#include "FadeTransition.h"
#include "IrisWipeTransition.h"
#include "DirectionalWipeTransition.h"
#include "BlurDissolveTransition.h"
#include "ZoomDissolveTransition.h"

#include <QVector>
#include <QString>
#include <QVariantMap>
#include <memory>

namespace ghita::timeline {

std::unique_ptr<TransitionEffect> createTransitionEffect(const QString& type,
                                                          const QVariantMap& params) {
    if (type == "fades") {
        auto effect = std::make_unique<FadeTransition>();
        return effect;
    }
    if (type == "iriswipe") {
        auto effect = std::make_unique<IrisWipeTransition>();
        if (params.contains("centerX"))
            effect->setCenter(params["centerX"].toDouble(),
                              params.value("centerY", 0.5).toDouble());
        if (params.contains("direction"))
            effect->setDirection(params["direction"].toInt());
        return effect;
    }
    if (type == "directionalwipe") {
        auto effect = std::make_unique<DirectionalWipeTransition>();
        if (params.contains("direction"))
            effect->setDirection(params["direction"].toInt());
        if (params.contains("softness"))
            effect->setSoftness(params["softness"].toInt());
        return effect;
    }
    if (type == "blurdissolve") {
        auto effect = std::make_unique<BlurDissolveTransition>();
        if (params.contains("maxBlur"))
            effect->setMaxBlur(params["maxBlur"].toInt());
        if (params.contains("curve"))
            effect->setCurve(params["curve"].toInt());
        return effect;
    }
    if (type == "zoomdissolve") {
        auto effect = std::make_unique<ZoomDissolveTransition>();
        if (params.contains("intensity"))
            effect->setIntensity(params["intensity"].toDouble());
        if (params.contains("rotation"))
            effect->setRotation(params["rotation"].toInt());
        return effect;
    }
    // Default to crossfade (same as fades).
    return std::make_unique<FadeTransition>();
}

QVector<QString> supportedTransitionTypes() {
    return {
        "crossfade",
        "fades",
        "iriswipe",
        "directionalwipe",
        "blurdissolve",
        "zoomdissolve",
    };
}

QString transitionLabel(const QString& type) {
    if (type == "crossfade") return "Crossfade";
    if (type == "fades") return "Fade";
    if (type == "iriswipe") return "Iris Wipe";
    if (type == "directionalwipe") return "Directional Wipe";
    if (type == "blurdissolve") return "Blur Dissolve";
    if (type == "zoomdissolve") return "Zoom Dissolve";
    return type;
}

QString transitionIcon(const QString& type) {
    if (type == "crossfade") return "\u2194\uFE0F";
    if (type == "fades") return "\u25C6\uFE0F";
    if (type == "iriswipe") return "\u25CF\uFE0F";
    if (type == "directionalwipe") return "\u25B6\uFE0F";
    if (type == "blurdissolve") return "\u25C7\uFE0F";
    if (type == "zoomdissolve") return "\u2295\uFE0F";
    return "\u2795";
}

} // namespace ghita::timeline
