import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../theme"
import "../services"

// M3 Expressive Wallpaper Picker with Static (1st-frame) vs Animated (awww) toggle
PanelWindow {
    id: pickerWin

    required property var modelData
    screen: modelData

    readonly property bool isOpen: ShellState.activeOverlay === "wallpapers"
    property bool windowVisible: false
    property bool morphStart: false
    property bool morphBehaviorsEnabled: false
    property int morphSlideDir: 1
    visible: windowVisible

    Timer {
        id: morphOutTimer
        interval: 45
        onTriggered: {
            if (!pickerWin.isOpen) {
                pickerWin.windowVisible = false;
                card.state = "closed";
            }
        }
    }

    Timer {
        id: closeHideTimer
        interval: 160
        onTriggered: {
            if (!pickerWin.isOpen) pickerWin.windowVisible = false;
        }
    }

    Timer {
        id: openTrigger
        interval: 25
        onTriggered: {
            const wasMorph = pickerWin.morphStart;
            pickerWin.morphBehaviorsEnabled = true;
            pickerWin.morphStart = false;
            card.state = "open";
            if (wasMorph) pickerSlideAnim.restart();
            ShellState.reportOverlayGeometry("wallpapers", 720, 490, 0);
        }
    }

    onIsOpenChanged: {
        if (isOpen) {
            closeHideTimer.stop();
            morphOutTimer.stop();
            Wallpaper.refreshList();
            const doMorph = ShellState.overlaysShareRegion(ShellState.previousOverlay, "wallpapers")
                && ShellState.morphFromW > 40 && ShellState.morphFromH > 40;
            morphBehaviorsEnabled = false;
            morphStart = doMorph;
            if (doMorph) {
                morphSlideDir = ShellState.overlaySlideDir(ShellState.previousOverlay, "wallpapers");
                pickerContentCol.opacity = 0.0;
            } else {
                pickerContentCol.opacity = 1.0;
                pickerContentSlide.x = 0;
            }
            card.state = doMorph ? "morph" : "closed";
            windowVisible = true;
            if (doMorph) morphBehaviorsEnabled = true;
            openTrigger.restart();
        } else {
            openTrigger.stop();
            if (ShellState.overlaysShareRegion("wallpapers", ShellState.activeOverlay)) {
                morphOutTimer.restart();
            } else {
                card.state = "closed";
                closeHideTimer.restart();
            }
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

    WlrLayershell.namespace: "expressive-wallpapers"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.closeOverlay()
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: ShellState.dockMode === "popup" ? 76 : 18
        width: pickerWin.morphStart ? ShellState.morphFromW : 720
        height: pickerWin.morphStart ? ShellState.morphFromH : 490
        radius: Theme.radiusExtraLarge
        color: Theme.glassSurface
        border.width: 1
        border.color: Theme.glassBorder
        clip: true

        Behavior on width {
            enabled: pickerWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }
        Behavior on height {
            enabled: pickerWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }

        focus: pickerWin.isOpen
        Keys.onEscapePressed: ShellState.closeOverlay()

        MouseArea { anchors.fill: parent }

        transformOrigin: Item.Bottom
        state: "closed"
        opacity: 0.0
        scale: 0.88
        transform: Translate { id: cardTranslate; y: 16 }

        states: [
            State {
                name: "morph"
                PropertyChanges { target: card; opacity: 1.0; scale: 1.0 }
                PropertyChanges { target: cardTranslate; y: 0 }
            },
            State {
                name: "open"
                PropertyChanges { target: card; opacity: 1.0; scale: 1.0 }
                PropertyChanges { target: cardTranslate; y: 0 }
            },
            State {
                name: "closed"
                PropertyChanges { target: card; opacity: 0.0; scale: 0.88 }
                PropertyChanges { target: cardTranslate; y: 16 }
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
                        script: { if (!pickerWin.isOpen) pickerWin.windowVisible = false; }
                    }
                }
            }
        ]

        ParallelAnimation {
            id: pickerSlideAnim
            NumberAnimation { target: pickerContentSlide; property: "x"; from: pickerWin.morphSlideDir * 28; to: 0; duration: 210; easing.type: Easing.OutCubic }
            NumberAnimation { target: pickerContentCol; property: "opacity"; from: 0.0; to: 1.0; duration: 170; easing.type: Easing.OutQuad }
        }

        ColumnLayout {
            id: pickerContentCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14
            transform: Translate { id: pickerContentSlide; x: 0 }

            // Header bar with Static/awww toggle, Auto-rotate toggle, and Shuffle
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                z: 20

                Text {
                    text: "󰸉  Wallpapers"
                    color: Theme.fgSurface
                    font.family: Theme.fontSans
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                // Static (Battery Saver) vs Animated (awww) toggle pill — greys out with tooltip if awww is not installed
                Rectangle {
                    Layout.preferredHeight: 30
                    Layout.preferredWidth: awwwRow.implicitWidth + 20
                    radius: (ShellState.hasAwww && Wallpaper.useAwww) ? 15 : 9
                    color: (ShellState.hasAwww && Wallpaper.useAwww) ? Theme.primaryContainer : Theme.surfaceContainerHigh
                    opacity: ShellState.hasAwww ? 1.0 : 0.48

                    Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Rectangle {
                        visible: !ShellState.hasAwww && awwwM.containsMouse
                        z: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 6
                        width: awwwTipTxt.implicitWidth + 18
                        height: awwwTipTxt.implicitHeight + 10
                        radius: 10
                        color: Theme.surfaceContainerHighest
                        border.width: 1
                        border.color: Theme.glassBorder

                        Text {
                            id: awwwTipTxt
                            anchors.centerIn: parent
                            text: "Install `awww` for animated wallpapers"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                    }

                    RowLayout {
                        id: awwwRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: (ShellState.hasAwww && Wallpaper.useAwww) ? "󰐊" : "󰏤"
                            color: (ShellState.hasAwww && Wallpaper.useAwww) ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                        }
                        Text {
                            text: (ShellState.hasAwww && Wallpaper.useAwww) ? "Animated (awww)" : "Static (1st frame)"
                            color: (ShellState.hasAwww && Wallpaper.useAwww) ? Theme.fgPrimaryContainer : Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: awwwM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: ShellState.hasAwww ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (ShellState.hasAwww) Wallpaper.toggleAwww();
                        }
                    }
                }

                // Auto-rotate toggle pill
                Rectangle {
                    Layout.preferredHeight: 30
                    Layout.preferredWidth: rotTxt.implicitWidth + 20
                    radius: Wallpaper.autoRotate ? 15 : 9
                    color: Wallpaper.autoRotate ? Theme.primaryContainer : Theme.surfaceContainerHigh

                    Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        id: rotTxt
                        anchors.centerIn: parent
                        text: Wallpaper.autoRotate ? "󰑖 Rotate On" : "󰑖 Rotate Off"
                        color: Wallpaper.autoRotate ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Wallpaper.autoRotate = !Wallpaper.autoRotate
                    }
                }

                // Shuffle button
                Rectangle {
                    Layout.preferredHeight: 30
                    Layout.preferredWidth: 30
                    radius: 15
                    color: shufM.containsMouse ? Theme.primary : Theme.surfaceContainerHigh

                    scale: shufM.pressed ? 0.9 : 1.0
                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒟"
                        color: shufM.containsMouse ? Theme.fgPrimary : Theme.fgSurface
                        font.family: Theme.fontMono
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: shufM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Wallpaper.randomNext()
                    }
                }
            }

            // 3-column wallpaper thumbnail grid
            GridView {
                id: wpGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: Math.floor((width - 8) / 3)
                cellHeight: 136
                model: Wallpaper.wallpapers
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 5
                    contentItem: Rectangle {
                        implicitWidth: 5
                        radius: 3
                        color: Theme.primary
                        opacity: 0.75
                    }
                    background: Item {}
                }

                delegate: Item {
                    id: wpCell
                    required property string modelData
                    readonly property bool isCurrent: modelData === Wallpaper.currentWallpaper
                    readonly property bool isAnim: Wallpaper.isAnimatedFile(modelData)

                    width: wpGrid.cellWidth
                    height: wpGrid.cellHeight

                    // ClippingRectangle properly rounds child Images to the corner radius!
                    ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: 6
                        radius: Theme.radiusMedium
                        color: Theme.surfaceContainerHigh
                        contentUnderBorder: false

                        scale: cellM.pressed ? 0.95 : (cellM.containsMouse ? 1.03 : 1.0)
                        Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }

                        border.width: wpCell.isCurrent ? 2.5 : 1
                        border.color: wpCell.isCurrent ? Theme.primary : Theme.glassBorder
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        // Always static 1st-frame thumbnail (fast & low memory)
                        Image {
                            anchors.fill: parent
                            source: "file://" + wpCell.modelData
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 320
                            sourceSize.height: 180
                            asynchronous: true
                            smooth: true
                        }

                        // GIF / WebP badge
                        Rectangle {
                            visible: wpCell.isAnim
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: 8
                            height: 18
                            width: badgeTxt.implicitWidth + 10
                            radius: 6
                            color: Theme.alpha(Theme.surface, 0.78)

                            Text {
                                id: badgeTxt
                                anchors.centerIn: parent
                                text: "GIF"
                                color: Theme.primary
                                font.family: Theme.fontSans
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                        }

                        // Active checkmark pill
                        Rectangle {
                            visible: wpCell.isCurrent
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 8
                            width: 22
                            height: 22
                            radius: 11
                            color: Theme.primary

                            Text {
                                anchors.centerIn: parent
                                text: "󰄬"
                                color: Theme.fgPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: 13
                            }
                        }

                        // Bottom filename scrim
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 26
                            color: Theme.alpha(Theme.surface, 0.72)

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                text: Wallpaper.displayName(wpCell.modelData)
                                color: Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                font.weight: wpCell.isCurrent ? Font.DemiBold : Font.Normal
                            }
                        }

                        MouseArea {
                            id: cellM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Wallpaper.applyWallpaper(wpCell.modelData, true)
                        }
                    }
                }
            }
        }
    }
}
