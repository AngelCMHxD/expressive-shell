import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../theme"
import "../services"

PanelWindow {
    id: bar

    required property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 34
    exclusiveZone: 34
    color: "transparent"

    WlrLayershell.namespace: "expressive-topbar"
    WlrLayershell.layer: WlrLayer.Top

    readonly property string outputName: modelData ? modelData.name : ""
    readonly property bool isMaximized: Umbriel.hasMaximizedOnOutput(outputName)

    // Stable ListModel of workspaces for this output so delegates stay alive
    // across workspace switches and morph smoothly with SpringAnimation
    ListModel {
        id: wsModel
    }
    property bool firstWsActive: false
    property bool lastWsActive: false

    function syncWorkspaces() {
        const list = Umbriel.workspacesForOutput(outputName);
        firstWsActive = list.length > 0 && Boolean(list[0].active);
        lastWsActive = list.length > 0 && Boolean(list[list.length - 1].active);
        // Update in-place if IDs match, otherwise reconcile minimal changes
        let sameIds = list.length === wsModel.count;
        if (sameIds) {
            for (let i = 0; i < list.length; i++) {
                if (wsModel.get(i).wsId !== list[i].id) {
                    sameIds = false;
                    break;
                }
            }
        }
        if (sameIds) {
            for (let i = 0; i < list.length; i++) {
                const w = list[i];
                wsModel.setProperty(i, "wsIndex", w.index);
                wsModel.setProperty(i, "active", Boolean(w.active));
                wsModel.setProperty(i, "occupied", Boolean(w.occupied));
            }
        } else {
            wsModel.clear();
            for (const w of list) {
                wsModel.append({
                    wsId: w.id,
                    wsIndex: w.index,
                    active: Boolean(w.active),
                    occupied: Boolean(w.occupied)
                });
            }
        }
    }

    Connections {
        target: Umbriel
        function onWorkspacesChanged() { bar.syncWorkspaces(); }
    }

    Component.onCompleted: syncWorkspaces()

    // Android-style top-to-bottom contrast scrim (keeps bare status text legible even over bright wallpapers)
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: bar.isMaximized
                    ? Theme.alpha(Theme.surface, ShellState.darkMode ? 0.85 : 0.88)
                    : Theme.alpha(Theme.surface, ShellState.darkMode ? 0.78 : 0.80)
                Behavior on color { ColorAnimation { duration: Motion.medium } }
            }
            GradientStop {
                position: 0.62
                color: bar.isMaximized
                    ? Theme.alpha(Theme.surface, ShellState.darkMode ? 0.56 : 0.60)
                    : Theme.alpha(Theme.surface, ShellState.darkMode ? 0.42 : 0.44)
                Behavior on color { ColorAnimation { duration: Motion.medium } }
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14

        // =====================================================================
        // LEFT: Bare Android Desktop Clock + Date (opens Notifications & Calendar shade)
        // =====================================================================
        Rectangle {
            id: clockPill
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: 26
            width: clockRow.implicitWidth + 16
            radius: Theme.radiusPill
            color: ShellState.activeOverlay === "calendar"
                ? Theme.primary
                : (clockMouse.containsMouse ? Theme.alpha(Theme.surfaceContainerHigh, 0.75) : "transparent")

            Behavior on color { ColorAnimation { duration: Motion.fast } }

            RowLayout {
                id: clockRow
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: SystemStatus.timeShort
                    color: ShellState.activeOverlay === "calendar" ? Theme.fgPrimary : Theme.fgSurface
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Text {
                    text: SystemStatus.dateShort
                    color: ShellState.activeOverlay === "calendar" ? Theme.alpha(Theme.fgPrimary, 0.85) : Theme.fgSurfaceVariant
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }

            MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ShellState.toggleOverlay("calendar")
            }
        }

        // =====================================================================
        // CENTER: Morphing Workspace Dots -> Active App-Icon Pill
        // =====================================================================
        Rectangle {
            id: wsContainer
            readonly property int padLeft: bar.firstWsActive ? 2 : 9
            readonly property bool rightEdgePillActive: scratchpadModel.count > 0
                ? scratchpadModel.get(scratchpadModel.count - 1).spVisible
                : bar.lastWsActive
            readonly property int padRight: rightEdgePillActive ? 2 : 9

            anchors.centerIn: parent
            height: 26
            width: wsRow.implicitWidth + padLeft + padRight
            radius: Theme.radiusPill
            color: Theme.glassSurface
            border.width: 1
            border.color: Theme.glassBorder

            Behavior on width {
                SpringAnimation {
                    spring: Motion.morphSpring
                    damping: Motion.morphDamping
                }
            }

            WheelHandler {
                onWheel: event => {
                    if (event.angleDelta.y > 0) Umbriel.previousWorkspace();
                    else if (event.angleDelta.y < 0) Umbriel.nextWorkspace();
                }
            }

            Row {
                id: wsRow
                anchors.left: parent.left
                anchors.leftMargin: wsContainer.padLeft
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Behavior on anchors.leftMargin {
                    SpringAnimation {
                        spring: Motion.morphSpring
                        damping: Motion.morphDamping
                    }
                }

                Repeater {
                    model: wsModel

                    delegate: Rectangle {
                        id: wsPill
                        required property string wsId
                        required property int wsIndex
                        required property bool active
                        required property bool occupied

                        readonly property bool isActive: active
                        readonly property bool isOccupied: occupied
                        property int focusedWinIdx: -1

                        // Incremental ListModel of windows in this workspace so reordering columns
                        // (Mod+Shift+Left/Right) smoothly spring-slides icons past each other!
                        ListModel { id: winModel }

                        function syncWorkspaceWindows() {
                            const list = Umbriel.windowsInWorkspace(wsId);
                            const nextIds = new Set(list.map(w => w.id));

                            for (let i = winModel.count - 1; i >= 0; i--) {
                                if (!nextIds.has(winModel.get(i).winId)) {
                                    winModel.remove(i);
                                }
                            }

                            let focusIdx = -1;
                            for (let target = 0; target < list.length; target++) {
                                const w = list[target];
                                if (w.active || w.focused) focusIdx = target;

                                let cur = -1;
                                for (let j = target; j < winModel.count; j++) {
                                    if (winModel.get(j).winId === w.id) {
                                        cur = j;
                                        break;
                                    }
                                }

                                if (cur === -1) {
                                    winModel.insert(target, {
                                        winId: w.id,
                                        appId: w.app_id || ""
                                    });
                                } else {
                                    if (cur !== target) winModel.move(cur, target, 1);
                                    if (winModel.get(target).appId !== (w.app_id || "")) {
                                        winModel.setProperty(target, "appId", w.app_id || "");
                                    }
                                }
                            }
                            focusedWinIdx = focusIdx;
                        }

                        Connections {
                            target: Umbriel
                            function onWindowsChanged() { wsPill.syncWorkspaceWindows(); }
                        }

                        Component.onCompleted: syncWorkspaceWindows()
                        onWsIdChanged: syncWorkspaceWindows()

                        anchors.verticalCenter: parent.verticalCenter
                        height: isActive ? 22 : (isOccupied ? 8 : 6)
                        width: isActive
                            ? Math.max(26, iconContainer.implicitWidth + 10)
                            : (isOccupied ? 8 : 6)
                        radius: Theme.radiusPill
                        color: isActive
                            ? Theme.primaryContainer
                            : (wsMouse.containsMouse
                                ? Theme.primary
                                : (isOccupied ? Theme.alpha(Theme.fgSurface, 0.72) : Theme.alpha(Theme.fgSurfaceVariant, 0.35)))
                        clip: true

                        Behavior on width {
                            SpringAnimation {
                                spring: Motion.morphSpring
                                damping: Motion.morphDamping
                            }
                        }
                        Behavior on height {
                            SpringAnimation {
                                spring: Motion.morphSpring
                                damping: Motion.morphDamping
                            }
                        }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        // Inactive workspace click area
                        MouseArea {
                            id: wsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton) {
                                    Umbriel.toggleOverview();
                                } else if (!wsPill.isActive) {
                                    Umbriel.switchWorkspace(wsPill.wsIndex);
                                }
                            }
                        }

                        // Active workspace: mini icons spring-pop in/out + gliding focus circle
                        Item {
                            id: iconContainer
                            anchors.centerIn: parent
                            implicitWidth: iconRow.implicitWidth
                            implicitHeight: 18
                            width: implicitWidth
                            height: implicitHeight
                            opacity: wsPill.isActive ? 1.0 : 0.0
                            scale: wsPill.isActive ? 1.0 : 0.45
                            visible: opacity > 0.02

                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            Behavior on scale {
                                SpringAnimation {
                                    spring: Motion.morphSpring
                                    damping: Motion.morphDamping
                                }
                            }

                            // Pixel-centered gliding focus halo behind the focused app icon
                            Rectangle {
                                visible: winModel.count > 0 && wsPill.focusedWinIdx >= 0
                                y: 0
                                x: Math.max(0, wsPill.focusedWinIdx) * (18 + 4)
                                width: 18
                                height: 18
                                radius: 9
                                color: Theme.alpha(Theme.primary, 0.35)

                                Behavior on x {
                                    SpringAnimation {
                                        spring: Motion.morphSpring
                                        damping: Motion.morphDamping
                                    }
                                }
                            }

                            // Fallback dot when active workspace is empty
                            Rectangle {
                                visible: winModel.count === 0
                                anchors.centerIn: parent
                                width: 6
                                height: 6
                                radius: 3
                                color: Theme.fgPrimaryContainer
                            }

                            Row {
                                id: iconRow
                                anchors.centerIn: parent
                                spacing: 4

                                // Smoothly spring-glide icons when reordering columns in scrolling mode
                                move: Transition {
                                    SpringAnimation {
                                        properties: "x"
                                        spring: Motion.morphSpring
                                        damping: Motion.morphDamping
                                        epsilon: 0.1
                                    }
                                }

                                add: Transition {
                                    ParallelAnimation {
                                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 140; easing.type: Easing.OutCubic }
                                        SpringAnimation { property: "scale"; from: 0.4; to: 1.0; spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.005 }
                                    }
                                }

                                Repeater {
                                    model: winModel

                                    delegate: Item {
                                        required property string winId
                                        required property string appId
                                        width: 18
                                        height: 18

                                        Image {
                                            anchors.centerIn: parent
                                            width: 14
                                            height: 14
                                            sourceSize.width: 28
                                            sourceSize.height: 28
                                            smooth: true
                                            mipmap: true
                                            source: Umbriel.iconForAppId(appId)
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Umbriel.focusWindow(winId)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Incremental ListModel for scratchpads so delegates stay alive and spring-animate smoothly on toggle
                ListModel { id: scratchpadModel }

                function syncScratchpads() {
                    const wins = Umbriel.scratchpadWindows();
                    const byName = {};
                    const list = [];
                    for (let i = 0; i < wins.length; i++) {
                        const w = wins[i];
                        const name = String(w.scratchpad || "");
                        if (!name) continue;
                        if (!byName[name]) {
                            byName[name] = { spName: name, appId: w.app_id || "", spVisible: Boolean(w.visible) };
                            list.push(byName[name]);
                        } else if (w.visible) {
                            byName[name].spVisible = true;
                        }
                    }

                    const nextNames = new Set(list.map(s => s.spName));
                    for (let i = scratchpadModel.count - 1; i >= 0; i--) {
                        if (!nextNames.has(scratchpadModel.get(i).spName)) {
                            scratchpadModel.remove(i);
                        }
                    }
                    for (let target = 0; target < list.length; target++) {
                        const s = list[target];
                        let cur = -1;
                        for (let j = target; j < scratchpadModel.count; j++) {
                            if (scratchpadModel.get(j).spName === s.spName) { cur = j; break; }
                        }
                        if (cur === -1) {
                            scratchpadModel.insert(target, s);
                        } else {
                            if (cur !== target) scratchpadModel.move(cur, target, 1);
                            if (scratchpadModel.get(target).spVisible !== s.spVisible) {
                                scratchpadModel.setProperty(target, "spVisible", s.spVisible);
                            }
                            if (scratchpadModel.get(target).appId !== s.appId) {
                                scratchpadModel.setProperty(target, "appId", s.appId);
                            }
                        }
                    }
                }

                Component.onCompleted: syncScratchpads()

                Connections {
                    target: Umbriel
                    function onWindowsChanged() { wsRow.syncScratchpads(); }
                }

                Rectangle {
                    visible: scratchpadModel.count > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 12
                    color: Theme.glassBorder
                }

                Repeater {
                    model: scratchpadModel

                    delegate: Rectangle {
                        id: spChip
                        required property string spName
                        required property string appId
                        required property bool spVisible
                        readonly property string displayName: spName ? (spName.charAt(0).toUpperCase() + spName.slice(1)) : ""

                        anchors.verticalCenter: parent.verticalCenter
                        height: 22
                        width: spVisible ? (spContentRow.implicitWidth + 14) : 22
                        radius: Theme.radiusPill
                        clip: true
                        color: (!spVisible && spM.containsMouse) ? Theme.surfaceContainerHighest : "transparent"

                        Behavior on width { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        // Spring-popping active pill background (stays alive via ListModel so animation always plays!)
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusPill
                            color: Theme.primaryContainer
                            opacity: spChip.spVisible ? 1.0 : 0.0
                            scale: spChip.spVisible ? 1.0 : 0.45

                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            Behavior on scale { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                        }

                        Row {
                            id: spContentRow
                            anchors.centerIn: parent
                            spacing: 5

                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14
                                sourceSize.width: 28
                                sourceSize.height: 28
                                smooth: true
                                mipmap: true
                                opacity: spChip.spVisible ? 1.0 : 0.6
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                                source: Umbriel.iconForAppId(spChip.appId)
                            }

                            Text {
                                visible: spChip.spVisible && spChip.displayName.length > 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: spChip.displayName
                                color: Theme.fgPrimaryContainer
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                opacity: spChip.spVisible ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            }
                        }

                        MouseArea {
                            id: spM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Umbriel.toggleScratchpad(spChip.spName)
                        }
                    }
                }
            }
        }

        // =====================================================================
        // RIGHT: Expressive Shell Live Media Pill + Discord Pill + Android 17 Status Icons
        // =====================================================================
        RowLayout {
            id: rightRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            function syncOrder() {
                const map = {
                    "media": mediaPill,
                    "tray": trayRow,
                    "keyboard": kbPill,
                    "notifications": bellPill,
                    "status": statusPill
                };
                for (const id of ShellState.topBarItems) {
                    const item = map[id];
                    if (item) {
                        item.parent = null;
                        item.parent = rightRow;
                    }
                }
            }

            Component.onCompleted: syncOrder()

            Connections {
                target: ShellState
                function onTopBarItemsChanged() { rightRow.syncOrder(); }
            }

            // Expressive Shell Live Media Pill (stays visible when paused in dark style; left circle toggles play/pause)
            ClippingRectangle {
                id: mediaPill
                readonly property bool mediaOpen: ShellState.activeOverlay === "media"
                readonly property bool isBright: mediaOpen || Media.isPlaying
                readonly property bool showPlayBtn: mediaPillM.containsMouse || mediaPlayM.containsMouse

                visible: ShellState.isTopBarItemEnabled("media") && Media.hasPlayer && Media.title.length > 0
                Layout.preferredHeight: 24
                Layout.preferredWidth: Math.min(184, mediaPillRow.implicitWidth + 14)
                radius: 12
                color: mediaOpen
                    ? Theme.primary
                    : (Media.isPlaying ? Theme.primaryContainer : Theme.surfaceContainerLow)
                border.width: 1
                border.color: mediaOpen
                    ? Theme.primary
                    : (Media.isPlaying ? Theme.alpha(Theme.primary, 0.35) : Theme.alpha(Theme.fgSurface, 0.28))
                contentUnderBorder: true

                scale: mediaPillM.pressed ? 0.95 : 1.0
                Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                Behavior on Layout.preferredWidth { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                // Pill body click opens MediaShade (placed BELOW mediaPillRow so left play/pause button wins clicks)
                MouseArea {
                    id: mediaPillM
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) Media.togglePlay();
                        else ShellState.toggleOverlay("media");
                    }
                }

                RowLayout {
                    id: mediaPillRow
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 10
                    spacing: 6

                    // Left icon: shows player app icon at rest, morphs to clickable Play/Pause circle on hover/open
                    Item {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: 9
                            color: mediaPill.showPlayBtn
                                ? (mediaPill.isBright
                                    ? (mediaPill.mediaOpen ? Theme.fgPrimary : Theme.primary)
                                    : Theme.fgSurface)
                                : "transparent"

                            scale: mediaPlayM.pressed ? 0.88 : 1.0
                            Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            Image {
                                id: barPlayerIcon
                                anchors.centerIn: parent
                                width: 15
                                height: 15
                                visible: !mediaPill.showPlayBtn && (Media.playerIconSource.length > 0 || Media.artUrl.length > 0) && status === Image.Ready
                                source: Media.playerIconSource.length > 0 ? Media.playerIconSource : Media.artUrl
                                fillMode: Media.playerIconSource.length > 0 ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                                sourceSize.width: 32
                                sourceSize.height: 32
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: mediaPill.showPlayBtn || !barPlayerIcon.visible
                                text: mediaPill.showPlayBtn
                                    ? (Media.isPlaying ? "󰏤" : "󰐊")
                                    : "󰎆"
                                color: mediaPill.showPlayBtn
                                    ? (mediaPill.isBright
                                        ? (mediaPill.mediaOpen ? Theme.primary : Theme.fgPrimary)
                                        : Theme.surfaceContainerLow)
                                    : (mediaPill.mediaOpen
                                        ? Theme.fgPrimary
                                        : (Media.isPlaying ? Theme.fgPrimaryContainer : Theme.fgSurface))
                                font.family: Theme.fontMono
                                font.pixelSize: mediaPill.showPlayBtn ? 11 : 12
                            }
                        }

                        MouseArea {
                            id: mediaPlayM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Media.togglePlay()
                        }
                    }

                    // Scrolling marquee text with soft edge fade-out (no ellipsis)
                    Item {
                        id: marqueeClip
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: mediaTitleTxt.implicitWidth
                        clip: true

                        readonly property real overflow: Math.max(0, mediaTitleTxt.implicitWidth - width)
                        readonly property bool needsScroll: overflow > 2
                        readonly property bool hovered: mediaPillM.containsMouse || mediaPlayM.containsMouse
                        property real scrollX: 0

                        onHoveredChanged: {
                            if (hovered && needsScroll) {
                                resetAnim.stop();
                                marqueeAnim.restart();
                            } else {
                                marqueeAnim.stop();
                                resetAnim.restart();
                            }
                        }

                        Connections {
                            target: Media
                            function onTitleChanged() {
                                marqueeAnim.stop();
                                resetAnim.stop();
                                marqueeClip.scrollX = 0;
                                if (marqueeClip.hovered && marqueeClip.needsScroll) {
                                    marqueeAnim.restart();
                                }
                            }
                        }

                        SequentialAnimation {
                            id: marqueeAnim
                            loops: Animation.Infinite
                            PauseAnimation { duration: 400 }
                            NumberAnimation {
                                target: marqueeClip
                                property: "scrollX"
                                to: marqueeClip.overflow
                                duration: Math.max(1200, Math.round(marqueeClip.overflow * 32))
                                easing.type: Easing.InOutSine
                            }
                            PauseAnimation { duration: 900 }
                            NumberAnimation {
                                target: marqueeClip
                                property: "scrollX"
                                to: 0
                                duration: Math.max(900, Math.round(marqueeClip.overflow * 22))
                                easing.type: Easing.InOutSine
                            }
                            PauseAnimation { duration: 500 }
                        }

                        NumberAnimation {
                            id: resetAnim
                            target: marqueeClip
                            property: "scrollX"
                            to: 0
                            duration: 320
                            easing.type: Easing.OutCubic
                        }

                        Text {
                            id: mediaTitleTxt
                            anchors.verticalCenter: parent.verticalCenter
                            x: -marqueeClip.scrollX
                            text: Media.title
                            color: mediaPill.mediaOpen
                                ? Theme.fgPrimary
                                : (Media.isPlaying ? Theme.fgPrimaryContainer : Theme.fgSurface)
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }

                        // Soft left-edge fade when scrolled
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 16
                            opacity: marqueeClip.scrollX > 1 ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: mediaPill.color }
                                GradientStop { position: 1.0; color: Theme.alpha(mediaPill.color, 0.0) }
                            }
                        }

                        // Soft right-edge fade when overflowing
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 22
                            opacity: (marqueeClip.needsScroll && marqueeClip.scrollX < marqueeClip.overflow - 1) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Theme.alpha(mediaPill.color, 0.0) }
                                GradientStop { position: 1.0; color: mediaPill.color }
                            }
                        }
                    }
                }
            }

            // Background apps / System Tray (left-click activates, right-click opens themed M3E menu, middle-click hides)
            Row {
                id: trayRow
                visible: ShellState.isTopBarItemEnabled("tray") && trayRepeater.count > 0
                spacing: 4
                Layout.alignment: Qt.AlignVCenter

                Repeater {
                    id: trayRepeater
                    model: SystemTray.items

                    delegate: Rectangle {
                        id: trayBtn
                        required property var modelData
                        readonly property string itemId: String(modelData.id || modelData.title || "")
                        readonly property bool hiddenByUser: ShellState.isTrayHidden(itemId)

                        visible: !hiddenByUser
                        width: visible ? 22 : 0
                        height: 22
                        radius: 11
                        color: trayM.containsMouse ? Theme.alpha(Theme.surfaceContainerHigh, 0.75) : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Image {
                            anchors.centerIn: parent
                            width: 15
                            height: 15
                            sourceSize.width: 30
                            sourceSize.height: 30
                            smooth: true
                            mipmap: true
                            source: trayBtn.modelData.icon || ""
                        }

                        MouseArea {
                            id: trayM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton || (mouse.button === Qt.RightButton && (mouse.modifiers & Qt.ShiftModifier))) {
                                    ShellState.toggleHideTray(trayBtn.itemId);
                                } else if (mouse.button === Qt.RightButton || trayBtn.modelData.onlyMenu) {
                                    const pt = trayBtn.mapToItem(null, trayBtn.width / 2, trayBtn.height);
                                    ShellState.openTrayMenu(trayBtn.modelData, trayBtn.itemId, pt.x);
                                } else {
                                    trayBtn.modelData.activate();
                                }
                            }
                        }
                    }
                }
            }

            // Expressive Shell Keyboard Layout Indicator (shown only when > 1 layout is configured)
            Rectangle {
                id: kbPill
                visible: ShellState.isTopBarItemEnabled("keyboard") && Umbriel.hasMultipleKeyboardLayouts
                readonly property bool kbOpen: ShellState.activeOverlay === "keyboard"

                Layout.preferredWidth: Math.max(24, kbCodeTxt.implicitWidth + 10)
                Layout.preferredHeight: 24
                radius: 12
                color: kbOpen
                    ? Theme.primary
                    : (kbBarMouse.containsMouse ? Theme.alpha(Theme.surfaceContainerHigh, 0.75) : "transparent")

                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Text {
                    id: kbCodeTxt
                    anchors.centerIn: parent
                    text: Umbriel.currentKeyboardLayoutCode
                    color: kbPill.kbOpen ? Theme.fgPrimary : Theme.fgSurface
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                MouseArea {
                    id: kbBarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            Umbriel.nextKeyboardLayout();
                        } else {
                            ShellState.toggleOverlay("keyboard");
                        }
                    }
                }
            }

            // Notification Bell icon with unread dot (Expressive Shell style, highlights in primary circle when open)
            Rectangle {
                id: bellPill
                visible: ShellState.isTopBarItemEnabled("notifications")
                readonly property bool notifOpen: ShellState.activeOverlay === "notifications"

                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 12
                color: notifOpen
                    ? Theme.primary
                    : (bellMouse.containsMouse ? Theme.alpha(Theme.surfaceContainerHigh, 0.75) : "transparent")

                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Canvas {
                    id: bellCanvas
                    anchors.centerIn: parent
                    width: 15
                    height: 15
                    property color iconColor: bellPill.notifOpen
                        ? Theme.fgPrimary
                        : (ShellState.dnd ? Theme.fgSurfaceVariant : Theme.fgSurface)
                    onIconColorChanged: requestPaint()
                    Component.onCompleted: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.fillStyle = iconColor;
                        ctx.beginPath();
                        ctx.arc(7.5, 6.2, 4.1, Math.PI, 0, false);
                        ctx.lineTo(12.2, 10.6);
                        ctx.lineTo(13.2, 11.6);
                        ctx.lineTo(1.8, 11.6);
                        ctx.lineTo(2.8, 10.6);
                        ctx.closePath();
                        ctx.fill();
                        ctx.beginPath();
                        ctx.arc(7.5, 12.6, 1.5, 0, Math.PI * 2);
                        ctx.fill();
                    }
                }

                // Unread dot badge in top-right of bell
                Rectangle {
                    visible: Notifications.count > 0 && !ShellState.dnd
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 3
                    anchors.rightMargin: 3
                    width: 5
                    height: 5
                    radius: 2.5
                    color: bellPill.notifOpen ? Theme.fgPrimary : Theme.primary
                }

                MouseArea {
                    id: bellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ShellState.toggleOverlay("notifications")
                }
            }

            // Expressive Shell / Android 17 Status Cluster (opens Quick Settings; right-click cycles dock)
            Rectangle {
                id: statusPill
                visible: ShellState.isTopBarItemEnabled("status")
                readonly property bool qsOpen: ShellState.activeOverlay === "quicksettings"
                readonly property color iconFg: qsOpen ? Theme.fgPrimary : Theme.fgSurface

                Layout.preferredHeight: 24
                Layout.preferredWidth: statusRow.implicitWidth + 14
                radius: 12
                color: qsOpen
                    ? Theme.primary
                    : (statusMouse.containsMouse ? Theme.alpha(Theme.surfaceContainerHigh, 0.75) : "transparent")

                Behavior on color { ColorAnimation { duration: Motion.fast } }

                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 7

                    // Mic muted indicator
                    Text {
                        visible: SystemStatus.micMuted
                        text: "󰍭"
                        color: statusPill.qsOpen ? Theme.fgPrimary : Theme.error
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                    }

                    // Bluetooth vector icon (shown when powered)
                    Canvas {
                        visible: SystemStatus.btPowered
                        Layout.preferredWidth: 13
                        Layout.preferredHeight: 14
                        property color col: statusPill.iconFg
                        onColChanged: requestPaint()
                        Component.onCompleted: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            ctx.strokeStyle = col;
                            ctx.lineWidth = 1.45;
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.beginPath();
                            ctx.moveTo(3.2, 4.2);
                            ctx.lineTo(9.8, 9.8);
                            ctx.lineTo(6.5, 12.6);
                            ctx.lineTo(6.5, 1.4);
                            ctx.lineTo(9.8, 4.2);
                            ctx.lineTo(3.2, 9.8);
                            ctx.stroke();
                        }
                    }

                    // Wi-Fi Signal Icon (matches Wi-Fi menu signal levels)
                    Text {
                        text: SystemStatus.wifiIconForSignal(SystemStatus.wifiSignal)
                        color: SystemStatus.wifiConnected ? statusPill.iconFg : Theme.alpha(statusPill.iconFg, 0.45)
                        font.family: Theme.fontMono
                        font.pixelSize: 15
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    // Android 17 / Expressive Horizontal Proportional-Fill Battery Capsule (`[ 85 ]`)
                    Item {
                        visible: SystemStatus.hasBattery
                        Layout.preferredWidth: 31
                        Layout.preferredHeight: 15

                        Canvas {
                            id: batCanvas
                            anchors.fill: parent
                            property int pct: SystemStatus.batteryPercent
                            property bool charging: SystemStatus.batteryCharging
                            property bool qsOpen: statusPill.qsOpen
                            property color fillCol: qsOpen
                                ? Theme.fgPrimary
                                : (charging ? Theme.primary : (pct <= ShellState.batteryWarnThreshold ? Theme.error : Theme.fgSurface))
                            property color emptyCol: Theme.alpha(statusPill.iconFg, 0.28)
                            property color strokeCol: Theme.alpha(statusPill.iconFg, 0.55)

                            onPctChanged: requestPaint()
                            onChargingChanged: requestPaint()
                            onFillColChanged: requestPaint()
                            onStrokeColChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);

                                const bodyW = 27;
                                const bodyH = 14;
                                const y0 = 0.5;
                                const r = 4.2;

                                // Battery positive terminal nub on the right
                                ctx.fillStyle = emptyCol;
                                ctx.beginPath();
                                ctx.roundedRect(bodyW + 1.2, (height - 5.5) / 2, 2.2, 5.5, 1.1, 1.1);
                                ctx.fill();

                                // Clip to rounded battery body
                                ctx.save();
                                ctx.beginPath();
                                ctx.roundedRect(0.5, y0, bodyW, bodyH, r, r);
                                ctx.clip();

                                // Unfilled track
                                ctx.fillStyle = emptyCol;
                                ctx.fillRect(0.5, y0, bodyW, bodyH);

                                // Proportional fill left-to-right
                                const fillW = Math.max(0, Math.min(bodyW, bodyW * (pct / 100.0)));
                                ctx.fillStyle = fillCol;
                                ctx.fillRect(0.5, y0, fillW, bodyH);
                                ctx.restore();

                                // Crisp outline around battery capsule
                                ctx.strokeStyle = strokeCol;
                                ctx.lineWidth = 0.9;
                                ctx.beginPath();
                                ctx.roundedRect(0.5, y0, bodyW, bodyH, r, r);
                                ctx.stroke();
                            }
                        }

                        // Centered bold battery number inside the horizontal capsule
                        Text {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: -1.5
                            text: SystemStatus.batteryPercent
                            color: statusPill.qsOpen
                                ? Theme.primary
                                : (SystemStatus.batteryCharging
                                    ? Theme.fgPrimary
                                    : (SystemStatus.batteryPercent <= ShellState.batteryWarnThreshold ? Theme.fgError : Theme.surface))
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                }

                MouseArea {
                    id: statusMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            ShellState.cycleDockMode();
                        } else {
                            ShellState.toggleOverlay("quicksettings");
                        }
                    }
                }
            }
        }
    }
}
