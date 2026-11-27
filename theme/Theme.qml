pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var paletteData: ({})

    FileView {
        id: colorsFile
        path: ShellState.configDir + "/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.paletteData = JSON.parse(text());
            } catch (e) {
                console.warn("Theme: failed to parse colors.json:", e);
            }
        }
    }

    readonly property var active: {
        const mode = ShellState.darkMode ? "dark" : "light";
        return (paletteData && paletteData[mode]) ? paletteData[mode] : {};
    }

    function c(key, fallback) {
        return (active && active[key]) ? active[key] : fallback;
    }

    function alpha(col, a) {
        const q = Qt.color(col);
        return Qt.rgba(q.r, q.g, q.b, a);
    }

    readonly property int themeAnimMs: 320

    // Material 3 Expressive color roles (smoothly animated on Dark<->Light & wallpaper changes)
    // Note: foreground roles use `fg*` instead of `on*` because QML reserves
    // `on<Prop>` for property-change signal handlers.
    property color primary: c("primary", "#80d5c4")
    Behavior on primary { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color fgPrimary: c("on_primary", "#00372f")
    Behavior on fgPrimary { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color primaryContainer: c("primary_container", "#005045")
    Behavior on primaryContainer { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color fgPrimaryContainer: c("on_primary_container", "#9cf2e0")
    Behavior on fgPrimaryContainer { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color secondary: c("secondary", "#b1ccc4")
    Behavior on secondary { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color fgSecondary: c("on_secondary", "#1c352f")
    Behavior on fgSecondary { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color secondaryContainer: c("secondary_container", "#334b45")
    Behavior on secondaryContainer { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color fgSecondaryContainer: c("on_secondary_container", "#cde8e0")
    Behavior on fgSecondaryContainer { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color tertiary: c("tertiary", "#a9cbe3")
    Behavior on tertiary { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color fgTertiary: c("on_tertiary", "#0f3447")
    Behavior on fgTertiary { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color tertiaryContainer: c("tertiary_container", "#294a5f")
    Behavior on tertiaryContainer { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color fgTertiaryContainer: c("on_tertiary_container", "#c7e7ff")
    Behavior on fgTertiaryContainer { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color surface: c("surface", "#0e1513")
    Behavior on surface { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color surfaceContainerLowest: c("surface_container_lowest", "#090f0e")
    Behavior on surfaceContainerLowest { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color surfaceContainerLow: c("surface_container_low", "#161d1b")
    Behavior on surfaceContainerLow { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color surfaceContainer: c("surface_container", "#1a211f")
    Behavior on surfaceContainer { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color surfaceContainerHigh: c("surface_container_high", "#252b2a")
    Behavior on surfaceContainerHigh { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color surfaceContainerHighest: c("surface_container_highest", "#303634")
    Behavior on surfaceContainerHighest { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color fgSurface: c("on_surface", "#dee4e1")
    Behavior on fgSurface { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color fgSurfaceVariant: c("on_surface_variant", "#bec9c5")
    Behavior on fgSurfaceVariant { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color outline: c("outline", "#89938f")
    Behavior on outline { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color outlineVariant: c("outline_variant", "#3f4946")
    Behavior on outlineVariant { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color error: c("error", "#ffb4ab")
    Behavior on error { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color fgError: c("on_error", "#690005")
    Behavior on fgError { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color livePill: c("live_pill", "#4cd964")
    Behavior on livePill { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color fgLivePill: c("on_live_pill", "#002108")
    Behavior on fgLivePill { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    // Frosted M3E surface helpers (derived from raw target colors so they animate in lockstep)
    property color glassSurface: alpha(c("surface_container", "#1a211f"), ShellState.darkMode ? 0.62 : 0.74)
    Behavior on glassSurface { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color glassSurfaceSoft: alpha(c("surface_container_high", "#252b2a"), ShellState.darkMode ? 0.42 : 0.56)
    Behavior on glassSurfaceSoft { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color glassSurfaceHigh: alpha(c("surface_container_high", "#252b2a"), ShellState.darkMode ? 0.74 : 0.82)
    Behavior on glassSurfaceHigh { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    property color glassBorder: alpha(c("outline_variant", "#3f4946"), ShellState.darkMode ? 0.50 : 0.42)
    Behavior on glassBorder { ColorAnimation { duration: root.themeAnimMs; easing.type: Easing.InOutCubic } }

    // Typography & Shape tokens (M3 Expressive)
    readonly property string fontSans: "Poppins"
    readonly property string fontMono: "JetBrainsMono Nerd Font"

    readonly property int radiusSmall: 10
    readonly property int radiusMedium: 16
    readonly property int radiusLarge: 24
    readonly property int radiusExtraLarge: 28
    readonly property int radiusPill: 999
}
