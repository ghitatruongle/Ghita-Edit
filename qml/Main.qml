// Main.qml — CapCut-style three-column layout with timeline
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import GhitaTheme 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 1280
    height: 800
    title: "Ghita Edit"
    color: Theme.effectiveBg
    flags: Qt.FramelessWindowHint  // Custom Windows-style chrome
    minimumWidth: 960
    minimumHeight: 540

    // Initialize Theme scale from the primary screen's device pixel ratio.
    Component.onCompleted: {
        Theme.scale = Screen.devicePixelRatio
    }

    property bool playing: mediaEngine ? mediaEngine.playing : false
    property int exportProgress: 0
    property string exportStatus: ""
    property string rightTab: "adjust"

    // Helper to format ms -> HH:MM:SS
    function fmtTime(ms) {
        var totalSec = Math.floor(ms / 1000)
        var h = Math.floor(totalSec / 3600)
        var m = Math.floor((totalSec % 3600) / 60)
        var s = totalSec % 60
        return (h < 10 ? "0" : "") + h + ":" +
               (m < 10 ? "0" : "") + m + ":" +
               (s < 10 ? "0" : "") + s
    }

    function startExport(path) {
        if (timeline.rowCount() === 0) return
        exportProgress = 0
        exportStatus = "Exporting…"
        exporter.exportAsync(timeline, path)
    }

    function clipIdAtPlayhead() {
        if (!timeline || !mediaEngine) return -1
        var pos = mediaEngine.positionMs
        for (var i = 0; i < timeline.rowCount(); i++) {
            var start = timeline.clipStartMs(i)
            var end = timeline.clipEndMs(i)
            if (pos >= start && pos < end) {
                return timeline.clipId(i)
            }
        }
        return -1
    }

    // Apply a color-grading filter preset (sets FxController properties).
    function applyFilter(name) {
        if (name === "None") { fx.reset(); return }
        if (name === "Vivid")    { fx.saturation = 1.3; fx.contrast = 1.1; fx.temperature = 10; fx.tint = 0 }
        if (name === "Cinematic"){ fx.contrast = 1.15; fx.saturation = 0.9; fx.temperature = -10; fx.tint = 5; fx.brightness = -0.02 }
        if (name === "B&W")      { fx.saturation = 0.0; fx.contrast = 1.2; fx.temperature = 0; fx.tint = 0 }
        if (name === "Warm")     { fx.temperature = 45; fx.tint = 12; fx.saturation = 1.05 }
        if (name === "Cool")     { fx.temperature = -45; fx.tint = -12; fx.saturation = 1.05 }
        if (name === "Fade")     { fx.brightness = 0.05; fx.contrast = 0.95; fx.saturation = 0.95 }
        if (name === "Vintage")  { fx.temperature = 20; fx.tint = -10; fx.saturation = 0.85; fx.contrast = 1.1 }
        if (name === "Clean")    { fx.saturation = 1.1; fx.contrast = 1.05; fx.temperature = 0; fx.tint = 0 }
        if (name === "Dramatic") { fx.contrast = 1.4; fx.saturation = 0.7; fx.brightness = -0.05; fx.temperature = -5 }
        if (name === "Moody")    { fx.contrast = 1.1; fx.saturation = 0.8; fx.brightness = -0.08; fx.temperature = -20; fx.tint = -10 }
        if (name === "Sunset")   { fx.temperature = 60; fx.tint = 25; fx.saturation = 1.2; fx.brightness = 0.03 }
        if (name === "Golden")   { fx.temperature = 50; fx.tint = 15; fx.saturation = 1.15; fx.contrast = 1.05 }
        if (name === "Ocean")    { fx.temperature = -50; fx.tint = -20; fx.saturation = 1.1; fx.brightness = 0.02 }
        if (name === "Noir")     { fx.saturation = 0.0; fx.contrast = 1.5; fx.brightness = -0.05; fx.temperature = 0 }
        if (name === "Soft")     { fx.contrast = 0.85; fx.saturation = 0.9; fx.brightness = 0.04; fx.temperature = 5 }
        if (name === "Retro")    { fx.temperature = 30; fx.tint = -15; fx.saturation = 0.8; fx.contrast = 1.05; fx.brightness = 0.02 }
        if (name === "Dreamy")   { fx.saturation = 1.15; fx.brightness = 0.06; fx.contrast = 0.9; fx.temperature = 10; fx.tint = 5 }
        if (name === "High-Key") { fx.brightness = 0.1; fx.contrast = 0.9; fx.saturation = 0.95; fx.temperature = 5 }
        if (name === "Low-Key")  { fx.brightness = -0.1; fx.contrast = 1.2; fx.saturation = 0.9; fx.temperature = -10 }
        if (name === "Push")     { fx.saturation = 1.4; fx.contrast = 1.1; fx.temperature = 10; fx.brightness = 0.02 }
        if (name === "Pastel")   { fx.saturation = 0.7; fx.brightness = 0.08; fx.contrast = 0.85; fx.temperature = 10 }
        if (name === "Sepia")    { fx.temperature = 35; fx.tint = 10; fx.saturation = 0.6; fx.contrast = 1.05; fx.brightness = 0.02 }
        if (name === "Frost")    { fx.temperature = -60; fx.tint = 10; fx.saturation = 0.85; fx.brightness = 0.05 }
        if (name === "Ember")    { fx.temperature = 70; fx.tint = 30; fx.saturation = 1.3; fx.contrast = 1.1 }
        if (name === "Lavender") { fx.temperature = -20; fx.tint = 25; fx.saturation = 0.9; fx.brightness = 0.04 }
        if (name === "Teal")     { fx.temperature = -40; fx.tint = -30; fx.saturation = 1.1; fx.contrast = 1.15 }
        if (name === "Orange")   { fx.temperature = 65; fx.tint = 35; fx.saturation = 1.25; fx.contrast = 1.1 }
        if (name === "Mono")     { fx.saturation = 0.0; fx.contrast = 1.0; fx.brightness = 0.0 }
        if (name === "Cross")    { fx.temperature = 15; fx.tint = 20; fx.saturation = 1.3; fx.contrast = 1.2 }
        if (name === "Cross-Process") { fx.temperature = 20; fx.tint = -15; fx.saturation = 1.2; fx.contrast = 1.15; fx.brightness = -0.03 }
        if (name === "HDR")      { fx.contrast = 1.3; fx.saturation = 1.2; fx.highlight = 0.2; fx.shadow = 0.15; fx.brightness = 0.02 }
        if (name === "Film-Print") { fx.temperature = 15; fx.tint = -5; fx.saturation = 0.9; fx.contrast = 1.05; fx.brightness = 0.01 }
        if (name === "Pro-Misaka") { fx.temperature = -10; fx.tint = 10; fx.saturation = 0.95; fx.contrast = 1.1; fx.brightness = -0.02 }
        if (name === "Cyberpunk") { fx.temperature = -30; fx.tint = 30; fx.saturation = 1.4; fx.contrast = 1.2; fx.brightness = -0.05 }
        if (name === "Aurora")   { fx.temperature = -40; fx.tint = 20; fx.saturation = 1.3; fx.contrast = 1.1; fx.hueShift = 30 }
        if (name === "Neon")     { fx.saturation = 1.5; fx.contrast = 1.2; fx.temperature = 0; fx.tint = 15; fx.hueShift = 15 }
        if (name === "Duotone")  { fx.saturation = 0.3; fx.temperature = 40; fx.tint = 20; fx.contrast = 1.3; fx.brightness = -0.05 }
        if (name === "Infrared") { fx.temperature = -80; fx.tint = 40; fx.saturation = 0.7; fx.contrast = 1.2; fx.hueShift = 90 }
        if (name === "Polaroid") { fx.temperature = 25; fx.tint = 5; fx.saturation = 0.8; fx.contrast = 0.95; fx.brightness = 0.06 }
        if (name === "VHS")      { fx.temperature = 10; fx.tint = -10; fx.saturation = 0.75; fx.contrast = 1.1; fx.brightness = 0.03 }
        if (name === "Grain")    { fx.saturation = 0.85; fx.contrast = 1.15; fx.brightness = -0.02; fx.temperature = 15 }
        if (name === "Matte")    { fx.brightness = 0.05; fx.contrast = 0.8; fx.saturation = 0.9; fx.shadow = 0.1 }
        if (name === "Lomo")     { fx.saturation = 1.3; fx.contrast = 1.25; fx.temperature = 20; fx.brightness = -0.03 }
        if (name === "Instagram"){ fx.temperature = 15; fx.tint = 5; fx.saturation = 1.1; fx.contrast = 1.1; fx.brightness = 0.02 }
        if (name === "Tungsten") { fx.temperature = -55; fx.tint = -15; fx.saturation = 1.0; fx.contrast = 1.1 }
        if (name === "Fluorescent") { fx.temperature = -30; fx.tint = 25; fx.saturation = 1.05; fx.contrast = 1.05 }
        if (name === "Daylight")  { fx.temperature = 0; fx.tint = 0; fx.saturation = 1.05; fx.contrast = 1.02 }
        if (name === "Cloudy")   { fx.temperature = 10; fx.tint = 5; fx.saturation = 1.0; fx.brightness = 0.03 }
        if (name === "Shade")    { fx.temperature = -25; fx.tint = -10; fx.saturation = 1.1; fx.contrast = 1.05 }
        if (name === "Black-Warm")  { fx.saturation = 0.0; fx.temperature = 30; fx.contrast = 1.3; fx.brightness = -0.05 }
        if (name === "Black-Cool")   { fx.saturation = 0.0; fx.temperature = -30; fx.contrast = 1.3; fx.brightness = -0.05 }
        if (name === "Split-Tone") { fx.temperature = 40; fx.tint = -20; fx.saturation = 1.1; fx.contrast = 1.1; fx.hueShift = -45 }
        if (name === "Vintage-1970") { fx.temperature = 25; fx.tint = -8; fx.saturation = 0.7; fx.contrast = 1.0; fx.brightness = 0.04 }
        if (name === "Vintage-1980") { fx.temperature = 15; fx.tint = 10; fx.saturation = 1.1; fx.contrast = 1.15; fx.brightness = 0.01 }
        if (name === "Vintage-1990") { fx.temperature = -5; fx.tint = 5; fx.saturation = 1.0; fx.contrast = 1.05; fx.brightness = 0.02 }
        if (name === "Kodak-Portra") { fx.temperature = 10; fx.tint = 8; fx.saturation = 1.05; fx.contrast = 1.0; fx.brightness = 0.01 }
        if (name === "Fuji-Pro")    { fx.temperature = -5; fx.tint = -5; fx.saturation = 1.1; fx.contrast = 1.05; fx.brightness = 0.0 }
        if (name === "Leica")       { fx.temperature = 5; fx.tint = 0; fx.saturation = 1.15; fx.contrast = 1.1; fx.brightness = 0.01 }
        if (name === "Arri")        { fx.temperature = 0; fx.tint = 0; fx.saturation = 1.0; fx.contrast = 1.0; fx.brightness = 0.0 }
        if (name === "DaVinci")     { fx.temperature = -8; fx.tint = 3; fx.saturation = 0.95; fx.contrast = 1.1; fx.highlight = 0.1; fx.shadow = 0.05 }
        if (name === "Log-Grade")   { fx.temperature = 0; fx.tint = 0; fx.saturation = 1.2; fx.contrast = 1.3; fx.highlight = -0.1; fx.shadow = 0.15; fx.brightness = 0.05 }
        if (name === "Rec709")     { fx.saturation = 1.0; fx.contrast = 1.0; fx.brightness = 0.0; fx.temperature = 0; fx.tint = 0 }
        if (name === "ACES")       { fx.saturation = 1.05; fx.contrast = 1.05; fx.temperature = -3; fx.tint = 2; fx.highlight = 0.05; fx.shadow = 0.05 }
        toast.show("Filter applied: " + name, "info")
    }

    // ---- Filter Model & Helpers ----
    // Filter categories for browsing.
    readonly property var filterCategories: ["All", "B&W", "Color", "Mood", "Creative", "Film", "Camera", "Vintage", "Season"]

    // Color swatches for each filter preset.
    readonly property var filterSwatches: ({
        "None":       "#888888", "Vivid":      "#ff6b6b", "Cinematic":  "#5b8def",
        "B&W":        "#cccccc", "Warm":       "#ffa94d", "Cool":       "#74c0fc",
        "Fade":       "#e8d5b7", "Vintage":    "#d8b48c", "Clean":      "#69db7c",
        "Dramatic":   "#c0392b", "Moody":      "#2c3e50", "Sunset":     "#e67e22",
        "Golden":     "#f1c40f", "Ocean":      "#2980b9", "Noir":       "#1a1a1a",
        "Soft":       "#aed6f1", "Retro":      "#e0a96d", "Dreamy":     "#d7bde2",
        "High-Key":   "#f9e79f", "Low-Key":    "#2c3e50", "Push":       "#ff9ff3",
        "Pastel":     "#f8c291", "Sepia":      "#c0813d", "Frost":      "#85c1e9",
        "Ember":      "#e74c3c", "Lavender":   "#bb8fce", "Teal":       "#1abc9c",
        "Orange":     "#e67e22", "Mono":       "#555555", "Cross":      "#e74c3c",
        "Cross-Process": "#e67e22", "HDR":      "#3498db", "Film-Print": "#d4a574",
        "Pro-Misaka": "#5dade2", "Cyberpunk":  "#8e44ad", "Aurora":     "#2ecc71",
        "Neon":       "#00ffff", "Duotone":    "#f39c12", "Infrared":   "#e74c3c",
        "Polaroid":   "#f5deb3", "VHS":        "#95a5a6", "Grain":      "#7f8c8d",
        "Matte":      "#bdc3c7", "Lomo":       "#d35400", "Instagram":  "#f0e68c",
        "Tungsten":   "#5b8def", "Fluorescent":"#5dade2", "Daylight":   "#f9e79f",
        "Cloudy":     "#aed6f1", "Shade":      "#3498db", "Black-Warm": "#c0813d",
        "Black-Cool": "#5b8def", "Split-Tone": "#e74c3c", "Vintage-1970": "#d4a574",
        "Vintage-1980": "#f0e68c", "Vintage-1990": "#aed6f1", "Kodak-Portra": "#f5deb3",
        "Fuji-Pro":   "#5dade2", "Leica":      "#58d68d", "Arri":       "#5b8def",
        "DaVinci":    "#5dade2", "Log-Grade":  "#3498db", "Rec709":     "#5b8def",
        "ACES":       "#58d68d"
    })

    // Build a flat model from categories.
    ListModel {
        id: filterModel

        function populate() {
            // Clear existing items.
            while (filterModel.count > 0) filterModel.remove(0)

            var allFilters = [
                { name: "None",       category: "All" },
                { name: "Vivid",      category: "All" },
                { name: "Cinematic",  category: "All" },
                { name: "B&W",        category: "All" },
                { name: "Warm",       category: "All" },
                { name: "Cool",       category: "All" },
                { name: "Fade",       category: "All" },
                { name: "Vintage",    category: "All" },
                { name: "Clean",      category: "All" },
                { name: "Dramatic",   category: "All" },
                { name: "Moody",      category: "All" },
                { name: "Sunset",     category: "All" },
                { name: "Golden",     category: "All" },
                { name: "Ocean",      category: "All" },
                { name: "Noir",       category: "All" },
                { name: "Soft",       category: "All" },
                { name: "Retro",      category: "All" },
                { name: "Dreamy",     category: "All" },
                { name: "High-Key",   category: "All" },
                { name: "Low-Key",    category: "All" },
                { name: "Push",       category: "All" },
                { name: "Pastel",     category: "All" },
                { name: "Sepia",      category: "All" },
                { name: "Frost",      category: "All" },
                { name: "Ember",      category: "All" },
                { name: "Lavender",   category: "All" },
                { name: "Teal",       category: "All" },
                { name: "Orange",     category: "All" },
                { name: "Mono",       category: "All" },
                { name: "Cross",      category: "All" },
                { name: "Cross-Process", category: "All" },
                { name: "HDR",        category: "All" },
                { name: "Film-Print", category: "All" },
                { name: "Pro-Misaka", category: "All" },
                { name: "Cyberpunk",  category: "All" },
                { name: "Aurora",     category: "All" },
                { name: "Neon",       category: "All" },
                { name: "Duotone",    category: "All" },
                { name: "Infrared",   category: "All" },
                { name: "Polaroid",   category: "All" },
                { name: "VHS",        category: "All" },
                { name: "Grain",      category: "All" },
                { name: "Matte",      category: "All" },
                { name: "Lomo",       category: "All" },
                { name: "Instagram",  category: "All" },
                { name: "Tungsten",   category: "All" },
                { name: "Fluorescent",category: "All" },
                { name: "Daylight",   category: "All" },
                { name: "Cloudy",     category: "All" },
                { name: "Shade",      category: "All" },
                { name: "Black-Warm", category: "All" },
                { name: "Black-Cool", category: "All" },
                { name: "Split-Tone", category: "All" },
                { name: "Vintage-1970", category: "All" },
                { name: "Vintage-1980", category: "All" },
                { name: "Vintage-1990", category: "All" },
                { name: "Kodak-Portra", category: "All" },
                { name: "Fuji-Pro",   category: "All" },
                { name: "Leica",      category: "All" },
                { name: "Arri",       category: "All" },
                { name: "DaVinci",    category: "All" },
                { name: "Log-Grade",  category: "All" },
                { name: "Rec709",     category: "All" },
                { name: "ACES",       category: "All" }
            ]

            // Categorize filters.
            var bwFilters = ["B&W", "Noir", "Mono", "Black-Warm", "Black-Cool"]
            var colorFilters = ["Vivid", "Warm", "Cool", "Clean", "Push", "Cross", "Cross-Process",
                               "Teal", "Orange", "Sepia", "Frost", "Ember", "Lavender", "Neon",
                               "Duotone", "Infrared", "Split-Tone", "Polaroid", "Lomo", "Instagram",
                               "Tungsten", "Fluorescent", "Daylight", "Cloudy", "Shade",
                               "Vintage-1970", "Vintage-1980", "Vintage-1990", "Kodak-Portra",
                               "Fuji-Pro", "Leica", "Arri", "DaVinci", "Log-Grade", "Rec709", "ACES"]
            var moodFilters = ["Cinematic", "Dramatic", "Moody", "Sunset", "Golden", "Ocean",
                              "Soft", "Retro", "Dreamy", "High-Key", "Low-Key", "Pastel",
                              "Fade", "Vintage", "Grain", "Matte", "HDR", "Film-Print",
                              "Pro-Misaka", "Cyberpunk", "Aurora", "VHS"]
            var creativeFilters = ["HDR", "Cross-Process", "Split-Tone", "Infrared", "Duotone",
                                  "Aurora", "Neon", "Cyberpunk", "ACES", "Log-Grade", "DaVinci"]
            var filmFilters = ["Cinematic", "Film-Print", "Vintage", "Vintage-1970", "Vintage-1980",
                              "Vintage-1990", "Kodak-Portra", "Fuji-Pro", "Leica", "Arri",
                              "DaVinci", "Log-Grade", "ACES", "Rec709", "VHS", "Grain", "Matte"]
            var cameraFilters = ["Kodak-Portra", "Fuji-Pro", "Leica", "Arri", "DaVinci",
                                "Log-Grade", "Rec709", "ACES", "Daylight", "Cloudy", "Shade",
                                "Tungsten", "Fluorescent"]
            var vintageFilters = ["Vintage", "Vintage-1970", "Vintage-1980", "Vintage-1990",
                                 "Retro", "Polaroid", "VHS", "Sepia", "Fade", "Grain"]
            var seasonFilters = ["Sunset", "Golden", "Ocean", "Frost", "Ember", "Lavender",
                                "Warm", "Cool", "Cloudy", "Shade", "Daylight"]

            for (var i = 0; i < allFilters.length; i++) {
                var fn = allFilters[i].name
                var swatch = filterSwatches[fn] || "#888888"

                // Add to "All" category.
                filterModel.append({ name: fn, swatch: swatch, category: "All" })

                // Add to specific categories if applicable.
                if (bwFilters.indexOf(fn) >= 0) filterModel.append({ name: fn, swatch: swatch, category: "B&W" })
                if (colorFilters.indexOf(fn) >= 0) filterModel.append({ name: fn, swatch: swatch, category: "Color" })
                if (moodFilters.indexOf(fn) >= 0) filterModel.append({ name: fn, swatch: swatch, category: "Mood" })
                if (creativeFilters.indexOf(fn) >= 0) filterModel.append({ name: fn, swatch: swatch, category: "Creative" })
                if (filmFilters.indexOf(fn) >= 0) filterModel.append({ name: fn, swatch: swatch, category: "Film" })
                if (cameraFilters.indexOf(fn) >= 0) filterModel.append({ name: fn, swatch: swatch, category: "Camera" })
                if (vintageFilters.indexOf(fn) >= 0) filterModel.append({ name: fn, swatch: swatch, category: "Vintage" })
                if (seasonFilters.indexOf(fn) >= 0) filterModel.append({ name: fn, swatch: swatch, category: "Season" })
            }
        }
    }

    // Saved custom filters list.
    property var savedFilters: []

    // Active filter name for highlighting.
    property string activeFilterName: ""

    // Sync activeFilterName with filterModel changes.
    Component.onCompleted: {
        filterModel.populate()
    }

    // Copy current FX values into the custom filter sliders.
    function customFilterFromFx() {
        // The sliders are already bound to fx.*, so no extra work needed.
        // Just track which preset was last applied.
    }

    // Save the current FX parameter set as a named custom filter.
    function saveCustomFilter(name) {
        // Check for duplicates.
        for (var i = 0; i < savedFilters.length; i++) {
            if (savedFilters[i] === name) {
                console.log("[Filters] Filter '" + name + "' already saved.")
                return
            }
        }
        savedFilters.push(name)
        console.log("[Filters] Saved custom filter: " + name)
    }

    // Load a saved custom filter by name (resets FX then applies stored values).
    function loadCustomFilter(name) {
        console.log("[Filters] Loading custom filter: " + name)
        // For now, reset to identity and let the user re-apply.
        // Custom filter persistence would require a JSON storage backend.
        fx.reset()
    }

    // Add a text clip at the playhead and select it.
    function addTextClipAtPlayhead(text) {
        var start = mediaEngine ? mediaEngine.positionMs : 0
        timeline.addTextClip(text, start, 3000)
        var pick = -1
        for (var i = 0; i < timeline.rowCount(); i++) {
            if (timeline.clipKind(i) >= 2 && timeline.clipStartMs(i) === start) pick = timeline.clipId(i)
        }
        if (pick >= 0 && appState) { appState.selectedClipId = pick; appState.selectedClipKind = 2 }
        root.rightTab = "text"
        toast.show("Text clip added", "success")
    }

    // Add a sticker clip at the playhead and select it.
    function addStickerAtPlayhead(path) {
        var start = mediaEngine ? mediaEngine.positionMs : 0
        timeline.addStickerClip(path, start, 3000)
        var pick = -1
        for (var i = 0; i < timeline.rowCount(); i++) {
            if (timeline.clipKind(i) === 3 && timeline.clipStartMs(i) === start) pick = timeline.clipId(i)
        }
        if (pick >= 0 && appState) { appState.selectedClipId = pick; appState.selectedClipKind = 3 }
        root.rightTab = "text"
        toast.show("Sticker clip added", "success")
    }

    // Add a PIP video clip at the playhead and select it.
    function addPipVideoClipAtPlayhead(path) {
        var start = mediaEngine ? mediaEngine.positionMs : 0
        timeline.addPipVideoClip(path, start, 5000)
        var pick = -1
        for (var i = 0; i < timeline.rowCount(); i++) {
            if (timeline.clipKind(i) === 4 && timeline.clipStartMs(i) === start) pick = timeline.clipId(i)
        }
        if (pick >= 0 && appState) {
            appState.selectedClipId = pick
            appState.selectedClipKind = 4
        }
        root.rightTab = "pip"
        toast.show("PIP video clip added", "success")
    }

    // Add a PIP image clip at the playhead and select it.
    function addPipImageClipAtPlayhead(path) {
        var start = mediaEngine ? mediaEngine.positionMs : 0
        timeline.addPipImageClip(path, start, 5000)
        var pick = -1
        for (var i = 0; i < timeline.rowCount(); i++) {
            if (timeline.clipKind(i) === 5 && timeline.clipStartMs(i) === start) pick = timeline.clipId(i)
        }
        if (pick >= 0 && appState) {
            appState.selectedClipId = pick
            appState.selectedClipKind = 5
        }
        root.rightTab = "pip"
        toast.show("PIP image clip added", "success")
    }

    // Add an audio clip at the playhead.
    // NOTE: We temporarily open the audio file in mediaEngine to read its
    // duration, then reopen the previous video. This is a workaround because
    // there is no standalone duration-reading API for audio files.
    function requestAudio(path) {
        var start = mediaEngine ? mediaEngine.positionMs : 0
        var savedPath = mediaEngine.mediaPath
        mediaEngine.open(path)
        var dur = mediaEngine.durationMs > 0 ? mediaEngine.durationMs : 8000
        if (savedPath) mediaEngine.open(savedPath)
        timeline.addClip(path, 0, dur, start, 1)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Toolbar ----
        Toolbar {
            Layout.fillWidth: true
            onOpenFile: fileDialog.open()
            onTogglePlay: playing ? mediaEngine.pause() : mediaEngine.play()
            onStop: mediaEngine.stop()
            onSplitRequested: {
                var id = clipIdAtPlayhead()
                if (id >= 0) {
                    timeline.splitClipAtPlayhead(id)
                    toast.show("Clip split", "info")
                }
            }
            onAddText: root.addTextClipAtPlayhead("Text")
            onAddSticker: stickerFileDialog.open()
            onAddPipVideo: pipVideoFileDialog.open()
            onAddPipImage: pipImageFileDialog.open()
            onExportRequested: exportDialog.open()
        }

        // ---- Main Content Area ----
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // === Left Panel: Source / Media Bin ===
            MediaBin {
                Layout.preferredWidth: 240
                Layout.fillHeight: true
                visible: true

                onMediaSelected: function(path) {
                    mediaEngine.open(path)
                }
                onMediaImportRequested: fileDialog.open()
                onStickerImportRequested: stickerFileDialog.open()
                onRequestText: function(text) { root.addTextClipAtPlayhead(text) }
                onRequestStickerImage: function(path) { root.addStickerAtPlayhead(path) }
                onRequestAudio: function(path) { root.requestAudio(path) }
                onRequestPipVideo: function(path) { pipVideoFileDialog.open() }
                onRequestPipImage: function(path) { pipImageFileDialog.open() }
            }

            // === Center: Preview Area ===
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#000000"

                Preview {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    isScrubbing: timeline ? timeline.isScrubbing : false
                }
            }

            // === Right Panel: Properties / Adjust ===
            Rectangle {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                color: Theme.panelBg
                border.color: Theme.border
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Tab bar
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        color: Theme.toolbarBg
                        border.color: Theme.borderDark
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingXs
                            anchors.rightMargin: Theme.spacingXs
                            spacing: 2

                            RightTab { text: "Adjust"; tabId: "adjust"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                            RightTab { text: "Audio"; tabId: "audio"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                            RightTab { text: "Filters"; tabId: "filters"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                            RightTab { text: "Effects"; tabId: "effects"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                            RightTab { text: "Crop"; tabId: "crop"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                            RightTab { text: "Text"; tabId: "text"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                            RightTab { text: "PIP"; tabId: "pip"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                            RightTab { text: "Transitions"; tabId: "transitions"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                            RightTab { text: "History"; tabId: "history"; activeTab: root.rightTab; onClicked: root.rightTab = tabId }
                        }
                    }

                    // Tab content
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: availableWidth
                        clip: true

                        ScrollBar.vertical: ScrollBar {
                            width: 6
                            policy: ScrollBar.AsNeeded
                            background: Rectangle { color: "transparent" }
                            contentItem: Rectangle {
                                radius: 3
                                color: Theme.border
                            }
                        }

                        ColumnLayout {
                            width: parent.width
                            spacing: Theme.spacingSm

                            // === Adjust Tab ===
                            ColumnLayout {
                                visible: root.rightTab === "adjust"
                                spacing: Theme.spacingSm
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm

                                // Basic section
                                CollapsibleSection {
                                    title: "Basic"
                                    Layout.fillWidth: true
                                    isExpanded: true

                                    CapFxSlider { label: "Brightness"; from: -1; to: 1; step: 0.01; value: fx.brightness; onChanged: fx.brightness = v }
                                    CapFxSlider { label: "Contrast"; from: 0; to: 2; step: 0.01; value: fx.contrast; onChanged: fx.contrast = v }
                                    CapFxSlider { label: "Saturation"; from: 0; to: 2; step: 0.01; value: fx.saturation; onChanged: fx.saturation = v }
                                }

                                // Color section
                                CollapsibleSection {
                                    title: "Color"
                                    Layout.fillWidth: true
                                    isExpanded: true

                                    CapFxSlider { label: "Temperature"; from: -100; to: 100; step: 1; value: fx.temperature || 0; onChanged: fx.temperature = v }
                                    CapFxSlider { label: "Tint"; from: -100; to: 100; step: 1; value: fx.tint || 0; onChanged: fx.tint = v }
                                }

                                // Light section
                                CollapsibleSection {
                                    title: "Light"
                                    Layout.fillWidth: true
                                    isExpanded: false

                                    CapFxSlider { label: "Highlight"; from: -100; to: 100; step: 1; value: fx.highlight * 100; onChanged: fx.highlight = v / 100 }
                                    CapFxSlider { label: "Shadow"; from: -100; to: 100; step: 1; value: fx.shadow * 100; onChanged: fx.shadow = v / 100 }
                                }

                                // Speed section (only for video/audio clips)
                                CollapsibleSection {
                                    title: "Speed"
                                    Layout.fillWidth: true
                                    isExpanded: false
                                    visible: appState && appState.selectedClipKind >= 0 && appState.selectedClipKind < 2

                                    // Numeric input
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingXs

                                        Label {
                                            text: "Playback Speed"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                        }
                                        Item { Layout.fillWidth: true }

                                        TextField {
                                            Layout.preferredWidth: 60
                                            Layout.preferredHeight: 24
                                            font.pixelSize: Theme.fontSizeSm
                                            color: Theme.textPrimary
                                            text: appState ? String(timeline.playbackSpeed(appState.selectedClipId)).replace(/\.?0+$/, '') + "x" : "1.0x"
                                            background: Rectangle { color: Theme.surfaceBg; radius: 3; border.color: Theme.border; border.width: 1 }
                                            onEditingFinished: {
                                                if (appState) {
                                                    var val = parseFloat(text.replace("x", ""))
                                                    if (!isNaN(val)) timeline.setPlaybackSpeed(appState.selectedClipId, val)
                                                }
                                            }
                                        }
                                    }

                                    // Slider
                                    Slider {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 20
                                        from: 0.25; to: 4.0; stepSize: 0.01
                                        value: appState ? timeline.playbackSpeed(appState.selectedClipId) : 1.0

                                        onMoved: {
                                            if (appState) timeline.setPlaybackSpeed(appState.selectedClipId, value)
                                        }

                                        // Sync value when external changes occur
                                        Connections {
                                            target: appState
                                            function onSelectedClipIdChanged() {
                                                if (appState && appState.selectedClipId > 0) {
                                                    // Value will update via the binding below
                                                }
                                            }
                                        }

                                        // Track
                                        background: Rectangle {
                                            x: slider.leftPadding
                                            y: slider.topPadding + slider.availableHeight / 2 - height / 2
                                            width: slider.availableWidth
                                            height: 3
                                            radius: 1.5
                                            color: Theme.border

                                            Rectangle {
                                                width: slider.visualPosition * parent.width
                                                height: parent.height
                                                radius: 1.5
                                                color: Theme.accent
                                            }
                                        }

                                        // Handle
                                        handle: Rectangle {
                                            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                                            y: slider.topPadding + slider.availableHeight / 2 - height / 2
                                            width: 14 * Theme.scale
                                            height: 14 * Theme.scale
                                            radius: 7
                                            color: Theme.textPrimary
                                            border.color: Qt.darker(Theme.textPrimary, 1.2)
                                            border.width: 1
                                        }
                                    }

                                    // Preset buttons
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingXs

                                        Repeater {
                                            model: [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
                                            Rectangle {
                                                width: 56 * Theme.scale; height: 24 * Theme.scale
                                                radius: Theme.radiusSmall
                                                color: btnMouse.pressed ? Theme.borderLight :
                                                       (appState && Math.abs(timeline.playbackSpeed(appState.selectedClipId) - modelData) < 0.001)
                                                           ? Theme.accent
                                                           : Theme.surfaceBg
                                                border.color: Theme.border
                                                border.width: 1

                                                Label {
                                                    anchors.centerIn: parent
                                                    text: modelData.toFixed(2).replace(/\.?0+$/, '') + "x"
                                                    color: (appState && Math.abs(timeline.playbackSpeed(appState.selectedClipId) - modelData) < 0.001)
                                                        ? Theme.bg
                                                        : Theme.textPrimary
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fontSizeXs
                                                    font.bold: true
                                                }

                                                MouseArea {
                                                    id: btnMouse
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (appState) timeline.setPlaybackSpeed(appState.selectedClipId, modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Pitch correction checkbox
                                    property bool pcCheckbox: appState ? timeline.pitchCorrection(appState.selectedClipId) : true
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSm

                                        Label {
                                            text: "Pitch Correction"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 16
                                            radius: 2
                                            border.color: pcCheckbox ? Theme.accent : Theme.border
                                            border.width: 1
                                            color: pcCheckbox ? Theme.accent : "transparent"

                                            Label {
                                                anchors.centerIn: parent
                                                text: "✓"
                                                color: Theme.textPrimary
                                                font.pixelSize: Theme.fontSizeXs
                                                visible: pcCheckbox
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (appState) timeline.setPitchCorrection(appState.selectedClipId, !pcCheckbox)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // === Audio Tab ===
                            ColumnLayout {
                                visible: root.rightTab === "audio"
                                spacing: Theme.spacingSm
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm

                                CollapsibleSection {
                                    title: "Volume"
                                    Layout.fillWidth: true
                                    isExpanded: true

                                    CapFxSlider { label: "Gain (dB)"; from: -24; to: 24; step: 0.5; value: fx.gainDb; onChanged: fx.gainDb = v }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSm

                                        Label {
                                            text: "Normalize"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSm
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 16
                                            radius: 2
                                            border.color: fx.normalize ? Theme.accent : Theme.border
                                            border.width: 1
                                            color: fx.normalize ? Theme.accent : "transparent"

                                            Label {
                                                anchors.centerIn: parent
                                                text: "✓"
                                                color: Theme.textPrimary
                                                font.pixelSize: Theme.fontSizeXs
                                                visible: fx.normalize
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: fx.normalize = !fx.normalize
                                            }
                                        }
                                    }
                                }

                                CollapsibleSection {
                                    title: "Fade"
                                    Layout.fillWidth: true
                                    isExpanded: true

                                    CapFxSlider { label: "Fade In (ms)"; from: 0; to: 5000; step: 100; value: fx.fadeInMs; onChanged: fx.fadeInMs = v }
                                    CapFxSlider { label: "Fade Out (ms)"; from: 0; to: 5000; step: 100; value: fx.fadeOutMs; onChanged: fx.fadeOutMs = v }
                                }

                                // Multi-track mixer
                                AudioMixer {
                                    id: audioMixer
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 200
                                    visible: root.rightTab === "audio"

                                    tracks: [
                                        { name: "A1", volume: 1.0, muted: false },
                                        { name: "A2", volume: 1.0, muted: false }
                                    ]

                                    onVolumeChanged: function(trackIndex, volume) {
                                        console.log("Track", trackIndex, "volume:", volume)
                                    }
                                    onTrackMuted: function(trackIndex, muted) {
                                        console.log("Track", trackIndex, "muted:", muted)
                                    }
                                }
                            }

                            // === Filters Tab ===
                            ColumnLayout {
                                visible: root.rightTab === "filters"
                                spacing: Theme.spacingSm
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm

                                // ---- Filter Categories ----
                                Label {
                                    text: "Filter Presets"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.Medium
                                    Layout.topMargin: Theme.spacingSm
                                }

                                // Category tabs
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingXs

                                    Repeater {
                                        model: filterCategories
                                        delegate: Rectangle {
                                            height: 24 * Theme.scale
                                            radius: Theme.radiusSmall
                                            color: filterCatMouse.pressed ? Theme.borderLight :
                                                  (filtersView.currentCategory === modelData ? Theme.accent : Theme.surfaceBg)
                                            border.color: filtersView.currentCategory === modelData ? Theme.accent : Theme.border
                                            border.width: 1

                                            Label {
                                                anchors.centerIn: parent
                                                text: modelData
                                                color: filtersView.currentCategory === modelData ? Theme.bg : Theme.textPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                                font.bold: filtersView.currentCategory === modelData
                                            }

                                            MouseArea {
                                                id: filterCatMouse
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: filtersView.currentCategory = modelData
                                            }
                                        }
                                    }
                                }

                                // Filter grid
                                GridView {
                                    id: filtersView
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 140 * Theme.scale
                                    cellWidth: (filtersView.width) / 3
                                    cellHeight: 50 * Theme.scale
                                    clip: true
                                    property string currentCategory: "All"
                                    property string activeFilter: ""

                                    model: filterModel

                                    delegate: Rectangle {
                                        width: filtersView.cellWidth - 4
                                        height: filtersView.cellHeight - 4
                                        radius: Theme.radiusSmall
                                        visible: filtersView.currentCategory === "All" || modelData.category === filtersView.currentCategory
                                        color: fMouse.pressed ? Theme.borderLight :
                                              (filtersView.activeFilter === modelData.name ? Theme.accent : Theme.surfaceBg)
                                        border.color: filtersView.activeFilter === modelData.name ? Theme.accent : Theme.border
                                        border.width: filtersView.activeFilter === modelData.name ? 2 : 1

                                        // Color swatch
                                        Rectangle {
                                            width: 16 * Theme.scale; height: 16 * Theme.scale; radius: 8 * Theme.scale
                                            anchors.top: parent.top; anchors.topMargin: 5 * Theme.scale
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            color: modelData.swatch
                                        }

                                        Label {
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 5
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.name
                                            color: filtersView.activeFilter === modelData.name ? Theme.bg : Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                            font.bold: filtersView.activeFilter === modelData.name
                                        }

                                        MouseArea {
                                            id: fMouse
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                filtersView.activeFilter = modelData.name
                                                root.applyFilter(modelData.name)
                                                customFilterFromFx()
                                            }
                                        }
                                    }
                                }

                                // ---- Custom Filter Controls ----
                                CollapsibleSection {
                                    title: "Custom Filter"
                                    Layout.fillWidth: true
                                    isExpanded: true

                                    // Dry-wet / intensity slider
                                    CapFxSlider {
                                        label: "Intensity"
                                        from: 0; to: 100; step: 1
                                        value: fx.dryWet * 100
                                        onChanged: fx.dryWet = v / 100
                                    }

                                    // Individual parameter sliders
                                    CapFxSlider { label: "Brightness"; from: -1; to: 1; step: 0.01; value: fx.brightness; onChanged: fx.brightness = v }
                                    CapFxSlider { label: "Contrast"; from: 0; to: 2; step: 0.01; value: fx.contrast; onChanged: fx.contrast = v }
                                    CapFxSlider { label: "Saturation"; from: 0; to: 2; step: 0.01; value: fx.saturation; onChanged: fx.saturation = v }
                                    CapFxSlider { label: "Temperature"; from: -100; to: 100; step: 1; value: fx.temperature || 0; onChanged: fx.temperature = v }
                                    CapFxSlider { label: "Tint"; from: -100; to: 100; step: 1; value: fx.tint || 0; onChanged: fx.tint = v }
                                    CapFxSlider { label: "Hue Shift"; from: -180; to: 180; step: 1; value: fx.hueShift || 0; onChanged: fx.hueShift = v }
                                    CapFxSlider { label: "Highlights"; from: -100; to: 100; step: 1; value: fx.highlight * 100; onChanged: fx.highlight = v / 100 }
                                    CapFxSlider { label: "Shadows"; from: -100; to: 100; step: 1; value: fx.shadow * 100; onChanged: fx.shadow = v / 100 }

                                    // Save custom filter
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingXs

                                        TextField {
                                            id: customFilterName
                                            Layout.preferredWidth: 120
                                            Layout.preferredHeight: 24
                                            font.pixelSize: Theme.fontSizeXs
                                            color: Theme.textPrimary
                                            placeholderText: "Filter name..."
                                            background: Rectangle { color: Theme.surfaceBg; radius: 3; border.color: Theme.border; border.width: 1 }
                                        }

                                        Button {
                                            text: "Save"
                                            Layout.fillWidth: true
                                            onClicked: {
                                                var name = customFilterName.text.trim()
                                                if (name === "") { name = "Custom-" + Date.now() }
                                                saveCustomFilter(name)
                                                customFilterName.text = ""
                                            }

                                            background: Rectangle {
                                                radius: Theme.radiusSmall
                                                color: parent.pressed ? Theme.borderLight : Theme.accent
                                            }

                                            contentItem: Label {
                                                text: parent.text
                                                color: Theme.bg
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                font.bold: true
                                            }
                                        }
                                    }

                                    // Quick-reset for custom filter
                                    Button {
                                        text: "Reset Filter"
                                        Layout.fillWidth: true
                                        onClicked: {
                                            fx.reset()
                                            filtersView.activeFilter = ""
                                        }

                                        background: Rectangle {
                                            radius: Theme.radiusSmall
                                            color: parent.pressed ? Theme.borderLight : "transparent"
                                            border.color: Theme.border
                                            border.width: 1
                                        }

                                        contentItem: Label {
                                            text: parent.text
                                            color: Theme.textSecondary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSm
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }

                                // ---- Saved Custom Filters ----
                                CollapsibleSection {
                                    title: "Saved Filters"
                                    Layout.fillWidth: true
                                    isExpanded: false

                                    ListView {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Math.min(savedFilters.length * 28 * Theme.scale, 100 * Theme.scale)
                                        clip: true
                                        model: savedFilters
                                        delegate: Rectangle {
                                            width: parent ? parent.width : 200
                                            height: 28 * Theme.scale
                                            color: smMouse.pressed ? Theme.borderLight : Theme.surfaceBg

                                            Label {
                                                anchors.left: parent.left
                                                anchors.leftMargin: Theme.spacingXs
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData
                                                color: Theme.textPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                            }

                                            MouseArea {
                                                id: smMouse
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: loadCustomFilter(modelData)
                                            }
                                        }
                                    }
                                }

                                Label {
                                    text: "Filters adjust color grading applied on export. Use the intensity slider to blend between original and filtered."
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    wrapMode: Text.Wrap
                                    Layout.topMargin: Theme.spacingSm
                                }
                            }

                            // === Effects Tab ===
                            ColumnLayout {
                                visible: root.rightTab === "effects"
                                spacing: Theme.spacingSm
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm

                                // ---- Preset selector ----
                                Label {
                                    text: "Effect Presets"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.Medium
                                    Layout.topMargin: Theme.spacingSm
                                }

                                // Preset dropdown
                                ComboBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    model: fx.listPresets()
                                    currentIndex: {
                                        var idx = 0
                                        for (var i = 0; i < model.length; i++) {
                                            if (model[i] === fx.currentPreset) { idx = i; break }
                                        }
                                        return idx
                                    }
                                    onActivated: function(idx) { fx.applyPreset(model[idx]) }

                                    background: Rectangle {
                                        color: Theme.surfaceBg
                                        radius: Theme.radiusSmall
                                        border.color: Theme.border
                                        border.width: 1
                                    }

                                    contentItem: Label {
                                        text: fx.currentPreset
                                        color: Theme.textPrimary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        verticalAlignment: Text.AlignVCenter
                                        leftMargin: 8
                                    }
                                }

                                // ---- Effect chain list ----
                                Label {
                                    text: "Effect Chain (" + fx.effectCount() + " effects)"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    font.weight: Font.Medium
                                    Layout.topMargin: Theme.spacingSm
                                }

                                // Effect chain Repeater
                                Repeater {
                                    model: fx.effectCount()
                                    Layout.fillWidth: true

                                    Rectangle {
                                        width: parent ? parent.width : 200
                                        height: 48 * Theme.scale
                                        color: Theme.surfaceBg
                                        radius: Theme.radiusSmall
                                        border.color: Theme.border
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: Theme.spacingXs
                                            spacing: Theme.spacingXs

                                            // Row: icon + name + toggle + intensity
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.spacingXs

                                                // Effect icon
                                                Label {
                                                    text: fx.effectIcon(index)
                                                    font.pixelSize: Theme.fontSizeMd
                                                    Layout.preferredWidth: 20
                                                }

                                                // Effect name
                                                Label {
                                                    text: fx.effectDisplayName(index)
                                                    color: fx.effectEnabled(index) ? Theme.textPrimary : Theme.textMuted
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fontSizeSm
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideMiddle
                                                }

                                                // On/Off toggle
                                                Rectangle {
                                                    Layout.preferredWidth: 36
                                                    Layout.preferredHeight: 20
                                                    radius: 10
                                                    color: fx.effectEnabled(index) ? Theme.accent : Theme.border
                                                    border.color: Theme.border
                                                    border.width: 1

                                                    Label {
                                                        anchors.centerIn: parent
                                                        text: fx.effectEnabled(index) ? "ON" : "OFF"
                                                    color: fx.effectEnabled(index) ? Theme.bg : Theme.textMuted
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: Theme.fontSizeXs
                                                        font.bold: true
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: fx.setEffectEnabled(index, !fx.effectEnabled(index))
                                                    }
                                                }
                                            }

                                            // Intensity slider
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.spacingXs

                                                Label {
                                                    text: "Intensity"
                                                    color: Theme.textMuted
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fontSizeXs
                                                }

                                                Slider {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 16
                                                    from: 0; to: 1; stepSize: 0.01
                                                    value: fx.effectIntensity(index)
                                                    onMoved: fx.setEffectIntensity(index, value)

                                                    background: Rectangle {
                                                        x: slider.leftPadding
                                                        y: slider.topPadding + slider.availableHeight / 2 - height / 2
                                                        width: slider.availableWidth
                                                        height: 3
                                                        radius: 1.5
                                                        color: Theme.border

                                                        Rectangle {
                                                            width: slider.visualPosition * parent.width
                                                            height: parent.height
                                                            radius: 1.5
                                                            color: Theme.accent
                                                        }
                                                    }

                                                    handle: Rectangle {
                                                        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                                                        y: slider.topPadding + slider.availableHeight / 2 - height / 2
                                                        width: 12
                                                        height: 12
                                                        radius: 6
                                                        color: Theme.textPrimary
                                                        border.color: Qt.darker(Theme.textPrimary, 1.2)
                                                        border.width: 1
                                                    }
                                                }

                                                Label {
                                                    text: (fx.effectIntensity(index) * 100).toFixed(0) + "%"
                                                    color: Theme.textMuted
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fontSizeXs
                                                }
                                            }
                                        }

                                        // Move buttons (up/down)
                                        RowLayout {
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 2
                                            spacing: 0

                                            Rectangle {
                                                width: 18 * Theme.scale; height: 18 * Theme.scale
                                                radius: 3
                                                color: upMouse.pressed ? Theme.borderLight : "transparent"
                                                MouseArea {
                                                    id: upMouse
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: fx.moveEffectUp(index)
                                                }
                                                Label {
                                                    anchors.centerIn: parent
                                                    text: "\u25B2"
                                                    color: Theme.textSecondary
                                                    font.pixelSize: Theme.fontSizeXs
                                                }
                                            }

                                            Rectangle {
                                                width: 18 * Theme.scale; height: 18 * Theme.scale
                                                radius: 3
                                                color: downMouse.pressed ? Theme.borderLight : "transparent"
                                                MouseArea {
                                                    id: downMouse
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: fx.moveEffectDown(index)
                                                }
                                                Label {
                                                    anchors.centerIn: parent
                                                    text: "\u25BC"
                                                    color: Theme.textSecondary
                                                    font.pixelSize: Theme.fontSizeXs
                                                }
                                            }

                                            Rectangle {
                                                width: 18 * Theme.scale; height: 18 * Theme.scale
                                                radius: 3
                                                color: remMouse.pressed ? Theme.error : "transparent"
                                                MouseArea {
                                                    id: remMouse
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: fx.removeEffect(index)
                                                }
                                                Label {
                                                    anchors.centerIn: parent
                                                    text: "\u2715"
                                                    color: Theme.textSecondary
                                                    font.pixelSize: Theme.fontSizeXs
                                                }
                                            }
                                        }
                                    }

                                    // Per-effect parameter sliders (shown below the chain when expanded)
                                    ColumnLayout {
                                        visible: fx.effectEnabled(index) && index < fx.effectCount()
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingXs

                                        // Brightness/Contrast params
                                        RowLayout {
                                            visible: fx.effectTypeName(index) === "BrightnessContrast"
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingXs

                                            Label {
                                                text: "Brightness"
                                                color: Theme.textMuted
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                            }
                                            Slider {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 14
                                                from: -1; to: 1; stepSize: 0.01
                                                value: fx.effectBrightness(index)
                                                onMoved: fx.setEffectBrightness(index, value)
                                                background: Rectangle {
                                                    x: slider.leftPadding; y: slider.topPadding + slider.availableHeight/2 - height/2
                                                    width: slider.availableWidth; height: 3; radius: 1.5; color: Theme.border
                                                    Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 1.5; color: Theme.accent }
                                                }
                                                handle: Rectangle {
                                                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                                                    y: slider.topPadding + slider.availableHeight/2 - height/2
                                                    width: 10; height: 10; radius: 5; color: Theme.textPrimary
                                                }
                                            }
                                        }

                                        RowLayout {
                                            visible: fx.effectTypeName(index) === "BrightnessContrast"
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingXs

                                            Label {
                                                text: "Contrast"
                                                color: Theme.textMuted
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                            }
                                            Slider {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 14
                                                from: 0; to: 2; stepSize: 0.01
                                                value: fx.effectContrast(index)
                                                onMoved: fx.setEffectContrast(index, value)
                                                background: Rectangle {
                                                    x: slider.leftPadding; y: slider.topPadding + slider.availableHeight/2 - height/2
                                                    width: slider.availableWidth; height: 3; radius: 1.5; color: Theme.border
                                                    Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 1.5; color: Theme.accent }
                                                }
                                                handle: Rectangle {
                                                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                                                    y: slider.topPadding + slider.availableHeight/2 - height/2
                                                    width: 10; height: 10; radius: 5; color: Theme.textPrimary
                                                }
                                            }
                                        }

                                        // Blur params
                                        RowLayout {
                                            visible: fx.effectTypeName(index) === "Blur"
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingXs

                                            Label {
                                                text: "Radius"
                                                color: Theme.textMuted
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                            }
                                            Slider {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 14
                                                from: 0; to: 20; stepSize: 0.5
                                                value: fx.effectBlurRadius(index)
                                                onMoved: fx.setEffectBlurRadius(index, value)
                                                background: Rectangle {
                                                    x: slider.leftPadding; y: slider.topPadding + slider.availableHeight/2 - height/2
                                                    width: slider.availableWidth; height: 3; radius: 1.5; color: Theme.border
                                                    Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 1.5; color: Theme.accent }
                                                }
                                                handle: Rectangle {
                                                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                                                    y: slider.topPadding + slider.availableHeight/2 - height/2
                                                    width: 10; height: 10; radius: 5; color: Theme.textPrimary
                                                }
                                            }
                                        }

                                        // Vignette params
                                        RowLayout {
                                            visible: fx.effectTypeName(index) === "Vignette"
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingXs

                                            Label {
                                                text: "Strength"
                                                color: Theme.textMuted
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                            }
                                            Slider {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 14
                                                from: 0; to: 1; stepSize: 0.01
                                                value: fx.effectVignetteStrength(index)
                                                onMoved: fx.setEffectVignetteStrength(index, value)
                                                background: Rectangle {
                                                    x: slider.leftPadding; y: slider.topPadding + slider.availableHeight/2 - height/2
                                                    width: slider.availableWidth; height: 3; radius: 1.5; color: Theme.border
                                                    Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 1.5; color: Theme.accent }
                                                }
                                                handle: Rectangle {
                                                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                                                    y: slider.topPadding + slider.availableHeight/2 - height/2
                                                    width: 10; height: 10; radius: 5; color: Theme.textPrimary
                                                }
                                            }
                                        }
                                    }
                                }

                                // ---- Add effect buttons ----
                                Label {
                                    text: "Add Effect"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    font.weight: Font.Medium
                                    Layout.topMargin: Theme.spacingSm
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingXs

                                    Rectangle {
                                        width: 80 * Theme.scale; height: 28 * Theme.scale
                                        radius: Theme.radiusSmall
                                        color: addBtnMouse.pressed ? Theme.borderLight : Theme.surfaceBg
                                        border.color: Theme.border; border.width: 1

                                        Label {
                                            anchors.centerIn: parent
                                            text: "\u2600 B/C"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                        }

                                        MouseArea {
                                            id: addBtnMouse
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: fx.addEffectByName("brightness")
                                        }
                                    }

                                    Rectangle {
                                        width: 80 * Theme.scale; height: 28 * Theme.scale
                                        radius: Theme.radiusSmall
                                        color: addBtnMouse2.pressed ? Theme.borderLight : Theme.surfaceBg
                                        border.color: Theme.border; border.width: 1

                                        Label {
                                            anchors.centerIn: parent
                                            text: "\u25CE Blur"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                        }

                                        MouseArea {
                                            id: addBtnMouse2
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: fx.addEffectByName("blur")
                                        }
                                    }

                                    Rectangle {
                                        width: 80 * Theme.scale; height: 28 * Theme.scale
                                        radius: Theme.radiusSmall
                                        color: addBtnMouse3.pressed ? Theme.borderLight : Theme.surfaceBg
                                        border.color: Theme.border; border.width: 1

                                        Label {
                                            anchors.centerIn: parent
                                            text: "\u27A4 Sharp"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                        }

                                        MouseArea {
                                            id: addBtnMouse3
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: fx.addEffectByName("sharpen")
                                        }
                                    }

                                    Rectangle {
                                        width: 80 * Theme.scale; height: 28 * Theme.scale
                                        radius: Theme.radiusSmall
                                        color: addBtnMouse4.pressed ? Theme.borderLight : Theme.surfaceBg
                                        border.color: Theme.border; border.width: 1

                                        Label {
                                            anchors.centerIn: parent
                                            text: "\u25CF Vignette"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                        }

                                        MouseArea {
                                            id: addBtnMouse4
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: fx.addEffectByName("vignette")
                                        }
                                    }
                                }

                                // ---- Reset chain ----
                                Button {
                                    text: "Reset Effects"
                                    Layout.fillWidth: true
                                    onClicked: fx.reset()

                                    background: Rectangle {
                                        radius: Theme.radiusSmall
                                        color: parent.pressed ? Theme.borderLight : "transparent"
                                        border.color: Theme.border
                                        border.width: 1
                                    }

                                    contentItem: Label {
                                        text: parent.text
                                        color: Theme.textSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                // Info text
                                Label {
                                    text: "Effects are applied in real-time to the preview and exported with the video. Reorder effects by using the arrow buttons."
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    wrapMode: Text.Wrap
                                    Layout.topMargin: Theme.spacingSm
                                }
                            }

                            // === Crop Tab ===
                            ColumnLayout {
                                visible: root.rightTab === "crop"
                                spacing: Theme.spacingSm
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm

                                Label {
                                    text: "Crop & Transform"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.Medium
                                    Layout.topMargin: Theme.spacingSm
                                }

                                // Hint when nothing selected
                                Label {
                                    visible: !(appState && appState.selectedClipId >= 0)
                                    text: "Select a clip on the timeline to crop and transform it."
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    wrapMode: Text.Wrap
                                }

                                // Crop section (works for video/audio clips too)
                                CollapsibleSection {
                                    title: "Crop"
                                    Layout.fillWidth: true
                                    isExpanded: true

                                    property real _cropVal: 0

                                    // Crop Left
                                    CapFxSlider {
                                        label: "Left"
                                        from: 0; to: 100; step: 0.5
                                        value: appState ? timeline.overlayCropLeft(appState.selectedClipId) * 100 : 0
                                        onChanged: if (appState) timeline.setOverlayCropLeft(appState.selectedClipId, v / 100)
                                    }

                                    // Crop Top
                                    CapFxSlider {
                                        label: "Top"
                                        from: 0; to: 100; step: 0.5
                                        value: appState ? timeline.overlayCropTop(appState.selectedClipId) * 100 : 0
                                        onChanged: if (appState) timeline.setOverlayCropTop(appState.selectedClipId, v / 100)
                                    }

                                    // Crop Right
                                    CapFxSlider {
                                        label: "Right"
                                        from: 0; to: 100; step: 0.5
                                        value: appState ? timeline.overlayCropRight(appState.selectedClipId) * 100 : 0
                                        onChanged: if (appState) timeline.setOverlayCropRight(appState.selectedClipId, v / 100)
                                    }

                                    // Crop Bottom
                                    CapFxSlider {
                                        label: "Bottom"
                                        from: 0; to: 100; step: 0.5
                                        value: appState ? timeline.overlayCropBottom(appState.selectedClipId) * 100 : 0
                                        onChanged: if (appState) timeline.setOverlayCropBottom(appState.selectedClipId, v / 100)
                                    }

                                    // Lock aspect ratio toggle
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSm

                                        Label {
                                            text: "Lock Aspect"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 16
                                            radius: 2
                                            border.color: appState ? timeline.overlayCropLockAspect(appState.selectedClipId) ? Theme.accent : Theme.border : Theme.border
                                            border.width: 1
                                            color: appState && timeline.overlayCropLockAspect(appState.selectedClipId) ? Theme.accent : "transparent"

                                            Label {
                                                anchors.centerIn: parent
                                                text: "L"
                                                color: Theme.textPrimary
                                                font.pixelSize: Theme.fontSizeXs
                                                font.bold: true
                                                visible: appState && timeline.overlayCropLockAspect(appState.selectedClipId)
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (appState) {
                                                        var locked = !timeline.overlayCropLockAspect(appState.selectedClipId)
                                                        timeline.setOverlayCropLockAspect(appState.selectedClipId, locked)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Snap-to-center toggle
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSm

                                        Label {
                                            text: "Snap to Center"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 16
                                            radius: 2
                                            border.color: appState ? timeline.overlayCropSnapCenter(appState.selectedClipId) ? Theme.accent : Theme.border : Theme.border
                                            border.width: 1
                                            color: appState && timeline.overlayCropSnapCenter(appState.selectedClipId) ? Theme.accent : "transparent"

                                            Label {
                                                anchors.centerIn: parent
                                                text: "+"
                                                color: Theme.textPrimary
                                                font.pixelSize: Theme.fontSizeXs
                                                visible: appState && timeline.overlayCropSnapCenter(appState.selectedClipId)
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (appState) {
                                                        var snapped = !timeline.overlayCropSnapCenter(appState.selectedClipId)
                                                        timeline.setOverlayCropSnapCenter(appState.selectedClipId, snapped)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Transform section
                                CollapsibleSection {
                                    title: "Transform"
                                    Layout.fillWidth: true
                                    isExpanded: true

                                    // Position X
                                    CapFxSlider {
                                        label: "Position X"
                                        from: 0; to: 1; step: 0.01
                                        value: appState ? timeline.overlayPos(appState.selectedClipId).x : 0.5
                                        onChanged: if (appState) { var p = timeline.overlayPos(appState.selectedClipId); timeline.setOverlayPos(appState.selectedClipId, v, p.y) }
                                    }

                                    // Position Y
                                    CapFxSlider {
                                        label: "Position Y"
                                        from: 0; to: 1; step: 0.01
                                        value: appState ? timeline.overlayPos(appState.selectedClipId).y : 0.5
                                        onChanged: if (appState) { var p = timeline.overlayPos(appState.selectedClipId); timeline.setOverlayPos(appState.selectedClipId, p.x, v) }
                                    }

                                    // Scale
                                    CapFxSlider {
                                        label: "Scale"
                                        from: 0.1; to: 5; step: 0.01
                                        value: appState ? timeline.overlayScale(appState.selectedClipId) : 1.0
                                        onChanged: if (appState) timeline.setOverlayScale(appState.selectedClipId, v)
                                    }

                                    // Rotation
                                    CapFxSlider {
                                        label: "Rotation"
                                        from: -180; to: 180; step: 1
                                        value: appState ? timeline.overlayRotation(appState.selectedClipId) : 0
                                        onChanged: if (appState) timeline.setOverlayRotation(appState.selectedClipId, v)
                                    }

                                    // Opacity
                                    CapFxSlider {
                                        label: "Opacity"
                                        from: 0; to: 1; step: 0.01
                                        value: appState ? timeline.overlayOpacity(appState.selectedClipId) : 1.0
                                        onChanged: if (appState) timeline.setOverlayOpacity(appState.selectedClipId, v)
                                    }
                                }

                                // Reset crop/transform button
                                Button {
                                    text: "Reset Crop & Transform"
                                    Layout.fillWidth: true
                                    onClicked: {
                                        if (!appState) return
                                        var id = appState.selectedClipId
                                        timeline.setOverlayCropLeft(id, 0)
                                        timeline.setOverlayCropTop(id, 0)
                                        timeline.setOverlayCropRight(id, 0)
                                        timeline.setOverlayCropBottom(id, 0)
                                        timeline.setOverlayCropLockAspect(id, false)
                                        timeline.setOverlayCropSnapCenter(id, false)
                                        timeline.setOverlayPos(id, 0.5, 0.5)
                                        timeline.setOverlayScale(id, 1.0)
                                        timeline.setOverlayRotation(id, 0)
                                        timeline.setOverlayOpacity(id, 1.0)
                                    }

                                    background: Rectangle {
                                        radius: Theme.radiusSmall
                                        color: parent.pressed ? Theme.borderLight : "transparent"
                                        border.color: Theme.border
                                        border.width: 1
                                    }

                                    contentItem: Label {
                                        text: parent.text
                                        color: Theme.textSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }

                            // === Text / Sticker Tab ===
                            ColumnLayout {
                                visible: root.rightTab === "text"
                                spacing: Theme.spacingSm
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm

                                Label {
                                    text: "Text & Sticker"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.Medium
                                    Layout.topMargin: Theme.spacingSm
                                }

                                // Hint when nothing selected
                                Label {
                                    visible: !(appState && appState.selectedClipKind >= 2)
                                    text: "Select a text or sticker clip on the timeline (or V2 track) to edit it."
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    wrapMode: Text.Wrap
                                }

                                // Editor (shown when an overlay clip is selected)
                                ColumnLayout {
                                    visible: appState && appState.selectedClipKind >= 2
                                    spacing: Theme.spacingSm
                                    Layout.fillWidth: true

                                    // Text content (Text clips only)
                                    ColumnLayout {
                                        visible: appState && appState.selectedClipKind === 2
                                        spacing: Theme.spacingXs
                                        Layout.fillWidth: true

                                        Label { text: "Text"; color: Theme.textPrimary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                                        TextField {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 30
                                            font.pixelSize: Theme.fontSizeSm
                                            color: Theme.textPrimary
                                            text: appState ? timeline.overlayText(appState.selectedClipId) : ""
                                            background: Rectangle { color: Theme.surfaceBg; radius: 3; border.color: Theme.border; border.width: 1 }
                                            onEditingFinished: if (appState) timeline.setOverlayText(appState.selectedClipId, text)
                                        }
                                    }

                                    // Font size
                                    CapFxSlider {
                                        visible: appState && appState.selectedClipKind === 2
                                        label: "Font Size"
                                        from: 12; to: 240; step: 1
                                        value: appState ? timeline.overlayFontSize(appState.selectedClipId) : 48
                                        onChanged: if (appState) timeline.setOverlayFontSize(appState.selectedClipId, v)
                                    }

                                    // Bold + color row
                                    RowLayout {
                                        visible: appState && appState.selectedClipKind === 2
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSm

                                        Rectangle {
                                            Layout.preferredWidth: 60
                                            Layout.preferredHeight: 26
                                            radius: 3
                                            color: bMouse.pressed ? Theme.borderLight : Theme.surfaceBg
                                            border.color: Theme.border; border.width: 1
                                            Label { anchors.centerIn: parent; text: "Bold"; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeXs; font.bold: true }
                                            MouseArea {
                                                id: bMouse
                                                anchors.fill: parent
                                                onClicked: if (appState) timeline.setOverlayBold(appState.selectedClipId, !timeline.overlayBold(appState.selectedClipId))
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                            radius: 3
                                            border.color: Theme.border; border.width: 1
                                            color: appState ? timeline.overlayColor(appState.selectedClipId) : "#ffffff"
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { colorDialog.target = "text"; colorDialog.open() }
                                            }
                                        }
                                        Label { text: "Color"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }

                                        Item { Layout.fillWidth: true }

                                        Rectangle {
                                            Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                            radius: 3
                                            border.color: Theme.border; border.width: 1
                                            color: appState ? timeline.overlayBg(appState.selectedClipId) : "transparent"
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { colorDialog.target = "bg"; colorDialog.open() }
                                            }
                                        }
                                        Label { text: "BG"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                                    }

                                    // Alignment (Text clips)
                                    RowLayout {
                                        visible: appState && appState.selectedClipKind === 2
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingXs
                                        Label { text: "Align"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                                        Item { Layout.fillWidth: true }
                                        Repeater {
                                            model: [ {a:0,t:"L"}, {a:1,t:"C"}, {a:2,t:"R"} ]
                                            Rectangle {
                                                Layout.preferredWidth: 26; Layout.preferredHeight: 24
                                                radius: 3
                                                color: alMouse.pressed ? Theme.borderLight : (appState && timeline.overlayAlign(appState.selectedClipId) === modelData.a ? Theme.accent : Theme.surfaceBg)
                                                border.color: Theme.border; border.width: 1
                                                Label { anchors.centerIn: parent; text: modelData.t; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeXs }
                                                MouseArea {
                                                    id: alMouse
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: if (appState) timeline.setOverlayAlign(appState.selectedClipId, modelData.a)
                                                }
                                            }
                                        }
                                    }

                                    // Transform (all overlay clips)
                                    CapFxSlider {
                                        label: "Position X"
                                        from: 0; to: 1; step: 0.01
                                        value: appState ? timeline.overlayPos(appState.selectedClipId).x : 0.5
                                        onChanged: if (appState) { var p = timeline.overlayPos(appState.selectedClipId); timeline.setOverlayPos(appState.selectedClipId, v, p.y) }
                                    }
                                    CapFxSlider {
                                        label: "Position Y"
                                        from: 0; to: 1; step: 0.01
                                        value: appState ? timeline.overlayPos(appState.selectedClipId).y : 0.5
                                        onChanged: if (appState) { var p = timeline.overlayPos(appState.selectedClipId); timeline.setOverlayPos(appState.selectedClipId, p.x, v) }
                                    }
                                    CapFxSlider {
                                        label: "Scale"
                                        from: 0.1; to: 5; step: 0.01
                                        value: appState ? timeline.overlayScale(appState.selectedClipId) : 1.0
                                        onChanged: if (appState) timeline.setOverlayScale(appState.selectedClipId, v)
                                    }
                                    CapFxSlider {
                                        label: "Rotation"
                                        from: -180; to: 180; step: 1
                                        value: appState ? timeline.overlayRotation(appState.selectedClipId) : 0
                                        onChanged: if (appState) timeline.setOverlayRotation(appState.selectedClipId, v)
                                    }
                                    CapFxSlider {
                                        label: "Opacity"
                                        from: 0; to: 1; step: 0.01
                                        value: appState ? timeline.overlayOpacity(appState.selectedClipId) : 1.0
                                        onChanged: if (appState) timeline.setOverlayOpacity(appState.selectedClipId, v)
                                    }
                                }
                            }

                            // === PIP (Picture-in-Picture) Tab ===
                            PIPControls {
                                id: pipControls
                                visible: root.rightTab === "pip"
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm
                            }

                            // === Transitions Tab ===
                            TransitionEditor {
                                id: transitionEditor
                                visible: root.rightTab === "transitions"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 320
                                Layout.margins: Theme.spacingSm

                                onApplyRequested: function(clipAId, clipBId, type, duration, params) {
                                    timeline.addTransition(clipAId, clipBId, type, duration, params || {})
                                    transitionEditor.scanAdjacentPairs()
                                }

                                onRemoveRequested: function(clipAId, clipBId) {
                                    timeline.removeTransition(clipAId, clipBId)
                                    transitionEditor.scanAdjacentPairs()
                                }
                            }

                            // === History Tab ===
                            ColumnLayout {
                                visible: root.rightTab === "history"
                                spacing: Theme.spacingSm
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm

                                Label {
                                    text: "Edit History"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.Medium
                                    Layout.topMargin: Theme.spacingSm
                                }

                                Label {
                                    text: "Recent actions on the undo stack."
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    wrapMode: Text.Wrap
                                }

                                // History list
                                ListView {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.min(historyModel.count * 28 * Theme.scale + 10 * Theme.scale, 200 * Theme.scale)
                                    clip: true
                                    model: timeline ? timeline.undoHistory() : []
                                    ScrollBar.vertical: ScrollBar {
                                        width: 6
                                        policy: ScrollBar.AsNeeded
                                        background: Rectangle { color: "transparent" }
                                        contentItem: Rectangle {
                                            radius: 3
                                            color: Theme.border
                                        }
                                    }

                                    delegate: Rectangle {
                                        width: parent ? parent.width : 200
                                        height: 28
                                        color: histMouse.pressed ? Theme.borderLight :
                                               (histMouse.containsMouse ? "#333333" : Theme.surfaceBg)
                                        border.bottom.color: Theme.borderDark
                                        border.bottom.width: 1

                                        Label {
                                            anchors.left: parent.left
                                            anchors.leftMargin: Theme.spacingSm
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                            elide: Text.ElideRight
                                        }

                                        MouseArea {
                                            id: histMouse
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.NoButton
                                        }
                                    }
                                }

                                // History info
                                Label {
                                    text: "Total actions: " + (timeline ? timeline.undoStackSize : 0)
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    wrapMode: Text.Wrap
                                }

                                // Keyboard hint
                                Label {
                                    text: "Ctrl+Z to undo · Ctrl+Y to redo"
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    wrapMode: Text.Wrap
                                }
                            }

                            // Reset button (shows at bottom of all tabs)
                            Button {
                                text: "↺ Reset All"
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingSm
                                Layout.topMargin: Theme.spacingMd
                                onClicked: fx.reset()

                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: parent.pressed ? Theme.borderLight : "transparent"
                                    border.color: Theme.border
                                    border.width: 1
                                }

                                contentItem: Label {
                                    text: parent.text
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            // Text Overlay editor panel (removed — inline editor above handles this)
                        }
                    }
                }
            }
        }

        // ---- Timeline ----
        Timeline {
            Layout.fillWidth: true
            Layout.preferredHeight: root.height * 0.38  // ~38% of window height
        }

        // ---- Status Bar ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            color: Theme.statusBarBg

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingMd
                anchors.rightMargin: Theme.spacingMd
                spacing: Theme.spacingMd

                // Left: File info + position
                Label {
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    text: {
                        if (!mediaEngine || mediaEngine.mediaPath === "")
                            return "Ghita Edit v0.1.5"
                        var dur = mediaEngine.durationMs || 0
                        var pos = mediaEngine.positionMs || 0
                        return mediaEngine.mediaPath.split("/").pop().split("\\").pop()
                             + "  ·  " + fmtTime(pos) + " / " + fmtTime(dur)
                    }
                }

                Item { Layout.fillWidth: true }

                // Undo/Redo status indicator
                Label {
                    visible: timeline && (timeline.canUndo || timeline.canRedo)
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    text: {
                        var parts = []
                        if (timeline.canUndo) {
                            var action = timeline.lastUndoAction
                            if (action) parts.push("\u21A9 " + action)
                            else parts.push("\u21A9 Undo")
                        }
                        if (timeline.canRedo) {
                            var action = timeline.lastRedoAction
                            if (action) parts.push("\u21AA " + action)
                            else parts.push("\u21AA Redo")
                        }
                        return parts.join("  |  ")
                    }
                    ToolTip {
                        visible: parent.hovered
                        text: "Keyboard: Ctrl+Z (Undo) / Ctrl+Y (Redo)"
                        delay: 400
                        background: Rectangle {
                            color: "#2e2e2e"
                            border.color: "#3a3a3a"
                            border.width: 1
                            radius: Theme.radiusSmall
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeSm
                            font.family: Theme.fontFamily
                        }
                    }
                }

                // Redo counter badge
                Label {
                    visible: timeline && timeline.canRedo
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    font.bold: true
                    text: "x" + timeline.undoStackSize
                }

                // Export progress
                ProgressBar {
                    visible: exportProgress > 0 && exportProgress < 100
                    value: exportProgress / 100
                    from: 0; to: 1
                    Layout.preferredWidth: 120
                    height: 12

                    background: Rectangle {
                        radius: 2
                        color: Theme.borderDark
                    }

                    contentItem: Rectangle {
                        radius: 2
                        color: Theme.accent
                        width: parent.visualPosition * parent.width
                    }
                }
                Label {
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    visible: exportProgress > 0
                    text: exportProgress + "%"
                }
                Label {
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    text: exportStatus
                }

                // Status indicator
                Rectangle {
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 6
                    radius: 3
                    color: playing ? Theme.accentGreen : Theme.textMuted
                }
                Label {
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    text: playing ? "Playing" : "Ready"
                }
            }
        }
    }

    // ---- CapCut-style Slider Component ----
    component CapFxSlider : ColumnLayout {
        id: fxSlider
        property string label
        property real from: 0
        property real to: 1
        property real step: 0.01
        property real value: 0
        signal changed(real v)

        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs

            Label {
                text: fxSlider.label
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                Layout.fillWidth: true
            }

            Label {
                text: fxSlider.value.toFixed(fxSlider.step < 0.1 ? 2 : 0)
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }
        }

        Slider {
            id: slider
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            from: fxSlider.from; to: fxSlider.to; stepSize: fxSlider.step; value: fxSlider.value
            onMoved: fxSlider.changed(value)

            // Track
            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.availableWidth
                height: 3
                radius: 1.5
                color: Theme.border

                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: 1.5
                    color: Theme.accent
                }
            }

            // Handle
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: 14 * Theme.scale
                height: 14 * Theme.scale
                radius: 7
                color: Theme.textPrimary
                border.color: Qt.darker(Theme.textPrimary, 1.2)
                border.width: 1
            }
        }
    }

    // ---- Right Panel Tab Component ----
    component RightTab : Rectangle {
        id: rightTabBtn
        property string text: ""
        property string tabId: ""
        property string activeTab: ""
        signal clicked()

        Layout.preferredHeight: 28
        Layout.preferredWidth: tabLabel.width + 24
        color: activeTab === tabId ? Theme.surfaceBg : "transparent"
        radius: Theme.radiusSmall

        Label {
            id: tabLabel
            anchors.centerIn: parent
            text: rightTabBtn.text
            color: activeTab === tabId ? Theme.textPrimary : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            font.weight: activeTab === tabId ? Font.Medium : Font.Normal
        }

        // Active indicator line
        Rectangle {
            visible: activeTab === tabId
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 16
            height: 2
            radius: 1
            color: Theme.accent
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: rightTabBtn.clicked()
        }
    }

    // ---- File Dialogs ----
    FileDialog {
        id: fileDialog
        title: "Import Media"
        nameFilters: [
            "Media files (*.mp4 *.mkv *.mov *.avi *.mp3 *.wav *.flac *.m4a)",
            "Video files (*.mp4 *.mkv *.mov *.avi)",
            "Audio files (*.mp3 *.wav *.flac *.m4a)",
            "All files (*)"
        ]
        fileMode: FileDialog.OpenFiles

        onAccepted: {
            var files = fileDialog.selectedFiles
            for (var i = 0; i < files.length; i++) {
                var path = exporter.urlToLocalPath(files[i])
                if (path === "" || path === undefined || path === null) {
                    console.error("Failed to convert URL to path:", files[i])
                    continue
                }
                console.log("Importing:", path)
                mediaBinModel.addMedia(path)
            }
        }
    }

    FileDialog {
        id: stickerFileDialog
        title: "Import sticker image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.svg *.webp)", "All files (*)"]
        onAccepted: {
            var p = exporter.urlToLocalPath(stickerFileDialog.selectedFile)
            if (p === "" || p === undefined || p === null) {
                console.error("Failed to convert URL to path:", stickerFileDialog.selectedFile)
                return
            }
            root.addStickerAtPlayhead(p)
        }
    }

    // PIP Video file dialog
    FileDialog {
        id: pipVideoFileDialog
        title: "Import PIP video"
        nameFilters: [
            "Video files (*.mp4 *.mkv *.mov *.avi)",
            "All files (*)"
        ]
        onAccepted: {
            var p = exporter.urlToLocalPath(pipVideoFileDialog.selectedFile)
            if (p === "" || p === undefined || p === null) {
                console.error("Failed to convert URL to path:", pipVideoFileDialog.selectedFile)
                return
            }
            root.addPipVideoClipAtPlayhead(p)
        }
    }

    // PIP Image file dialog
    FileDialog {
        id: pipImageFileDialog
        title: "Import PIP image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.svg *.webp)", "All files (*)"]
        onAccepted: {
            var p = exporter.urlToLocalPath(pipImageFileDialog.selectedFile)
            if (p === "" || p === undefined || p === null) {
                console.error("Failed to convert URL to path:", pipImageFileDialog.selectedFile)
                return
            }
            root.addPipImageClipAtPlayhead(p)
        }
    }

    // Updated ColorDialog to support PIP properties
    ColorDialog {
        id: colorDialog
        property string target: "text"
        onAccepted: {
            if (!appState) return
            var id = appState.selectedClipId
            var c = colorDialog.selectedColor.toString()
            if (target === "text") timeline.setOverlayColor(id, c)
            else if (target === "bg") timeline.setOverlayBg(id, c)
            else if (target === "pipBorder") timeline.setPipBorderColor(id, c)
            else if (target === "pipShadow") timeline.setPipShadowColor(id, c)
        }
    }

    ExportDialog {
        id: exportDialog
        onBeginExport: function(path, w, h, crf) {
            exporter.setTargetSize(w, h)
            exporter.setCrf(crf)
            toast.show("Starting export...", "info")
            startExport(path)
        }
    }

    Connections {
        target: exporter
        function onProgressChanged(p) { exportProgress = p }
        function onExportFinished(ok) {
            exportStatus = ok ? "Export finished" : "Export failed"
            if (ok) {
                toast.show("Export completed successfully", "success")
            } else {
                toast.show("Export failed", "error")
            }
        }
    }

    Connections {
        target: timeline
        function onClipAdded(id) {
            toast.show("Clip added", "success")
        }
        function onClipRemoved(id) {
            toast.show("Clip removed", "warning")
        }
        function onClipsPasted(ids) {
            toast.show("Clips pasted", "info")
        }
    }

    // ---- Keyboard shortcuts ----
    focus: true
    Keys.onPressed: function(event) {
        // Skip shortcuts when typing in text fields
        if (event.target instanceof TextInput || event.target instanceof TextField) return

        // Space: Play/Pause
        if (event.key === Qt.Key_Space && !event.modifiers) {
            mediaEngine.playing ? mediaEngine.pause() : mediaEngine.play()
            event.accepted = true
        }
        // Delete: Remove selected clip
        else if (event.key === Qt.Key_Delete) {
            if (appState.selectedClipId !== -1) {
                timeline.deleteClip(appState.selectedClipId)
                toast.show("Clip deleted", "warning")
            }
            event.accepted = true
        }
        // Ctrl+Z: Undo
        else if (event.key === Qt.Key_Z && event.modifiers & Qt.ControlModifier) {
            timeline.undo()
            event.accepted = true
        }
        // Ctrl+Y: Redo
        else if (event.key === Qt.Key_Y && event.modifiers & Qt.ControlModifier) {
            timeline.redo()
            event.accepted = true
        }
        // S: Split at playhead
        else if (event.key === Qt.Key_S && !event.modifiers) {
            if (appState.selectedClipId !== -1) {
                timeline.splitClip(appState.selectedClipId, timeline.positionMs)
                toast.show("Clip split", "info")
            }
            event.accepted = true
        }
        // Ctrl+Shift+A: Add video track
        else if (event.key === Qt.Key_A && event.modifiers & Qt.ControlModifier && event.modifiers & Qt.ShiftModifier) {
            timeline.addTrack(0)  // TrackVideo
            event.accepted = true
        }
        // Ctrl+Shift+T: Add audio track
        else if (event.key === Qt.Key_T && event.modifiers & Qt.ControlModifier && event.modifiers & Qt.ShiftModifier) {
            timeline.addTrack(1)  // TrackAudio
            event.accepted = true
        }
        // Ctrl+Shift+O: Add overlay track
        else if (event.key === Qt.Key_O && event.modifiers & Qt.ControlModifier && event.modifiers & Qt.ShiftModifier) {
            timeline.addTrack(2)  // TrackOverlay
            event.accepted = true
        }
        // Ctrl+Shift+P: Add PIP video
        else if (event.key === Qt.Key_P && event.modifiers & Qt.ControlModifier && event.modifiers & Qt.ShiftModifier) {
            pipVideoFileDialog.open()
            event.accepted = true
        }
    }

    // ---- Toast Notification ----
    ToastNotification {
        id: toast
        anchors.fill: parent
        z: 1000
    }

    // Connect to MediaBinModel signals for import feedback
    Connections {
        target: mediaBinModel
        function onMediaError(msg) {
            toast.show(msg, "error")
        }
        function onMediaAdded(index) {
            toast.show("Media imported successfully", "success")
        }
    }
}
