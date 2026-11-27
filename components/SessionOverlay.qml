import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

// M3 Expressive Session / Power Overlay (pops up at the bottom, no fullscreen background blur, 1-4 / L-S-R-P keys)
PanelWindow {
    id: sessWin

    required property var modelData
    screen: modelData

    readonly property bool isOpen: ShellState.activeOverlay === "session"
    property bool windowVisible: false
    visible: windowVisible

    Timer {
        id: openTrigger
        interval: 25
        onTriggered: {
            card.state = "open";
            card.forceActiveFocus();
        }
    }

    onIsOpenChanged: {
        if (isOpen) {
            card.state = "closed";
            windowVisible = true;
            openTrigger.restart();
        } else {
            openTrigger.stop();
            card.state = "closed";
        }
    }

    function runAction(action) {
        ShellState.closeOverlay();
        if (action === "lock") SystemStatus.lockSession();
        else if (action === "suspend") SystemStatus.suspendSystem();
        else if (action === "reboot") SystemStatus.rebootSystem();
        else if (action === "poweroff") SystemStatus.poweroffSystem();
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    color: "transparent"

    // Dedicated namespace outside Umbriel's blur rule so the background behind the menu isn't blurred
    WlrLayershell.namespace: "expressive-session"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Click outside to close (no blurred/dimmed fullscreen backdrop)
    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.closeOverlay()
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: ShellState.dockMode === "popup" ? 76 : 18
        width: 468
        implicitHeight: col.implicitHeight + 36
        height: implicitHeight
        radius: Theme.radiusExtraLarge
        color: Theme.alpha(Theme.surfaceContainer, 0.94)
        border.width: 1
        border.color: Theme.glassBorder

        Keys.onEscapePressed: ShellState.closeOverlay()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_1 || event.key === Qt.Key_L) sessWin.runAction("lock");
            else if (event.key === Qt.Key_2 || event.key === Qt.Key_S) sessWin.runAction("suspend");
            else if (event.key === Qt.Key_3 || event.key === Qt.Key_R) sessWin.runAction("reboot");
            else if (event.key === Qt.Key_4 || event.key === Qt.Key_P) sessWin.runAction("poweroff");
        }

        MouseArea { anchors.fill: parent }

        transformOrigin: Item.Bottom
        state: "closed"
        opacity: 0.0
        scale: 0.86
        transform: Translate { id: cardTranslate; y: 18 }

        states: [
            State {
                name: "open"
                PropertyChanges { target: card; opacity: 1.0; scale: 1.0 }
                PropertyChanges { target: cardTranslate; y: 0 }
            },
            State {
                name: "closed"
                PropertyChanges { target: card; opacity: 0.0; scale: 0.86 }
                PropertyChanges { target: cardTranslate; y: 18 }
            }
        ]

        transitions: [
            Transition {
                from: "closed"; to: "open"
                ParallelAnimation {
                    NumberAnimation { target: card; property: "opacity"; from: 0.0; to: 1.0; duration: 45; easing.type: Easing.OutQuad }
                    SpringAnimation { target: card; property: "scale"; spring: 7.5; damping: 0.36; epsilon: 0.004 }
                    SpringAnimation { target: cardTranslate; property: "y"; spring: 7.5; damping: 0.36; epsilon: 0.004 }
                }
            },
            Transition {
                from: "open"; to: "closed"
                SequentialAnimation {
                    ParallelAnimation {
                        NumberAnimation { target: card; property: "opacity"; duration: 120; easing.type: Easing.OutQuad }
                        NumberAnimation { target: card; property: "scale"; duration: 130; easing.type: Easing.InCubic }
                        NumberAnimation { target: cardTranslate; property: "y"; duration: 130; easing.type: Easing.InCubic }
                    }
                    ScriptAction {
                        script: { if (!sessWin.isOpen) sessWin.windowVisible = false; }
                    }
                }
            }
        ]

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 18
            spacing: 14

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Power & Session"
                    color: Theme.fgSurface
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Press 1–4 or Esc"
                    color: Theme.fgSurfaceVariant
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: [
                        { num: "1", icon: "󰌾", label: "Lock", action: "lock", danger: false },
                        { num: "2", icon: "󰤄", label: "Suspend", action: "suspend", danger: false },
                        { num: "3", icon: "󰜉", label: "Reboot", action: "reboot", danger: false },
                        { num: "4", icon: "󰐥", label: "Power Off", action: "poweroff", danger: true }
                    ]

                    delegate: Rectangle {
                        id: btn
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 92
                        radius: m.containsMouse ? 24 : 18
                        color: m.containsMouse
                            ? (modelData.danger ? Theme.error : Theme.primaryContainer)
                            : Theme.surfaceContainerHigh

                        scale: m.pressed ? 0.93 : (m.containsMouse ? 1.04 : 1.0)
                        Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                        Behavior on radius { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        // Shortcut keycap badge (1-4)
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 8
                            width: 18
                            height: 18
                            radius: 6
                            color: m.containsMouse
                                ? Theme.alpha(btn.modelData.danger ? Theme.fgError : Theme.fgPrimaryContainer, 0.2)
                                : Theme.surfaceContainerHighest

                            Text {
                                anchors.centerIn: parent
                                text: btn.modelData.num
                                color: m.containsMouse
                                    ? (btn.modelData.danger ? Theme.fgError : Theme.fgPrimaryContainer)
                                    : Theme.fgSurfaceVariant
                                font.family: Theme.fontSans
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 7

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: btn.modelData.icon
                                color: m.containsMouse
                                    ? (btn.modelData.danger ? Theme.fgError : Theme.fgPrimaryContainer)
                                    : Theme.fgSurface
                                font.family: Theme.fontMono
                                font.pixelSize: 22
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: btn.modelData.label
                                color: m.containsMouse
                                    ? (btn.modelData.danger ? Theme.fgError : Theme.fgPrimaryContainer)
                                    : Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            id: m
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sessWin.runAction(btn.modelData.action)
                        }
                    }
                }
            }
        }
    }
}
