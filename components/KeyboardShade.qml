import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

PanelWindow {
    id: kbWin

    required property var modelData
    screen: modelData

    readonly property bool isOpen: ShellState.activeOverlay === "keyboard"
    property bool windowVisible: false
    property bool morphStart: false
    property bool morphBehaviorsEnabled: false
    property int morphSlideDir: 1
    visible: windowVisible

    Timer {
        id: morphOutTimer
        interval: 45
        onTriggered: {
            if (!kbWin.isOpen) {
                kbWin.windowVisible = false;
                card.state = "closed";
            }
        }
    }

    Timer {
        id: openTrigger
        interval: 25
        onTriggered: {
            const wasMorph = kbWin.morphStart;
            kbWin.morphBehaviorsEnabled = true;
            kbWin.morphStart = false;
            card.state = "open";
            if (wasMorph) kbSlideAnim.restart();
            ShellState.reportOverlayGeometry("keyboard", 312, card.targetH, 12);
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

    onIsOpenChanged: {
        if (isOpen) {
            morphOutTimer.stop();
            const doMorph = ShellState.overlaysShareRegion(ShellState.previousOverlay, "keyboard")
                && ShellState.morphFromW > 40 && ShellState.morphFromH > 40;
            morphBehaviorsEnabled = false;
            morphStart = doMorph;
            if (doMorph) {
                morphSlideDir = ShellState.overlaySlideDir(ShellState.previousOverlay, "keyboard");
                contentCol.opacity = 0.0;
            } else {
                contentCol.opacity = 1.0;
                kbContentSlide.x = 0;
            }
            card.state = doMorph ? "morph" : "closed";
            windowVisible = true;
            if (doMorph) morphBehaviorsEnabled = true;
            openTrigger.restart();
        } else {
            openTrigger.stop();
            if (ShellState.overlaysShareRegion("keyboard", ShellState.activeOverlay)) {
                morphOutTimer.restart();
            } else {
                card.state = "closed";
            }
        }
    }

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.closeOverlay()
    }

    // Expressive Shell / Android 17 Keyboard Layout Picker (anchored top-right)
    Rectangle {
        id: card
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: kbWin.morphStart ? ShellState.morphFromRight : 12
        width: kbWin.morphStart ? ShellState.morphFromW : 312
        readonly property real targetH: contentCol.implicitHeight + 30
        height: kbWin.morphStart ? ShellState.morphFromH : targetH
        radius: Theme.radiusExtraLarge
        color: Theme.glassSurface
        border.width: 1
        border.color: Theme.glassBorder
        clip: true

        onTargetHChanged: if (kbWin.isOpen && !kbWin.morphStart) ShellState.reportOverlayGeometry("keyboard", 312, targetH, 12)

        Behavior on anchors.rightMargin {
            enabled: kbWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }
        Behavior on width {
            enabled: kbWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }
        Behavior on height {
            enabled: kbWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }

        focus: kbWin.isOpen
        Keys.onEscapePressed: ShellState.closeOverlay()

        MouseArea { anchors.fill: parent }

        // Expressive M3E spring pop-in/out from top-right
        transformOrigin: Item.TopRight
        state: "closed"
        opacity: 0.0
        scale: 0.86
        transform: Translate { id: cardTranslate; y: -12 }

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
                PropertyChanges { target: card; opacity: 0.0; scale: 0.86 }
                PropertyChanges { target: cardTranslate; y: -12 }
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
                        script: { if (!kbWin.isOpen) kbWin.windowVisible = false; }
                    }
                }
            }
        ]

        ParallelAnimation {
            id: kbSlideAnim
            NumberAnimation { target: kbContentSlide; property: "x"; from: kbWin.morphSlideDir * 26; to: 0; duration: 210; easing.type: Easing.OutCubic }
            NumberAnimation { target: contentCol; property: "opacity"; from: 0.0; to: 1.0; duration: 170; easing.type: Easing.OutQuad }
        }

        ColumnLayout {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 15
            spacing: 14
            transform: Translate { id: kbContentSlide; x: 0 }

            // Centered "Keyboard" header with right-aligned settings gear (matches screenshot)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 30

                Text {
                    anchors.centerIn: parent
                    text: "Keyboard"
                    color: Theme.fgSurface
                    font.family: Theme.fontSans
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    radius: 15
                    color: cfgM.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰒓"
                        color: Theme.fgSurface
                        font.family: Theme.fontMono
                        font.pixelSize: 18
                    }

                    MouseArea {
                        id: cfgM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ShellState.closeOverlay();
                            Quickshell.execDetached([
                                "sh", "-c",
                                "zed ~/.config/umbriel/config.toml || xdg-open ~/.config/umbriel/config.toml"
                            ]);
                        }
                    }
                }
            }

            // Connected M3E Layout Selector Stack (active item morphs into full pill in Theme.primary)
            Column {
                id: layoutList
                Layout.fillWidth: true
                spacing: 3

                Repeater {
                    id: layoutRepeater
                    model: Umbriel.keyboardLayouts

                    delegate: Rectangle {
                        id: kbItem
                        required property string modelData
                        required property int index

                        readonly property bool isActive: index === Umbriel.currentKeyboardLayoutIndex
                        readonly property bool isFirst: index === 0
                        readonly property bool isLast: index === layoutRepeater.count - 1
                        readonly property string shortCode: Umbriel.layoutShortCode(modelData)

                        width: layoutList.width
                        height: 54

                        // Expressive Shell M3E segmented morph: active row becomes full pill (27),
                        // inactive rows keep outer 22px and inner 6px corners
                        topLeftRadius: isActive ? 27 : (isFirst ? 22 : 6)
                        topRightRadius: isActive ? 27 : (isFirst ? 22 : 6)
                        bottomLeftRadius: isActive ? 27 : (isLast ? 22 : 6)
                        bottomRightRadius: isActive ? 27 : (isLast ? 22 : 6)

                        color: isActive
                            ? Theme.primary
                            : (kbM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)

                        scale: kbM.pressed ? 0.97 : 1.0
                        Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                        Behavior on topLeftRadius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                        Behavior on topRightRadius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                        Behavior on bottomLeftRadius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                        Behavior on bottomRightRadius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            spacing: 14

                            // Short code column (e.g. GB, US, ES, あ)
                            Text {
                                Layout.preferredWidth: 26
                                horizontalAlignment: Text.AlignHCenter
                                text: kbItem.shortCode
                                color: kbItem.isActive ? Theme.fgPrimary : Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }

                            // Full layout name
                            Text {
                                Layout.fillWidth: true
                                text: kbItem.modelData
                                elide: Text.ElideRight
                                color: kbItem.isActive ? Theme.fgPrimary : Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 14
                                font.weight: kbItem.isActive ? Font.Medium : Font.DemiBold
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                        }

                        MouseArea {
                            id: kbM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Umbriel.selectKeyboardLayout(kbItem.index)
                        }
                    }
                }
            }
        }
    }
}
