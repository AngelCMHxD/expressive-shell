import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

PanelWindow {
    id: dock

    required property var modelData
    screen: modelData

    readonly property bool isPopupMode: ShellState.dockMode === "popup"
    readonly property bool isOff: ShellState.dockMode === "off"
    property bool hovered: false
    readonly property bool revealed: ShellState.ready && !isOff && (!isPopupMode || hovered || ShellState.activeOverlay === "launcher" || ShellState.activeOverlay === "wallpapers" || (ShellState.appMenuOpen && ShellState.appMenuFromBottom))

    // Keep window alive during close animation so switching to "off" animates smoothly
    property bool windowVisible: !isOff
    visible: ShellState.ready && windowVisible

    onIsOffChanged: {
        if (!isOff) {
            windowVisible = true;
        }
    }

    anchors {
        bottom: true
        left: true
        right: true
    }

    // Constant Wayland surface height: 54px in Fixed mode, 74px in Pop-up mode
    // (gives generous room for the floating M3E pill + spring overshoot without clipping)
    implicitHeight: isPopupMode ? 74 : 54
    exclusiveZone: (ShellState.ready && ShellState.dockMode === "always") ? 54 : 0
    color: "transparent"

    // Only use an input region mask in Pop-up mode; Fixed mode needs no mask so clicks never break.
    // Use stationary `popupZone` (full resting footprint) while revealed so fast upward flicks
    // during the spring pop-in stay inside the hover zone instead of triggering auto-hide.
    Region {
        id: popupMask
        item: dock.revealed ? popupZone : triggerStrip
    }
    mask: dock.isPopupMode ? popupMask : null

    WlrLayershell.namespace: "expressive-dock"
    WlrLayershell.layer: WlrLayer.Overlay

    // Stable list of unpinned running app_ids (preserves order across focus changes)
    property var unpinnedAppIds: []

    function syncUnpinnedApps() {
        const pinned = new Set(ShellState.pinnedApps);
        const present = new Set();
        for (const w of Umbriel.windows) {
            if (!w.app_id || w.scratchpad || pinned.has(w.app_id)) continue;
            present.add(w.app_id);
        }
        const next = unpinnedAppIds.filter(id => present.has(id));
        const existing = new Set(next);
        for (const id of present) {
            if (!existing.has(id)) {
                next.push(id);
                existing.add(id);
            }
        }
        if (next.length !== unpinnedAppIds.length || next.some((id, i) => id !== unpinnedAppIds[i])) {
            unpinnedAppIds = next;
        }
    }

    Connections {
        target: Umbriel
        function onWindowsChanged() { dock.syncUnpinnedApps(); }
    }

    Component.onCompleted: syncUnpinnedApps()

    function isAppRunning(appId) {
        return Umbriel.windows.some(w => w.app_id === appId);
    }

    function isAppFocused(appId) {
        return Umbriel.windows.some(w => w.app_id === appId && w.active);
    }

    function firstWindowId(appId) {
        const w = Umbriel.windows.find(win => win.app_id === appId);
        return w ? w.id : "";
    }

    // Thin bottom-edge hover zone when hidden in pop-up mode
    Item {
        id: triggerStrip
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 6

        HoverHandler { id: triggerHover }
    }

    // Stationary full resting footprint of the popped-up pill (prevents closing on fast upward flicks)
    Item {
        id: popupZone
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: surface.width + 16
        height: 68

        HoverHandler { id: zoneHover }
    }

    readonly property bool pointerInside: triggerHover.hovered || zoneHover.hovered || surfaceHover.hovered

    onPointerInsideChanged: {
        if (pointerInside) {
            hideTimer.stop();
            dock.hovered = true;
        } else {
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 320
        onTriggered: {
            if (!dock.pointerInside) dock.hovered = false;
        }
    }

    // Expressive-style tonal M3 bottom taskbar surface:
    // Full-width bar in Fixed mode; floating M3E rounded pill with spring pop-up in Pop-up mode!
    Rectangle {
        id: surface
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dock.isPopupMode ? 10 : 0
        width: dock.isPopupMode ? Math.min(parent.width - 32, dockRow.implicitWidth + 32) : parent.width
        height: 54
        radius: dock.isPopupMode ? 27 : 0

        color: Theme.glassSurface
        border.width: 1
        border.color: Theme.glassBorder

        Behavior on width {
            enabled: dock.windowVisible
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping }
        }
        Behavior on radius { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        HoverHandler { id: surfaceHover }

        transformOrigin: Item.Bottom
        transform: Translate { id: dockTranslate; y: 0 }
        state: dock.revealed ? "shown" : "hidden"

        states: [
            State {
                name: "shown"
                PropertyChanges { target: surface; scale: 1.0 }
                PropertyChanges { target: dockTranslate; y: 0 }
                PropertyChanges { target: iconsTranslate; y: 0 }
            },
            State {
                name: "hidden"
                PropertyChanges { target: surface; scale: dock.isPopupMode ? 0.82 : 1.0 }
                PropertyChanges { target: dockTranslate; y: dock.isPopupMode ? 74 : 56 }
                PropertyChanges { target: iconsTranslate; y: 12 }
            }
        ]

        transitions: [
            Transition {
                from: "hidden"; to: "shown"
                ParallelAnimation {
                    SpringAnimation { target: dockTranslate; property: "y"; spring: 7.8; damping: 0.34; epsilon: 0.05 }
                    SpringAnimation { target: surface; property: "scale"; spring: 7.8; damping: 0.34; epsilon: 0.004 }
                    SpringAnimation { target: iconsTranslate; property: "y"; spring: 9.0; damping: 0.38; epsilon: 0.05 }
                }
            },
            Transition {
                from: "shown"; to: "hidden"
                SequentialAnimation {
                    ParallelAnimation {
                        NumberAnimation { target: dockTranslate; property: "y"; duration: 170; easing.type: Easing.InCubic }
                        NumberAnimation { target: surface; property: "scale"; duration: 160; easing.type: Easing.InCubic }
                        NumberAnimation { target: iconsTranslate; property: "y"; duration: 150; easing.type: Easing.InCubic }
                    }
                    ScriptAction {
                        script: { if (dock.isOff) dock.windowVisible = false; }
                    }
                }
            }
        ]

        // Always centered cleanly (never swaps anchors across modes)
        RowLayout {
            id: dockRow
            anchors.centerIn: parent
            spacing: 10
            transform: Translate { id: iconsTranslate; y: 0 }

            // Accent Pill Launcher Button
            Rectangle {
                id: launcherBtn
                Layout.preferredWidth: 46
                Layout.preferredHeight: 34
                radius: launcherMouse.pressed ? Theme.radiusMedium : 17
                color: Theme.primary

                scale: launcherMouse.pressed ? 0.92 : (launcherMouse.containsMouse ? 1.07 : 1.0)
                Behavior on scale {
                    SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping }
                }
                Behavior on radius { NumberAnimation { duration: Motion.fast } }

                Text {
                    anchors.centerIn: parent
                    text: "󰀻"
                    color: Theme.fgPrimary
                    font.family: Theme.fontMono
                    font.pixelSize: 18
                }

                MouseArea {
                    id: launcherMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ShellState.toggleOverlay("launcher")
                }
            }

            // Divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 22
                color: Theme.alpha(Theme.outlineVariant, 0.7)
            }

            // Pinned apps
            Repeater {
                model: ShellState.pinnedApps

                delegate: Item {
                    id: pinnedItem
                    required property string modelData
                    readonly property bool running: dock.isAppRunning(modelData)
                    readonly property bool focused: dock.isAppFocused(modelData)

                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 42

                    Rectangle {
                        id: iconBg
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        width: 34
                        height: 34
                        radius: pinnedMouse.containsMouse ? 12 : 17
                        color: pinnedItem.focused
                            ? Theme.primaryContainer
                            : (pinnedMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent")

                        scale: pinnedMouse.pressed ? 0.88 : (pinnedMouse.containsMouse ? 1.12 : 1.0)
                        Behavior on scale {
                            SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping }
                        }
                        Behavior on radius { NumberAnimation { duration: Motion.fast } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Image {
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            sourceSize.width: 48
                            sourceSize.height: 48
                            smooth: true
                            mipmap: true
                            source: Umbriel.iconForAppId(pinnedItem.modelData)
                        }
                    }

                    // Active / running indicator pill
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        height: 3
                        width: pinnedItem.focused ? 16 : (pinnedItem.running ? 6 : 0)
                        radius: 2
                        color: pinnedItem.focused ? Theme.primary : Theme.fgSurfaceVariant

                        Behavior on width {
                            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping }
                        }
                    }

                    MouseArea {
                        id: pinnedMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                const pt = pinnedItem.mapToItem(null, pinnedItem.width / 2, 0);
                                ShellState.openAppMenu(pinnedItem.modelData, pinnedItem.modelData, pt.x, pt.y, true);
                            } else {
                                Umbriel.launchAppId(pinnedItem.modelData);
                            }
                        }
                    }
                }
            }

            // Divider before unpinned running apps
            Rectangle {
                visible: dock.unpinnedAppIds.length > 0
                Layout.preferredWidth: 1
                Layout.preferredHeight: 22
                color: Theme.alpha(Theme.outlineVariant, 0.7)
            }

            // Unpinned running apps (stable app_id model so focus animations work)
            Repeater {
                model: dock.unpinnedAppIds

                delegate: Item {
                    id: runItem
                    required property string modelData
                    readonly property bool focused: dock.isAppFocused(modelData)

                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 42

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        width: 34
                        height: 34
                        radius: runMouse.containsMouse ? 12 : 17
                        color: runItem.focused
                            ? Theme.secondaryContainer
                            : (runMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent")

                        scale: runMouse.pressed ? 0.88 : (runMouse.containsMouse ? 1.12 : 1.0)
                        Behavior on scale {
                            SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping }
                        }
                        Behavior on radius { NumberAnimation { duration: Motion.fast } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Image {
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            sourceSize.width: 48
                            sourceSize.height: 48
                            smooth: true
                            mipmap: true
                            source: Umbriel.iconForAppId(runItem.modelData)
                        }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        height: 3
                        width: runItem.focused ? 16 : 6
                        radius: 2
                        color: runItem.focused ? Theme.primary : Theme.fgSurfaceVariant

                        Behavior on width {
                            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping }
                        }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    MouseArea {
                        id: runMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                const pt = runItem.mapToItem(null, runItem.width / 2, 0);
                                ShellState.openAppMenu(runItem.modelData, runItem.modelData, pt.x, pt.y, true);
                            } else {
                                const wid = dock.firstWindowId(runItem.modelData);
                                if (wid) Umbriel.focusWindow(wid);
                            }
                        }
                    }
                }
            }
        }
    }
}
