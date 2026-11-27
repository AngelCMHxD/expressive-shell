import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

PanelWindow {
    id: osdWin

    required property var modelData
    screen: modelData

    property bool armed: false
    property bool showing: false
    property bool windowVisible: false
    property string osdIcon: "󰕾"
    property string osdLabel: ""
    property real osdValue: 0
    property bool osdIsMuted: false

    visible: windowVisible

    Timer { id: openTrigger; interval: 25; onTriggered: pill.state = "open" }

    anchors {
        bottom: true
    }

    margins {
        bottom: ShellState.dockMode === "popup" ? 72 : (ShellState.dockMode === "always" ? 8 : 16)
    }

    implicitWidth: 264
    implicitHeight: 68
    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.namespace: "expressive-shade"
    WlrLayershell.layer: WlrLayer.Overlay

    // Avoid flashing on startup/reload while PipeWire / brightnessctl initialize
    property real lastBrightness: SystemStatus.brightness
    Timer {
        interval: 2200
        running: true
        onTriggered: {
            osdWin.lastBrightness = SystemStatus.brightness;
            osdWin.armed = true;
        }
    }

    Timer {
        id: hideTimer
        interval: 1600
        onTriggered: {
            osdWin.showing = false;
            openTrigger.stop();
            pill.state = "closed";
        }
    }

    function trigger(icon, val, muted, label) {
        if (!armed) return;
        osdIcon = icon;
        osdValue = Math.max(0, Math.min(1, val));
        osdIsMuted = muted;
        osdLabel = label || (Math.round(osdValue * 100) + "%");
        const wasHidden = !windowVisible;
        showing = true;
        if (wasHidden) {
            pill.state = "closed";
            windowVisible = true;
            openTrigger.restart();
        } else {
            openTrigger.stop();
            pill.state = "open";
        }
        hideTimer.restart();
    }

    Connections {
        target: SystemStatus
        function onVolumeChanged() {
            osdWin.trigger(
                SystemStatus.muted ? "󰖁" : (SystemStatus.volume > 0.5 ? "󰕾" : "󰖀"),
                SystemStatus.volume,
                SystemStatus.muted,
                ""
            );
        }
        function onMutedChanged() {
            osdWin.trigger(
                SystemStatus.muted ? "󰖁" : "󰕾",
                SystemStatus.volume,
                SystemStatus.muted,
                SystemStatus.muted ? "Muted" : ""
            );
        }
        function onMicMutedChanged() {
            osdWin.trigger(
                SystemStatus.micMuted ? "󰍭" : "󰍬",
                SystemStatus.micMuted ? 0 : 1,
                SystemStatus.micMuted,
                SystemStatus.micMuted ? "Mic off" : "Mic on"
            );
        }
        function onBrightnessChanged() {
            if (!osdWin.armed) {
                osdWin.lastBrightness = SystemStatus.brightness;
                return;
            }
            if (Math.abs(SystemStatus.brightness - osdWin.lastBrightness) < 0.015) return;
            osdWin.lastBrightness = SystemStatus.brightness;
            osdWin.trigger("󰃠", SystemStatus.brightness, false, "");
        }
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        width: 224
        height: 44
        radius: Theme.radiusPill
        color: Theme.glassSurfaceHigh
        border.width: 1
        border.color: Theme.glassBorder

        transformOrigin: Item.Bottom
        state: "closed"
        opacity: 0.0
        scale: 0.84
        transform: Translate { id: pillTranslate; y: 14 }

        states: [
            State {
                name: "open"
                PropertyChanges { target: pill; opacity: 1.0; scale: 1.0 }
                PropertyChanges { target: pillTranslate; y: 0 }
            },
            State {
                name: "closed"
                PropertyChanges { target: pill; opacity: 0.0; scale: 0.84 }
                PropertyChanges { target: pillTranslate; y: 14 }
            }
        ]

        transitions: [
            Transition {
                from: "closed"; to: "open"
                ParallelAnimation {
                    NumberAnimation { target: pill; property: "opacity"; from: 0.0; to: 1.0; duration: 45; easing.type: Easing.OutQuad }
                    SpringAnimation { target: pill; property: "scale"; spring: 7.5; damping: 0.36; epsilon: 0.004 }
                    SpringAnimation { target: pillTranslate; property: "y"; spring: 7.5; damping: 0.36; epsilon: 0.004 }
                }
            },
            Transition {
                from: "open"; to: "closed"
                SequentialAnimation {
                    ParallelAnimation {
                        NumberAnimation { target: pill; property: "opacity"; duration: 120; easing.type: Easing.OutQuad }
                        NumberAnimation { target: pill; property: "scale"; duration: 130; easing.type: Easing.InCubic }
                        NumberAnimation { target: pillTranslate; property: "y"; duration: 130; easing.type: Easing.InCubic }
                    }
                    ScriptAction {
                        script: { if (!osdWin.showing) osdWin.windowVisible = false; }
                    }
                }
            }
        ]

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            Text {
                text: osdWin.osdIcon
                color: osdWin.osdIsMuted ? Theme.error : Theme.primary
                font.family: Theme.fontMono
                font.pixelSize: 16
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 8
                radius: 4
                color: Theme.surfaceContainerHighest
                clip: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * osdWin.osdValue
                    radius: 4
                    color: osdWin.osdIsMuted ? Theme.outlineVariant : Theme.primary

                    Behavior on width {
                        SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping }
                    }
                }
            }

            Text {
                Layout.preferredWidth: 42
                horizontalAlignment: Text.AlignRight
                text: osdWin.osdLabel
                color: Theme.fgSurface
                font.family: Theme.fontSans
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }
    }
}
