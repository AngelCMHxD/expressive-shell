import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

// M3 Expressive Desktop Widget on the wallpaper layer (inspired by Expressive Shell)
PanelWindow {
    id: widgetWin

    required property var modelData
    screen: modelData

    visible: ShellState.desktopWidgetsVisible

    anchors {
        top: true
        left: true
    }

    margins {
        top: 52
        left: 24
    }

    implicitWidth: 244
    implicitHeight: 286
    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.namespace: "expressive-widget"
    // Bottom layer is strictly above Background (wallpapers/awww) and strictly below app windows
    WlrLayershell.layer: WlrLayer.Bottom

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusExtraLarge
        color: Theme.glassSurface
        border.width: 1
        border.color: Theme.glassBorder

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            // Header label
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: SystemStatus.weekdayFull
                color: Theme.fgSurfaceVariant
                font.family: Theme.fontSans
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            // M3 Expressive Scalloped Cookie Badge
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 132
                Layout.preferredHeight: 132

                Canvas {
                    id: scallopCanvas
                    anchors.fill: parent
                    property color fillColor: Theme.primaryContainer

                    onFillColorChanged: requestPaint()
                    onWidthChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        const cx = width / 2;
                        const cy = height / 2;
                        const baseR = Math.min(width, height) * 0.43;
                        const amp = baseR * 0.095;
                        const lobes = 10;
                        const steps = 180;

                        ctx.beginPath();
                        for (let i = 0; i <= steps; i++) {
                            const t = (i / steps) * Math.PI * 2;
                            const r = baseR + amp * Math.cos(lobes * t);
                            const x = cx + r * Math.cos(t);
                            const y = cy + r * Math.sin(t);
                            if (i === 0) ctx.moveTo(x, y);
                            else ctx.lineTo(x, y);
                        }
                        ctx.closePath();
                        ctx.fillStyle = fillColor;
                        ctx.fill();
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: -2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: SystemStatus.dayNumber
                        color: Theme.fgPrimaryContainer
                        font.family: Theme.fontSans
                        font.pixelSize: 42
                        font.weight: Font.Bold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: SystemStatus.timeShort
                        color: Theme.alpha(Theme.fgPrimaryContainer, 0.85)
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }
            }

            // Subtitle
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: SystemStatus.monthDay + "  ·  " + Umbriel.windows.length + " open"
                color: Theme.fgSurface
                font.family: Theme.fontSans
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            Item { Layout.fillHeight: true }

            // Bottom quick-action icon pills (matching Expressive widget footer)
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                // Toggle Dark / Light M3 palette
                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: darkMouse.pressed ? 12 : 19
                    color: darkMouse.containsMouse ? Theme.primaryContainer : Theme.surfaceContainerHigh

                    scale: darkMouse.pressed ? 0.9 : 1.0
                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on radius { NumberAnimation { duration: Motion.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: ShellState.darkMode ? "󰖨" : "󰖔"
                        color: Theme.fgSurface
                        font.family: Theme.fontMono
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: darkMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.darkMode = !ShellState.darkMode
                    }
                }

                // Cycle Dock Mode
                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: dockBtnMouse.pressed ? 12 : 19
                    color: dockBtnMouse.containsMouse ? Theme.primaryContainer : Theme.surfaceContainerHigh

                    scale: dockBtnMouse.pressed ? 0.9 : 1.0
                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on radius { NumberAnimation { duration: Motion.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰘔"
                        color: Theme.fgSurface
                        font.family: Theme.fontMono
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: dockBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.cycleDockMode()
                    }
                }

                // Umbriel Overview
                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: ovMouse.pressed ? 12 : 19
                    color: ovMouse.containsMouse ? Theme.primaryContainer : Theme.surfaceContainerHigh

                    scale: ovMouse.pressed ? 0.9 : 1.0
                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on radius { NumberAnimation { duration: Motion.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰕰"
                        color: Theme.fgSurface
                        font.family: Theme.fontMono
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: ovMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Umbriel.toggleOverview()
                    }
                }
            }
        }
    }
}
