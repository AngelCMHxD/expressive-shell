import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

// Shared M3 Expressive Right-Click Context Menu for BottomDock & LauncherPopup
PanelWindow {
    id: menuWin

    required property var modelData
    screen: modelData

    readonly property bool isOpen: ShellState.appMenuOpen
    property bool windowVisible: false
    visible: windowVisible

    Timer { id: openTrigger; interval: 16; onTriggered: menuCard.state = "open" }
    Timer { id: closeHideTimer; interval: 150; onTriggered: if (!menuWin.isOpen) menuWin.windowVisible = false }

    onIsOpenChanged: {
        if (isOpen) {
            closeHideTimer.stop();
            menuCard.state = "closed";
            windowVisible = true;
            openTrigger.restart();
        } else {
            openTrigger.stop();
            menuCard.state = "closed";
            closeHideTimer.restart();
        }
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.namespace: "expressive-shade"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: ShellState.closeAppMenu()
    }

    Rectangle {
        id: menuCard
        readonly property bool pinned: ShellState.isAppPinned(ShellState.appMenuId)

        width: 196
        height: menuCol.implicitHeight + 12
        x: Math.max(10, Math.min(menuWin.width - width - 10, ShellState.appMenuX - width / 2))
        y: ShellState.appMenuFromBottom
            ? Math.max(10, menuWin.height - height - (ShellState.dockMode === "popup" ? 76 : 62))
            : Math.max(10, Math.min(menuWin.height - height - 10, ShellState.appMenuY))

        radius: 18
        color: Theme.glassSurfaceHigh
        border.width: 1
        border.color: Theme.glassBorder

        transformOrigin: ShellState.appMenuFromBottom ? Item.Bottom : Item.Top
        state: "closed"
        opacity: 0.0
        scale: 0.88
        transform: Translate { id: menuTranslate; y: ShellState.appMenuFromBottom ? 8 : -8 }

        states: [
            State {
                name: "open"
                PropertyChanges { target: menuCard; opacity: 1.0; scale: 1.0 }
                PropertyChanges { target: menuTranslate; y: 0 }
            },
            State {
                name: "closed"
                PropertyChanges { target: menuCard; opacity: 0.0; scale: 0.88 }
                PropertyChanges { target: menuTranslate; y: ShellState.appMenuFromBottom ? 8 : -8 }
            }
        ]

        transitions: [
            Transition {
                from: "closed"; to: "open"
                ParallelAnimation {
                    NumberAnimation { target: menuCard; property: "opacity"; from: 0.0; to: 1.0; duration: 45; easing.type: Easing.OutQuad }
                    SpringAnimation { target: menuCard; property: "scale"; spring: 8.5; damping: 0.42; epsilon: 0.004 }
                    SpringAnimation { target: menuTranslate; property: "y"; spring: 8.5; damping: 0.42; epsilon: 0.004 }
                }
            },
            Transition {
                from: "open"; to: "closed"
                SequentialAnimation {
                    ParallelAnimation {
                        NumberAnimation { target: menuCard; property: "opacity"; duration: 100; easing.type: Easing.OutQuad }
                        NumberAnimation { target: menuCard; property: "scale"; duration: 110; easing.type: Easing.InCubic }
                        NumberAnimation { target: menuTranslate; property: "y"; duration: 110; easing.type: Easing.InCubic }
                    }
                    ScriptAction { script: { if (!menuWin.isOpen) menuWin.windowVisible = false; } }
                }
            }
        ]

        focus: menuWin.isOpen
        Keys.onEscapePressed: ShellState.closeAppMenu()

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: menuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            spacing: 2

            // Open / Focus app
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 12
                color: openM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Text { text: "󰏌"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Open " + ShellState.appMenuName
                        color: Theme.fgSurface
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    id: openM
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const id = ShellState.appMenuId;
                        ShellState.closeAppMenu();
                        if (ShellState.activeOverlay === "launcher") ShellState.closeOverlay();
                        Umbriel.launchAppId(id);
                    }
                }
            }

            // Pin / Unpin from taskbar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 12
                color: pinM.containsMouse ? Theme.primaryContainer : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        text: menuCard.pinned ? "󰐄" : "󰐃"
                        color: pinM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurface
                        font.family: Theme.fontMono
                        font.pixelSize: 15
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: menuCard.pinned ? "Unpin from taskbar" : "Pin to taskbar"
                        color: pinM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurface
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    id: pinM
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        ShellState.togglePinApp(ShellState.appMenuId);
                        ShellState.closeAppMenu();
                    }
                }
            }
        }
    }
}
