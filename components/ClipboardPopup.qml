import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"

// M3 Expressive Clipboard History Popup (backed by cliphist + wl-copy)
PanelWindow {
    id: clipWin

    required property var modelData
    screen: modelData

    readonly property bool isOpen: ShellState.activeOverlay === "clipboard"
    property bool windowVisible: false
    visible: windowVisible

    Timer {
        id: openTrigger
        interval: 25
        onTriggered: {
            card.state = "open";
            clipSearch.forceActiveFocus();
        }
    }

    // Safety timer so the Wayland layer surface ALWAYS unmaps after closing
    Timer {
        id: closeHideTimer
        interval: 160
        onTriggered: {
            if (!clipWin.isOpen) clipWin.windowVisible = false;
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

    WlrLayershell.namespace: "expressive-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property bool hasCliphist: true
    property var rawEntries: []
    property string query: ""

    readonly property var filteredEntries: {
        const q = query.trim().toLowerCase();
        if (!q) return rawEntries;
        return rawEntries.filter(e => e.preview.toLowerCase().includes(q));
    }

    property var _buf: []

    Process {
        id: listProc
        command: ["sh", "-c", "command -v cliphist >/dev/null 2>&1 || { echo '__MISSING__'; exit 0; }; cliphist list | head -n 60"]
        stdout: SplitParser {
            onRead: line => {
                if (line === "__MISSING__") {
                    clipWin.hasCliphist = false;
                    return;
                }
                const tab = line.indexOf("\t");
                if (tab > 0) {
                    clipWin._buf.push({
                        raw: line,
                        id: line.slice(0, tab),
                        preview: line.slice(tab + 1).trim()
                    });
                }
            }
        }
        onExited: {
            clipWin.rawEntries = clipWin._buf;
            clipWin._buf = [];
        }
    }

    onIsOpenChanged: {
        if (isOpen) {
            closeHideTimer.stop();
            query = "";
            clipSearch.text = "";
            hasCliphist = true;
            _buf = [];
            listProc.running = true;
            card.state = "closed";
            windowVisible = true;
            openTrigger.restart();
        } else {
            openTrigger.stop();
            card.state = "closed";
            closeHideTimer.restart();
        }
    }

    function pickEntry(entry) {
        if (!entry) return;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "_", entry.raw]);
        ShellState.closeOverlay();
    }

    function wipeHistory() {
        Quickshell.execDetached(["cliphist", "wipe"]);
        rawEntries = [];
    }

    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.closeOverlay()
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: 12
        width: 440
        height: 460
        radius: Theme.radiusExtraLarge
        color: Theme.glassSurface
        border.width: 1
        border.color: Theme.glassBorder

        MouseArea { anchors.fill: parent }

        transformOrigin: Item.Top
        state: "closed"
        opacity: 0.0
        scale: 0.92
        transform: Translate { id: cardTranslate; y: -16 }

        states: [
            State {
                name: "open"
                PropertyChanges { target: card; opacity: 1.0; scale: 1.0 }
                PropertyChanges { target: cardTranslate; y: 0 }
            },
            State {
                name: "closed"
                PropertyChanges { target: card; opacity: 0.0; scale: 0.92 }
                PropertyChanges { target: cardTranslate; y: -16 }
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
                        script: { if (!clipWin.isOpen) clipWin.windowVisible = false; }
                    }
                }
            }
        ]

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "󰅌  Clipboard"
                    color: Theme.fgSurface
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: clipWin.hasCliphist && clipWin.rawEntries.length > 0
                    Layout.preferredHeight: 26
                    Layout.preferredWidth: wipeTxt.implicitWidth + 16
                    radius: Theme.radiusPill
                    color: wipeM.containsMouse ? Theme.error : Theme.surfaceContainerHigh

                    Text {
                        id: wipeTxt
                        anchors.centerIn: parent
                        text: "Clear all"
                        color: wipeM.containsMouse ? Theme.fgError : Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: wipeM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: clipWin.wipeHistory()
                    }
                }
            }

            // Search pill
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Theme.radiusPill
                color: Theme.surfaceContainerHigh
                border.width: clipSearch.activeFocus ? 1.5 : 1
                border.color: clipSearch.activeFocus ? Theme.primary : Theme.glassBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8

                    Text { text: "󰍉"; color: Theme.primary; font.family: Theme.fontMono; font.pixelSize: 15 }

                    TextInput {
                        id: clipSearch
                        Layout.fillWidth: true
                        color: Theme.fgSurface
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        clip: true
                        onTextChanged: clipWin.query = text
                        Keys.onEscapePressed: ShellState.closeOverlay()
                        Keys.onReturnPressed: {
                            if (clipWin.filteredEntries.length > 0) clipWin.pickEntry(clipWin.filteredEntries[0]);
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: clipSearch.text.length === 0
                            text: "Filter clipboard..."
                            color: Theme.fgSurfaceVariant
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                        }
                    }
                }
            }

            // Missing cliphist hint
            Rectangle {
                visible: !clipWin.hasCliphist
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusLarge
                color: Theme.surfaceContainerHigh

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    spacing: 6

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "cliphist not installed yet"
                        color: Theme.fgSurface
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Install cliphist & wl-clipboard and start wl-paste --watch cliphist store to enable history."
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                    }
                }
            }

            // Clipboard entries list
            ListView {
                visible: clipWin.hasCliphist
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: clipWin.filteredEntries
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    implicitHeight: Math.min(64, entryTxt.implicitHeight + 20)
                    height: implicitHeight
                    radius: Theme.radiusMedium
                    color: itemM.containsMouse ? Theme.primaryContainer : Theme.surfaceContainerHigh

                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        id: entryTxt
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 12
                        text: modelData.preview
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: itemM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurface
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: itemM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: clipWin.pickEntry(modelData)
                    }
                }
            }
        }
    }
}
