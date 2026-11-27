import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../theme"

// M3 Expressive Right-Click Context Menu for System Tray items
PanelWindow {
    id: trayMenuWin

    required property var modelData
    screen: modelData

    readonly property bool isOpen: ShellState.trayMenuOpen
    property bool windowVisible: false
    visible: windowVisible

    Timer { id: openTrigger; interval: 16; onTriggered: menuCard.state = "open" }
    Timer { id: closeHideTimer; interval: 150; onTriggered: if (!trayMenuWin.isOpen) trayMenuWin.windowVisible = false }

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

    // Navigation stack for nested submenus (each entry is a QsMenuEntry whose parent QsMenuOpener stays alive!)
    property var menuStack: []
    property int subSlideDir: 1
    property bool pendingSubSlide: false

    onIsOpenChanged: {
        if (isOpen) {
            closeHideTimer.stop();
            menuStack = [];
            menuCard.state = "closed";
            windowVisible = true;
            openTrigger.restart();
        } else {
            openTrigger.stop();
            menuCard.state = "closed";
            closeHideTimer.restart();
        }
    }

    // Keep static QsMenuOpener levels alive so parent QsMenuEntry handles stay valid and children stay 100% reactive
    QsMenuOpener {
        id: rootOpener
        menu: ShellState.trayMenuItem ? ShellState.trayMenuItem.menu : null
    }

    QsMenuOpener {
        id: subOpener1
        menu: trayMenuWin.menuStack.length >= 1 ? trayMenuWin.menuStack[0] : null
    }

    QsMenuOpener {
        id: subOpener2
        menu: trayMenuWin.menuStack.length >= 2 ? trayMenuWin.menuStack[1] : null
    }

    QsMenuOpener {
        id: subOpener3
        menu: trayMenuWin.menuStack.length >= 3 ? trayMenuWin.menuStack[2] : null
    }

    readonly property var activeOpener: menuStack.length === 0
        ? rootOpener
        : (menuStack.length === 1 ? subOpener1 : (menuStack.length === 2 ? subOpener2 : subOpener3))

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: ShellState.closeTrayMenu()
    }

    Rectangle {
        id: menuCard
        width: 224
        height: Math.min(trayMenuWin.height - 24, menuCol.implicitHeight + 12)
        x: Math.max(10, Math.min(trayMenuWin.width - width - 10, ShellState.trayMenuX - width / 2))
        y: 6

        Behavior on height {
            enabled: menuCard.state === "open"
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }

        radius: 18
        color: Theme.glassSurfaceHigh
        border.width: 1
        border.color: Theme.glassBorder
        clip: true

        transformOrigin: Item.Top
        state: "closed"
        opacity: 0.0
        scale: 0.88
        transform: Translate { id: menuTranslate; y: -8 }

        states: [
            State {
                name: "open"
                PropertyChanges { target: menuCard; opacity: 1.0; scale: 1.0 }
                PropertyChanges { target: menuTranslate; y: 0 }
            },
            State {
                name: "closed"
                PropertyChanges { target: menuCard; opacity: 0.0; scale: 0.88 }
                PropertyChanges { target: menuTranslate; y: -8 }
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
                    ScriptAction { script: { if (!trayMenuWin.isOpen) trayMenuWin.windowVisible = false; } }
                }
            }
        ]

        focus: trayMenuWin.isOpen
        Keys.onEscapePressed: {
            if (trayMenuWin.menuStack.length > 0) {
                trayMenuWin.subSlideDir = -1;
                trayMenuWin.menuStack = trayMenuWin.menuStack.slice(0, trayMenuWin.menuStack.length - 1);
                subSlideAnim.restart();
            } else {
                ShellState.closeTrayMenu();
            }
        }

        ParallelAnimation {
            id: subSlideAnim
            NumberAnimation { target: menuContentSlide; property: "x"; from: trayMenuWin.subSlideDir * 22; to: 0; duration: 190; easing.type: Easing.OutCubic }
            NumberAnimation { target: menuCol; property: "opacity"; from: 0.0; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
        }

        MouseArea { anchors.fill: parent }

        Flickable {
            anchors.fill: parent
            anchors.margins: 6
            contentHeight: menuCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: menuCol
                width: parent.width
                spacing: 2
                transform: Translate { id: menuContentSlide; x: 0 }

                // Back button when inside a submenu
                Rectangle {
                    visible: trayMenuWin.menuStack.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: 11
                    color: backM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text { text: "󰁍"; color: Theme.primary; font.family: Theme.fontMono; font.pixelSize: 14 }
                        Text {
                            Layout.fillWidth: true
                            text: "Back"
                            color: Theme.primary
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: backM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            trayMenuWin.subSlideDir = -1;
                            trayMenuWin.menuStack = trayMenuWin.menuStack.slice(0, trayMenuWin.menuStack.length - 1);
                            subSlideAnim.restart();
                        }
                    }
                }

                // DBus menu entries
                Repeater {
                    id: entriesRep
                    model: trayMenuWin.activeOpener ? trayMenuWin.activeOpener.children : null
                    onCountChanged: {
                        if (trayMenuWin.pendingSubSlide && count > 0) {
                            trayMenuWin.pendingSubSlide = false;
                            subSlideAnim.restart();
                        }
                    }

                    delegate: Item {
                        id: entryWrap
                        required property var modelData
                        readonly property bool isSep: Boolean(modelData.isSeparator)
                        readonly property bool isEnabled: modelData.enabled !== false
                        readonly property bool hasSub: Boolean(modelData.hasChildren)
                        readonly property bool isChecked: modelData.checkState === Qt.Checked

                        Layout.fillWidth: true
                        Layout.preferredHeight: isSep ? 9 : 34

                        // Separator line
                        Rectangle {
                            visible: entryWrap.isSep
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            height: 1
                            color: Theme.glassBorder
                        }

                        // Action row
                        Rectangle {
                            visible: !entryWrap.isSep
                            anchors.fill: parent
                            radius: 11
                            color: (entryWrap.isEnabled && entryM.containsMouse)
                                ? Theme.surfaceContainerHighest
                                : "transparent"
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                // Check / Radio / Icon
                                Item {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    visible: entryWrap.isChecked || Boolean(entryWrap.modelData.icon)

                                    Image {
                                        visible: Boolean(entryWrap.modelData.icon) && !entryWrap.isChecked
                                        anchors.centerIn: parent
                                        width: 14
                                        height: 14
                                        sourceSize.width: 28
                                        sourceSize.height: 28
                                        smooth: true
                                        mipmap: true
                                        source: entryWrap.modelData.icon || ""
                                    }

                                    Text {
                                        visible: entryWrap.isChecked
                                        anchors.centerIn: parent
                                        text: "󰄬"
                                        color: Theme.primary
                                        font.family: Theme.fontMono
                                        font.pixelSize: 14
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: String(entryWrap.modelData.text || "").replace(/&/g, "")
                                    color: entryWrap.isEnabled ? Theme.fgSurface : Theme.alpha(Theme.fgSurfaceVariant, 0.5)
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }

                                Text {
                                    visible: entryWrap.hasSub
                                    text: "󰅂"
                                    color: Theme.fgSurfaceVariant
                                    font.family: Theme.fontMono
                                    font.pixelSize: 14
                                }
                            }

                            MouseArea {
                                id: entryM
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: entryWrap.isEnabled
                                cursorShape: entryWrap.isEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (entryWrap.hasSub) {
                                        trayMenuWin.subSlideDir = 1;
                                        trayMenuWin.pendingSubSlide = true;
                                        trayMenuWin.menuStack = [...trayMenuWin.menuStack, entryWrap.modelData];
                                        subSlideAnim.restart();
                                    } else {
                                        entryWrap.modelData.triggered();
                                        ShellState.closeTrayMenu();
                                    }
                                }
                            }
                        }
                    }
                }

                // Divider before Hide action (root level only)
                Rectangle {
                    visible: trayMenuWin.menuStack.length === 0 && entriesRep.count > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    Layout.topMargin: 3
                    Layout.bottomMargin: 3
                    color: Theme.glassBorder
                }

                // Hide from top bar (root level only)
                Rectangle {
                    visible: trayMenuWin.menuStack.length === 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: 11
                    color: hideM.containsMouse ? Theme.alpha(Theme.error, 0.16) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: "󰈉"
                            color: hideM.containsMouse ? Theme.error : Theme.fgSurfaceVariant
                            font.family: Theme.fontMono
                            font.pixelSize: 14
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Hide from bar"
                            color: hideM.containsMouse ? Theme.error : Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: hideM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ShellState.toggleHideTray(ShellState.trayMenuId);
                            ShellState.closeTrayMenu();
                        }
                    }
                }
            }
        }
    }
}
