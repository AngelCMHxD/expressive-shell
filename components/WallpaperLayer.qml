import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

// Static low-power wallpaper layer (renders static 1st frame of GIFs/images at 0% CPU).
// Waits for async decode (`Image.Ready`) before crossfading so it NEVER flashes blank.
PanelWindow {
    id: wpWin

    required property var modelData
    screen: modelData

    readonly property bool shouldShow: (!Wallpaper.useAwww || !Wallpaper.awwwReady) && Wallpaper.currentWallpaper.length > 0
    visible: shouldShow || container.opacity > 0.01

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.namespace: "expressive-wallpaper"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    property string frontSource: ""
    property string backSource: ""
    property bool showingFront: true
    property bool pendingSwapToBack: false
    property bool pendingSwapToFront: false

    function loadSource(path) {
        if (!path) return;
        const url = "file://" + path;
        if (showingFront) {
            if (frontSource === url) return;
            pendingSwapToFront = false;
            pendingSwapToBack = true;
            if (backSource === url && backImg.status === Image.Ready) {
                pendingSwapToBack = false;
                showingFront = false;
            } else {
                backSource = url;
            }
        } else {
            if (backSource === url) return;
            pendingSwapToBack = false;
            pendingSwapToFront = true;
            if (frontSource === url && frontImg.status === Image.Ready) {
                pendingSwapToFront = false;
                showingFront = true;
            } else {
                frontSource = url;
            }
        }
    }

    Connections {
        target: Wallpaper
        function onCurrentWallpaperChanged() {
            wpWin.loadSource(Wallpaper.currentWallpaper);
        }
    }

    Component.onCompleted: {
        if (Wallpaper.currentWallpaper) {
            frontSource = "file://" + Wallpaper.currentWallpaper;
            showingFront = true;
        }
    }

    Item {
        id: container
        anchors.fill: parent
        opacity: wpWin.shouldShow ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        // Note: Qt Quick `Image` (not AnimatedImage) naturally decodes only frame 0 of GIFs.
        // Disable bilinear smoothing for pixel-art / low-res wallpapers (< 1280px or .gif) so pixels stay razor-sharp.
        Image {
            id: backImg
            anchors.fill: parent
            source: wpWin.backSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: implicitWidth >= 1280 && !wpWin.backSource.toLowerCase().endsWith(".gif")
            opacity: wpWin.showingFront ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: 360; easing.type: Easing.InOutCubic } }

            onStatusChanged: {
                if (status === Image.Ready && wpWin.pendingSwapToBack) {
                    wpWin.pendingSwapToBack = false;
                    wpWin.showingFront = false;
                }
            }
        }

        Image {
            id: frontImg
            anchors.fill: parent
            source: wpWin.frontSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: implicitWidth >= 1280 && !wpWin.frontSource.toLowerCase().endsWith(".gif")
            opacity: wpWin.showingFront ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 360; easing.type: Easing.InOutCubic } }

            onStatusChanged: {
                if (status === Image.Ready && wpWin.pendingSwapToFront) {
                    wpWin.pendingSwapToFront = false;
                    wpWin.showingFront = true;
                }
            }
        }
    }
}
