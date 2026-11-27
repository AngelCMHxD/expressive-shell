import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

// Expressive-style centered floating M3 Expressive App Launcher
PanelWindow {
    id: launcherWin

    required property var modelData
    screen: modelData

    readonly property bool isOpen: ShellState.activeOverlay === "launcher"
    property bool windowVisible: false
    property bool morphStart: false
    property bool morphBehaviorsEnabled: false
    property int morphSlideDir: 1
    visible: windowVisible

    Timer {
        id: morphOutTimer
        interval: 45
        onTriggered: {
            if (!launcherWin.isOpen) {
                launcherWin.windowVisible = false;
                card.state = "closed";
            }
        }
    }

    Timer {
        id: openTrigger
        interval: 25
        onTriggered: {
            const wasMorph = launcherWin.morphStart;
            launcherWin.morphBehaviorsEnabled = true;
            launcherWin.morphStart = false;
            card.state = "open";
            if (wasMorph) launcherSlideAnim.restart();
            ShellState.reportOverlayGeometry("launcher", 648, 510, 0);
            searchInput.forceActiveFocus();
        }
    }

    Timer {
        id: closeHideTimer
        interval: 160
        onTriggered: {
            if (!launcherWin.isOpen) launcherWin.windowVisible = false;
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

    WlrLayershell.namespace: "expressive-launcher"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property string query: ""
    property int selectedIdx: 0
    property var appLookup: ({})

    // Incremental ListModel so GridView add/remove/move transitions animate smoothly while typing
    ListModel {
        id: appModel
    }

    function computeFiltered() {
        const all = DesktopEntries.applications.values || [];
        const q = query.trim().toLowerCase();
        const items = [];
        const lookup = {};
        for (let i = 0; i < all.length; i++) {
            const app = all[i];
            if (!app || app.noDisplay) continue;
            lookup[app.id] = app;
            if (q.length > 0) {
                const name = (app.name || "").toLowerCase();
                const generic = (app.genericName || "").toLowerCase();
                const comment = (app.comment || "").toLowerCase();
                const id = (app.id || "").toLowerCase();
                if (!name.includes(q) && !generic.includes(q) && !comment.includes(q) && !id.includes(q)) {
                    continue;
                }
            }
            items.push(app);
        }
        items.sort((a, b) => {
            if (q.length > 0) {
                const aStarts = (a.name || "").toLowerCase().startsWith(q) ? 0 : 1;
                const bStarts = (b.name || "").toLowerCase().startsWith(q) ? 0 : 1;
                if (aStarts !== bStarts) return aStarts - bStarts;
            }
            return (a.name || "").localeCompare(b.name || "");
        });
        appLookup = lookup;
        return items;
    }

    function syncApps() {
        const next = computeFiltered();
        const nextIds = new Set(next.map(a => a.id));

        // 1. Remove items no longer matching (triggers GridView.remove transition)
        for (let i = appModel.count - 1; i >= 0; i--) {
            if (!nextIds.has(appModel.get(i).appId)) {
                appModel.remove(i);
            }
        }

        // 2. Insert new items or move existing items into sorted position
        for (let targetIdx = 0; targetIdx < next.length; targetIdx++) {
            const app = next[targetIdx];
            const iconPath = (app.icon && Quickshell.iconPath(app.icon, true))
                || Umbriel.iconForAppId(app.id);

            let curIdx = -1;
            for (let j = targetIdx; j < appModel.count; j++) {
                if (appModel.get(j).appId === app.id) {
                    curIdx = j;
                    break;
                }
            }

            if (curIdx === -1) {
                appModel.insert(targetIdx, {
                    appId: app.id,
                    appName: app.name || app.id,
                    appIcon: iconPath
                });
            } else if (curIdx !== targetIdx) {
                appModel.move(curIdx, targetIdx, 1);
            }
        }
    }

    Component.onCompleted: syncApps()

    onIsOpenChanged: {
        if (isOpen) {
            closeHideTimer.stop();
            morphOutTimer.stop();
            if (query !== "" || appModel.count === 0) {
                query = "";
                searchInput.text = "";
                syncApps();
            }
            selectedIdx = 0;
            appGrid.contentY = 0;
            const doMorph = ShellState.overlaysShareRegion(ShellState.previousOverlay, "launcher")
                && ShellState.morphFromW > 40 && ShellState.morphFromH > 40;
            morphBehaviorsEnabled = false;
            morphStart = doMorph;
            if (doMorph) {
                morphSlideDir = ShellState.overlaySlideDir(ShellState.previousOverlay, "launcher");
                launcherContentCol.opacity = 0.0;
            } else {
                launcherContentCol.opacity = 1.0;
                launcherContentSlide.x = 0;
            }
            card.state = doMorph ? "morph" : "closed";
            windowVisible = true;
            if (doMorph) morphBehaviorsEnabled = true;
            openTrigger.restart();
        } else {
            openTrigger.stop();
            if (ShellState.overlaysShareRegion("launcher", ShellState.activeOverlay)) {
                morphOutTimer.restart();
            } else {
                card.state = "closed";
                closeHideTimer.restart();
            }
        }
    }

    onQueryChanged: {
        selectedIdx = 0;
        syncApps();
    }

    function launchById(appId) {
        const app = appLookup[appId];
        ShellState.closeOverlay();
        if (app) app.execute();
    }

    function launchSelected() {
        if (appModel.count === 0) return;
        const idx = Math.max(0, Math.min(selectedIdx, appModel.count - 1));
        launchById(appModel.get(idx).appId);
    }

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.closeOverlay()
    }

    // Centered floating M3E Launcher Card (Expressive proportions)
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: ShellState.dockMode === "popup" ? 76 : 18
        width: launcherWin.morphStart ? ShellState.morphFromW : 648
        height: launcherWin.morphStart ? ShellState.morphFromH : 510
        radius: Theme.radiusExtraLarge
        color: Theme.glassSurface
        border.width: 1
        border.color: Theme.glassBorder
        clip: true

        Behavior on width {
            enabled: launcherWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }
        Behavior on height {
            enabled: launcherWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }

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
                        script: { if (!launcherWin.isOpen) launcherWin.windowVisible = false; }
                    }
                }
            }
        ]

        ParallelAnimation {
            id: launcherSlideAnim
            NumberAnimation { target: launcherContentSlide; property: "x"; from: launcherWin.morphSlideDir * 28; to: 0; duration: 210; easing.type: Easing.OutCubic }
            NumberAnimation { target: launcherContentCol; property: "opacity"; from: 0.0; to: 1.0; duration: 170; easing.type: Easing.OutQuad }
        }

        ColumnLayout {
            id: launcherContentCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16
            transform: Translate { id: launcherContentSlide; x: 0 }

            // Pill Search Bar (matches Expressive launcher header)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                radius: Theme.radiusPill
                color: Theme.surfaceContainerHigh
                border.width: searchInput.activeFocus ? 1.5 : 1
                border.color: searchInput.activeFocus ? Theme.primary : Theme.glassBorder

                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 10

                    Text {
                        text: "󰍉"
                        color: Theme.primary
                        font.family: Theme.fontMono
                        font.pixelSize: 17
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        color: Theme.fgSurface
                        selectionColor: Theme.primaryContainer
                        selectedTextColor: Theme.fgPrimaryContainer
                        font.family: Theme.fontSans
                        font.pixelSize: 14
                        clip: true

                        onTextChanged: launcherWin.query = text

                        Keys.onEscapePressed: ShellState.closeOverlay()
                        Keys.onReturnPressed: launcherWin.launchSelected()
                        Keys.onEnterPressed: launcherWin.launchSelected()
                        Keys.onRightPressed: {
                            if (launcherWin.selectedIdx + 1 < appModel.count) {
                                launcherWin.selectedIdx++;
                                appGrid.positionViewAtIndex(launcherWin.selectedIdx, GridView.Contain);
                            }
                        }
                        Keys.onLeftPressed: {
                            if (launcherWin.selectedIdx > 0) {
                                launcherWin.selectedIdx--;
                                appGrid.positionViewAtIndex(launcherWin.selectedIdx, GridView.Contain);
                            }
                        }
                        Keys.onDownPressed: {
                            const next = Math.min(appModel.count - 1, launcherWin.selectedIdx + 6);
                            if (next >= 0) {
                                launcherWin.selectedIdx = next;
                                appGrid.positionViewAtIndex(launcherWin.selectedIdx, GridView.Contain);
                            }
                        }
                        Keys.onUpPressed: {
                            const prev = Math.max(0, launcherWin.selectedIdx - 6);
                            launcherWin.selectedIdx = prev;
                            appGrid.positionViewAtIndex(launcherWin.selectedIdx, GridView.Contain);
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text.length === 0
                            text: "Search apps..."
                            color: Theme.fgSurfaceVariant
                            font.family: Theme.fontSans
                            font.pixelSize: 14
                        }
                    }

                    // Clear button
                    Rectangle {
                        visible: searchInput.text.length > 0
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 12
                        color: clrM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                        Text { anchors.centerIn: parent; text: "󰅖"; color: Theme.fgSurfaceVariant; font.family: Theme.fontMono; font.pixelSize: 13 }
                        MouseArea {
                            id: clrM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchInput.text = ""
                        }
                    }
                }
            }

            // 6-column Expressive App Grid with pop-in/out & reflow transitions
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                GridView {
                    id: appGrid
                    anchors.fill: parent
                    anchors.rightMargin: 8
                    clip: true
                    cellWidth: Math.floor(width / 6)
                    cellHeight: 88
                    model: appModel
                    boundsBehavior: Flickable.StopAtBounds

                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 150; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; from: 0.65; to: 1.0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.35 }
                        }
                    }

                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 0.0; duration: 130; easing.type: Easing.InCubic }
                            NumberAnimation { property: "scale"; to: 0.65; duration: 140; easing.type: Easing.InCubic }
                        }
                    }

                    move: Transition {
                        NumberAnimation { properties: "x,y"; duration: 190; easing.type: Easing.OutCubic }
                    }

                    displaced: Transition {
                        NumberAnimation { properties: "x,y"; duration: 190; easing.type: Easing.OutCubic }
                    }

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
                        id: appCell
                        required property string appId
                        required property string appName
                        required property string appIcon
                        required property int index
                        readonly property bool isSelected: index === launcherWin.selectedIdx

                        width: appGrid.cellWidth
                        height: appGrid.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: Theme.radiusMedium
                            color: appCell.isSelected
                                ? Theme.alpha(Theme.primaryContainer, 0.85)
                                : (cellMouse.containsMouse ? Theme.alpha(Theme.surfaceContainerHigh, 0.8) : "transparent")

                            scale: cellMouse.pressed ? 0.92 : (cellMouse.containsMouse ? 1.06 : 1.0)
                            Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                spacing: 6

                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 42
                                    height: 42
                                    sourceSize.width: 84
                                    sourceSize.height: 84
                                    smooth: true
                                    mipmap: true
                                    source: appCell.appIcon
                                }

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: appCell.appName
                                    color: appCell.isSelected ? Theme.fgPrimaryContainer : Theme.fgSurface
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    font.weight: appCell.isSelected ? Font.DemiBold : Font.Normal
                                }
                            }
                        }

                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onEntered: launcherWin.selectedIdx = appCell.index
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    const pt = appCell.mapToItem(null, mouse.x, mouse.y);
                                    ShellState.openAppMenu(appCell.appId, appCell.appName, pt.x, pt.y, false);
                                } else {
                                    launcherWin.launchById(appCell.appId);
                                }
                            }
                        }
                    }
                }

                // Empty search state
                Text {
                    anchors.centerIn: parent
                    visible: appModel.count === 0
                    text: "No matching apps"
                    color: Theme.fgSurfaceVariant
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                }
            }
        }
    }
}
