import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../theme"
import "../services"

PanelWindow {
    id: notifWin

    required property var modelData
    screen: modelData

    readonly property bool isOpen: ShellState.activeOverlay === "notifications"
    property bool windowVisible: false
    property bool morphStart: false
    property bool morphBehaviorsEnabled: false
    property int morphSlideDir: 1
    visible: windowVisible

    Timer {
        id: morphOutTimer
        interval: 45
        onTriggered: {
            if (!notifWin.isOpen) {
                notifWin.windowVisible = false;
                card.state = "closed";
            }
        }
    }

    Timer {
        id: openTrigger
        interval: 25
        onTriggered: {
            const wasMorph = notifWin.morphStart;
            notifWin.morphBehaviorsEnabled = true;
            notifWin.morphStart = false;
            card.state = "open";
            if (wasMorph) notifSlideAnim.restart();
            ShellState.reportOverlayGeometry("notifications", 388, card.targetH, 12);
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
            syncGroupModel();
            const doMorph = ShellState.overlaysShareRegion(ShellState.previousOverlay, "notifications")
                && ShellState.morphFromW > 40 && ShellState.morphFromH > 40;
            morphBehaviorsEnabled = false;
            morphStart = doMorph;
            if (doMorph) {
                morphSlideDir = ShellState.overlaySlideDir(ShellState.previousOverlay, "notifications");
                contentCol.opacity = 0.0;
            } else {
                contentCol.opacity = 1.0;
                notifContentSlide.x = 0;
            }
            card.state = doMorph ? "morph" : "closed";
            windowVisible = true;
            if (doMorph) morphBehaviorsEnabled = true;
            openTrigger.restart();
        } else {
            openTrigger.stop();
            if (ShellState.overlaysShareRegion("notifications", ShellState.activeOverlay)) {
                morphOutTimer.restart();
            } else {
                card.state = "closed";
            }
        }
    }

    // Incremental per-app grouped ListModel (ordered by most recent notification per app)
    ListModel {
        id: groupModel
    }

    function buildGroups() {
        const list = Notifications.history || [];
        const byKey = {};
        const ordered = [];

        for (let i = 0; i < list.length; i++) {
            const n = list[i];
            const aName = n.appName || "Notification";
            const key = aName.toLowerCase();
            if (!byKey[key]) {
                const grp = {
                    appKey: key,
                    appName: aName,
                    appIcon: n.appIconSource || n.appBadgeSource || n.iconSource || "",
                    latestTime: n.time || "",
                    items: []
                };
                byKey[key] = grp;
                ordered.push(grp);
            }
            const g = byKey[key];
            if (!g.appIcon && (n.appIconSource || n.appBadgeSource || n.iconSource)) {
                g.appIcon = n.appIconSource || n.appBadgeSource || n.iconSource;
            }
            g.items.push({
                uid: n.uid,
                appName: aName,
                iconSource: n.iconSource || "",
                appIconSource: n.appIconSource || "",
                appBadgeSource: n.appBadgeSource || "",
                attachmentImage: n.attachmentImage || "",
                contextImage: n.contextImage || "",
                isContextImage: Boolean(n.isContextImage),
                summary: n.summary || "",
                body: n.body || "",
                actions: Array.isArray(n.actions) ? n.actions : [],
                time: n.time || ""
            });
        }
        return ordered;
    }

    function syncGroupModel() {
        const groups = buildGroups();
        const nextKeys = new Set(groups.map(g => g.appKey));

        for (let i = groupModel.count - 1; i >= 0; i--) {
            if (!nextKeys.has(groupModel.get(i).appKey)) {
                groupModel.remove(i);
            }
        }

        for (let target = 0; target < groups.length; target++) {
            const g = groups[target];
            const serialized = JSON.stringify(g.items);
            let cur = -1;
            for (let j = target; j < groupModel.count; j++) {
                if (groupModel.get(j).appKey === g.appKey) {
                    cur = j;
                    break;
                }
            }
            if (cur === -1) {
                groupModel.insert(target, {
                    appKey: g.appKey,
                    appName: g.appName,
                    appIcon: g.appIcon,
                    latestTime: g.latestTime,
                    itemCount: g.items.length,
                    itemsJson: serialized,
                    removing: false,
                    animateIn: notifWin.isOpen && card.state === "open"
                });
            } else {
                if (cur !== target) groupModel.move(cur, target, 1);
                const row = groupModel.get(target);
                if (row.appIcon !== g.appIcon) groupModel.setProperty(target, "appIcon", g.appIcon);
                if (row.latestTime !== g.latestTime) groupModel.setProperty(target, "latestTime", g.latestTime);
                if (row.itemCount !== g.items.length) groupModel.setProperty(target, "itemCount", g.items.length);
                if (row.itemsJson !== serialized) groupModel.setProperty(target, "itemsJson", serialized);
            }
        }
    }

    Connections {
        target: Notifications
        function onHistoryChanged() {
            notifWin.syncGroupModel();
        }
    }

    Component.onCompleted: syncGroupModel()

    Timer {
        id: clearAllTimer
        interval: 220
        onTriggered: Notifications.clearAll()
    }

    function animateClearAll() {
        if (groupModel.count === 0) return;
        for (let i = 0; i < groupModel.count; i++) {
            groupModel.setProperty(i, "removing", true);
        }
        clearAllTimer.restart();
    }

    // Reusable rounded attached-image preview (Android BigPicture style when expanded)
    component BigImagePreview: ClippingRectangle {
        id: bigImgBox
        property string src: ""
        property bool onlyIfLarge: false

        readonly property bool isLoaded: previewImg.status === Image.Ready
        readonly property bool qualifies: !onlyIfLarge || previewImg.implicitWidth >= 100 || previewImg.implicitHeight >= 100
        readonly property real aspect: (previewImg.implicitWidth > 0 && previewImg.implicitHeight > 0)
            ? (previewImg.implicitHeight / previewImg.implicitWidth)
            : 0.56

        visible: src.length > 0 && isLoaded && qualifies
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? Math.max(88, Math.min(168, Math.round(width * aspect))) : 0
        Layout.topMargin: visible ? 6 : 0
        radius: 14
        color: Theme.surfaceContainerHighest

        Image {
            id: previewImg
            anchors.fill: parent
            source: bigImgBox.src
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
        }
    }

    // Reusable Android text-action row (`Play   Turn Off   Watch Later`)
    component ActionRow: Flow {
        id: actFlow
        property int uid: -1
        property var actions: []

        visible: actions && actions.length > 0
        Layout.fillWidth: true
        Layout.topMargin: visible ? 6 : 0
        spacing: 14

        Repeater {
            model: actFlow.actions || []

            delegate: Text {
                required property var modelData
                text: modelData.text || ""
                color: actM.containsMouse ? Theme.fgSurface : Theme.primary
                font.family: Theme.fontSans
                font.pixelSize: 12
                font.weight: Font.DemiBold
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                MouseArea {
                    id: actM
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifications.invokeAction(actFlow.uid, modelData.identifier)
                }
            }
        }
    }

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.closeOverlay()
    }

    // Expressive Shell / Android 17 Notifications Shade (anchored top-right beneath the bell)
    Rectangle {
        id: card
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: notifWin.morphStart ? ShellState.morphFromRight : 12
        width: notifWin.morphStart ? ShellState.morphFromW : 388
        readonly property real maxBodyHeight: Math.max(260, Math.min(520, notifWin.height - 170))
        readonly property real listHeight: Math.min(maxBodyHeight, notifListCol.implicitHeight)
        readonly property real targetH: contentCol.implicitHeight + 28
        height: notifWin.morphStart ? ShellState.morphFromH : targetH
        radius: Theme.radiusExtraLarge
        color: Theme.glassSurface
        border.width: 1
        border.color: Theme.glassBorder
        clip: true

        onTargetHChanged: if (notifWin.isOpen && !notifWin.morphStart) ShellState.reportOverlayGeometry("notifications", 388, targetH, 12)

        Behavior on anchors.rightMargin {
            enabled: notifWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }
        Behavior on width {
            enabled: notifWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }
        Behavior on height {
            enabled: notifWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }

        focus: notifWin.isOpen
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
                        script: { if (!notifWin.isOpen) notifWin.windowVisible = false; }
                    }
                }
            }
        ]

        ParallelAnimation {
            id: notifSlideAnim
            NumberAnimation { target: notifContentSlide; property: "x"; from: notifWin.morphSlideDir * 26; to: 0; duration: 210; easing.type: Easing.OutCubic }
            NumberAnimation { target: contentCol; property: "opacity"; from: 0.0; to: 1.0; duration: 170; easing.type: Easing.OutQuad }
        }

        ColumnLayout {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 12
            transform: Translate { id: notifContentSlide; x: 0 }

            // Empty state card
            Rectangle {
                visible: groupModel.count === 0
                Layout.fillWidth: true
                Layout.preferredHeight: 92
                radius: 22
                color: Theme.surfaceContainerHigh

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ShellState.dnd ? "Do Not Disturb is active" : "No notifications"
                        color: Theme.fgSurface
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ShellState.dnd ? "Notifications are silenced" : "You're all caught up"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                    }
                }
            }

            // Rounded ClippingRectangle around the scrollable stack so scrolled cards crop cleanly
            // right against Android 17's 22px rounded stack edge
            ClippingRectangle {
                visible: groupModel.count > 0
                Layout.fillWidth: true
                Layout.preferredHeight: card.listHeight
                radius: 22
                color: "transparent"

                Flickable {
                    id: notifFlick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: notifListCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    NumberAnimation {
                        id: shelfScrollAnim
                        target: notifFlick
                        property: "contentY"
                        duration: 280
                        easing.type: Easing.OutCubic
                    }

                    Column {
                        id: notifListCol
                        width: parent.width
                        spacing: 0

                        Repeater {
                            id: groupRepeater
                            model: groupModel

                            delegate: Item {
                                id: grpSlot
                                required property string appKey
                                required property string appName
                                required property string appIcon
                                required property string latestTime
                                required property int itemCount
                                required property string itemsJson
                                required property bool removing
                                required property bool animateIn
                                required property int index

                                readonly property var items: {
                                    try { return JSON.parse(itemsJson); }
                                    catch (e) { return []; }
                                }
                                readonly property var firstItem: items.length > 0 ? items[0] : null
                                readonly property bool isGroup: items.length > 1

                                property bool appeared: !animateIn
                                property bool expanded: false
                                property bool localRemoving: false
                                readonly property bool isRemoving: removing || localRemoving
                                readonly property bool isShown: appeared && !isRemoving
                                readonly property bool isFirst: index === 0
                                readonly property bool isLast: index === groupRepeater.count - 1

                                readonly property real cardInnerHeight: grpCard.implicitHeight
                                readonly property real targetHeight: cardInnerHeight + (isLast ? 0 : 3)

                                Component.onCompleted: {
                                    if (animateIn) {
                                        Qt.callLater(() => {
                                            if (grpSlot) grpSlot.appeared = true;
                                        });
                                    }
                                }

                                width: notifListCol.width
                                height: isShown ? targetHeight : 0
                                clip: true

                                Behavior on height {
                                    NumberAnimation {
                                        duration: 230
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Timer {
                                    id: dismissGrpTimer
                                    interval: 235
                                    onTriggered: {
                                        if (grpSlot.isGroup) Notifications.dismissApp(grpSlot.appKey);
                                        else if (grpSlot.firstItem) Notifications.dismiss(grpSlot.firstItem.uid);
                                    }
                                }

                                function requestDismissGroup() {
                                    if (localRemoving) return;
                                    localRemoving = true;
                                    dismissGrpTimer.restart();
                                }

                                Rectangle {
                                    id: grpCard
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    implicitHeight: isGroup
                                        ? (grpSlot.expanded ? expandedGroupCol.implicitHeight : (collapsedGroupRow.implicitHeight + 24))
                                        : (singleRow.implicitHeight + 24)
                                    height: implicitHeight
                                    clip: true

                                    Behavior on height {
                                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                    }

                                    opacity: grpSlot.isShown ? 1.0 : 0.0
                                    scale: grpSlot.isShown ? 1.0 : 0.92
                                    transformOrigin: Item.Top

                                    Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutQuad } }
                                    Behavior on scale { SpringAnimation { spring: 11.0; damping: 0.58; epsilon: 0.002 } }

                                    topLeftRadius: grpSlot.isFirst ? 22 : 6
                                    topRightRadius: grpSlot.isFirst ? 22 : 6
                                    bottomLeftRadius: grpSlot.isLast ? 22 : 6
                                    bottomRightRadius: grpSlot.isLast ? 22 : 6

                                    Behavior on topLeftRadius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on topRightRadius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on bottomLeftRadius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on bottomRightRadius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                    color: (!grpSlot.expanded && cardHover.containsMouse)
                                        ? Theme.surfaceContainerHighest
                                        : Theme.surfaceContainerHigh
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                    MouseArea {
                                        id: cardHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.RightButton) {
                                                grpSlot.requestDismissGroup();
                                            } else if (!grpSlot.isGroup || !grpSlot.expanded) {
                                                grpSlot.expanded = !grpSlot.expanded;
                                            }
                                        }
                                    }

                                    // =========================================================
                                    // CASE A: Single Notification (compact Android crop + BigPicture/Actions when expanded)
                                    // =========================================================
                                    RowLayout {
                                        id: singleRow
                                        visible: !grpSlot.isGroup && grpSlot.firstItem !== null
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 12
                                        anchors.topMargin: 12
                                        spacing: 12

                                        // Left 36px circular icon rail (context image + corner app badge, or app icon)
                                        Item {
                                            Layout.preferredWidth: 38
                                            Layout.preferredHeight: 38
                                            Layout.alignment: Qt.AlignTop

                                            ClippingRectangle {
                                                anchors.centerIn: parent
                                                width: 36
                                                height: 36
                                                radius: 18
                                                color: Theme.primaryContainer

                                                Image {
                                                    id: singleIconImg
                                                    anchors.fill: parent
                                                    anchors.margins: (grpSlot.firstItem && grpSlot.firstItem.isContextImage) ? 0 : 4
                                                    visible: grpSlot.firstItem !== null && (grpSlot.firstItem.iconSource || "").length > 0 && status === Image.Ready
                                                    source: grpSlot.firstItem ? (grpSlot.firstItem.iconSource || "") : ""
                                                    fillMode: (grpSlot.firstItem && grpSlot.firstItem.isContextImage) ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                                                    sourceSize.width: 72
                                                    sourceSize.height: 72
                                                    smooth: true
                                                    mipmap: true
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: !singleIconImg.visible
                                                    text: "󰂚"
                                                    color: Theme.fgPrimaryContainer
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 16
                                                }
                                            }

                                            // Small corner app badge when a context image is shown
                                            Rectangle {
                                                visible: grpSlot.firstItem !== null
                                                    && grpSlot.firstItem.isContextImage
                                                    && (grpSlot.firstItem.appBadgeSource || "").length > 0
                                                    && singleBadgeImg.status === Image.Ready
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                width: 16
                                                height: 16
                                                radius: 8
                                                color: Theme.surfaceContainerHigh
                                                border.width: 1.5
                                                border.color: Theme.surfaceContainerHigh

                                                Image {
                                                    id: singleBadgeImg
                                                    anchors.centerIn: parent
                                                    width: 11
                                                    height: 11
                                                    sourceSize.width: 22
                                                    sourceSize.height: 22
                                                    smooth: true
                                                    mipmap: true
                                                    source: grpSlot.firstItem ? (grpSlot.firstItem.appBadgeSource || "") : ""
                                                }
                                            }
                                        }

                                        // Right of icon rail: text + optional expanded BigPicture + Actions
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 2

                                            // When expanded, show Android `App · Time` header line above bold title
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 6

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    spacing: 2

                                                    Text {
                                                        visible: grpSlot.expanded && grpSlot.firstItem !== null && grpSlot.firstItem.summary !== grpSlot.appName
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 0
                                                        elide: Text.ElideRight
                                                        text: grpSlot.appName + "  ·  " + grpSlot.latestTime
                                                        color: Theme.fgSurfaceVariant
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: 11
                                                    }

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 0
                                                        spacing: 5

                                                        Text {
                                                            Layout.fillWidth: true
                                                            Layout.minimumWidth: 0
                                                            Layout.maximumWidth: implicitWidth
                                                            text: grpSlot.firstItem ? (grpSlot.firstItem.summary || grpSlot.appName) : ""
                                                            elide: Text.ElideRight
                                                            color: Theme.fgSurface
                                                            font.family: Theme.fontSans
                                                            font.pixelSize: 12
                                                            font.weight: Font.DemiBold
                                                        }

                                                        Text {
                                                            id: timeTxt
                                                            visible: !grpSlot.expanded || (grpSlot.firstItem !== null && grpSlot.firstItem.summary === grpSlot.appName)
                                                            text: "·  " + grpSlot.latestTime
                                                            color: Theme.fgSurfaceVariant
                                                            font.family: Theme.fontSans
                                                            font.pixelSize: 11
                                                        }

                                                        Item { Layout.fillWidth: true }
                                                    }
                                                }

                                                // Separate hover dismiss × button (keeps steady layout slot so text never reflows)
                                                Rectangle {
                                                    Layout.preferredWidth: 24
                                                    Layout.preferredHeight: 24
                                                    Layout.alignment: Qt.AlignTop
                                                    radius: 12
                                                    readonly property bool shown: cardHover.containsMouse || sDismissM.containsMouse || sExpM.containsMouse
                                                    opacity: shown ? 1.0 : 0.0
                                                    color: sDismissM.containsMouse
                                                        ? Theme.primaryContainer
                                                        : Theme.alpha(Theme.fgSurface, 0.10)

                                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰅖"
                                                        color: sDismissM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 11
                                                    }

                                                    MouseArea {
                                                        id: sDismissM
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        enabled: parent.shown
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: grpSlot.requestDismissGroup()
                                                    }
                                                }

                                                // Dedicated expand/collapse chevron pill (never dismisses)
                                                Rectangle {
                                                    Layout.preferredWidth: 24
                                                    Layout.preferredHeight: 24
                                                    Layout.alignment: Qt.AlignTop
                                                    radius: 12
                                                    color: sExpM.containsMouse
                                                        ? Theme.surfaceContainerHighest
                                                        : Theme.alpha(Theme.fgSurface, 0.10)

                                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: grpSlot.expanded ? "󰅃" : "󰅀"
                                                        color: Theme.fgSurfaceVariant
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 12
                                                    }

                                                    MouseArea {
                                                        id: sExpM
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: grpSlot.expanded = !grpSlot.expanded
                                                    }
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                visible: grpSlot.firstItem !== null && (grpSlot.firstItem.body || "").length > 0
                                                text: grpSlot.firstItem ? grpSlot.firstItem.body : ""
                                                wrapMode: grpSlot.expanded ? Text.WordWrap : Text.NoWrap
                                                maximumLineCount: grpSlot.expanded ? 12 : 1
                                                elide: Text.ElideRight
                                                color: Theme.fgSurfaceVariant
                                                font.family: Theme.fontSans
                                                font.pixelSize: 11
                                            }

                                            // Smoothly expanding/collapsing BigPicture + Action row
                                            Item {
                                                id: singleExtra
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: grpSlot.expanded ? singleExtraCol.implicitHeight : 0
                                                clip: true
                                                opacity: grpSlot.expanded ? 1.0 : 0.0

                                                Behavior on Layout.preferredHeight {
                                                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                                }
                                                Behavior on opacity {
                                                    NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
                                                }

                                                ColumnLayout {
                                                    id: singleExtraCol
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    spacing: 2

                                                    BigImagePreview {
                                                        src: grpSlot.firstItem
                                                            ? (grpSlot.firstItem.attachmentImage || grpSlot.firstItem.contextImage || "")
                                                            : ""
                                                        onlyIfLarge: grpSlot.firstItem ? !(grpSlot.firstItem.attachmentImage || "").length : true
                                                    }

                                                    ActionRow {
                                                        uid: grpSlot.firstItem ? grpSlot.firstItem.uid : -1
                                                        actions: grpSlot.firstItem ? grpSlot.firstItem.actions : []
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // =========================================================
                                    // CASE B: Collapsed Per-App Group (WhatsApp `[ 2 ⌄ ]` / DiDi `[ 3 ⌄ ]`)
                                    // =========================================================
                                    RowLayout {
                                        id: collapsedGroupRow
                                        opacity: (grpSlot.isGroup && !grpSlot.expanded) ? 1.0 : 0.0
                                        visible: grpSlot.isGroup && opacity > 0.01
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 12
                                        anchors.topMargin: 12
                                        spacing: 12

                                        Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutQuad } }

                                        // Full 36px App circular icon
                                        ClippingRectangle {
                                            Layout.preferredWidth: 36
                                            Layout.preferredHeight: 36
                                            Layout.alignment: Qt.AlignTop
                                            radius: 18
                                            color: Theme.primaryContainer

                                            Image {
                                                id: grpAppImg
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                visible: grpSlot.appIcon.length > 0 && status === Image.Ready
                                                source: grpSlot.appIcon
                                                fillMode: Image.PreserveAspectFit
                                                sourceSize.width: 72
                                                sourceSize.height: 72
                                                smooth: true
                                                mipmap: true
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                visible: !grpAppImg.visible
                                                text: "󰂚"
                                                color: Theme.fgPrimaryContainer
                                                font.family: Theme.fontMono
                                                font.pixelSize: 16
                                            }
                                        }

                                        // Header + up to 2 single-line previews (with 16px pfp only when child has context image)
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 6

                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    elide: Text.ElideRight
                                                    text: grpSlot.appName + "  ·  " + grpSlot.latestTime
                                                    color: Theme.fgSurfaceVariant
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 11
                                                    font.weight: Font.Medium
                                                }

                                                // Separate hover dismiss × for collapsed group (steady slot, zero reflow)
                                                Rectangle {
                                                    Layout.preferredWidth: 22
                                                    Layout.preferredHeight: 22
                                                    radius: 11
                                                    readonly property bool shown: cardHover.containsMouse || gCloseM.containsMouse || gPillM.containsMouse
                                                    opacity: shown ? 1.0 : 0.0
                                                    color: gCloseM.containsMouse ? Theme.primaryContainer : Theme.alpha(Theme.fgSurface, 0.10)
                                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰅖"
                                                        color: gCloseM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 11
                                                    }

                                                    MouseArea {
                                                        id: gCloseM
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        enabled: parent.shown
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: grpSlot.requestDismissGroup()
                                                    }
                                                }

                                                // Android `[ 3 ⌄ ]` count pill (expands group)
                                                Rectangle {
                                                    Layout.preferredHeight: 22
                                                    Layout.preferredWidth: gPillRow.implicitWidth + 12
                                                    radius: 11
                                                    color: gPillM.containsMouse
                                                        ? Theme.primaryContainer
                                                        : Theme.alpha(Theme.fgSurface, 0.12)
                                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                                    Row {
                                                        id: gPillRow
                                                        anchors.centerIn: parent
                                                        spacing: 3

                                                        Text {
                                                            text: grpSlot.itemCount
                                                            color: gPillM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurface
                                                            font.family: Theme.fontSans
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                        }
                                                        Text {
                                                            text: "󰅀"
                                                            color: gPillM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                                                            font.family: Theme.fontMono
                                                            font.pixelSize: 11
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: gPillM
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: grpSlot.expanded = true
                                                    }
                                                }
                                            }

                                            Repeater {
                                                model: grpSlot.items.slice(0, 2)

                                                delegate: RowLayout {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    // Tiny 16x16 sender/context avatar ONLY when child has a context image (WhatsApp vs DiDi)
                                                    ClippingRectangle {
                                                        visible: Boolean(modelData.isContextImage) && (modelData.iconSource || "").length > 0
                                                        Layout.preferredWidth: 16
                                                        Layout.preferredHeight: 16
                                                        radius: 8
                                                        color: Theme.surfaceContainerHighest

                                                        Image {
                                                            anchors.fill: parent
                                                            source: modelData.iconSource || ""
                                                            fillMode: Image.PreserveAspectCrop
                                                            sourceSize.width: 32
                                                            sourceSize.height: 32
                                                            smooth: true
                                                            mipmap: true
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                        maximumLineCount: 1
                                                        textFormat: Text.StyledText
                                                        text: {
                                                            const esc = s => String(s || "")
                                                                .replace(/&/g, "&amp;")
                                                                .replace(/</g, "&lt;")
                                                                .replace(/>/g, "&gt;");
                                                            const title = esc(modelData.summary || grpSlot.appName);
                                                            const body = esc(modelData.body || "");
                                                            return body.length > 0
                                                                ? ("<b>" + title + "</b>  " + body)
                                                                : ("<b>" + title + "</b>");
                                                        }
                                                        color: Theme.fgSurface
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: 11
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // =========================================================
                                    // CASE C: Expanded Per-App Group (Android exact rail alignment + hairline dividers)
                                    // - App icon stays full 36x36 in top-left header
                                    // - Context children (WhatsApp) show 36x36 context avatar in left rail
                                    // - Non-context children (DiDi) leave empty 36px spacer in left rail
                                    // =========================================================
                                    ColumnLayout {
                                        id: expandedGroupCol
                                        opacity: (grpSlot.isGroup && grpSlot.expanded) ? 1.0 : 0.0
                                        visible: grpSlot.isGroup && opacity > 0.01
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        spacing: 0

                                        Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutQuad } }

                                        // Group header row (full 36x36 app icon + `App · Time` + `[ × ]` + `[ N ⌃ ]` pill)
                                        Item {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 56

                                            MouseArea {
                                                id: expHdrHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton) grpSlot.requestDismissGroup();
                                                    else grpSlot.expanded = false;
                                                }
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 14
                                                anchors.rightMargin: 12
                                                spacing: 12

                                                // App icon stays full 36x36 in top-left corner
                                                ClippingRectangle {
                                                    Layout.preferredWidth: 36
                                                    Layout.preferredHeight: 36
                                                    radius: 18
                                                    color: Theme.primaryContainer

                                                    Image {
                                                        id: expAppImg
                                                        anchors.fill: parent
                                                        anchors.margins: 4
                                                        visible: grpSlot.appIcon.length > 0 && status === Image.Ready
                                                        source: grpSlot.appIcon
                                                        fillMode: Image.PreserveAspectFit
                                                        sourceSize.width: 72
                                                        sourceSize.height: 72
                                                        smooth: true
                                                        mipmap: true
                                                    }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        visible: !expAppImg.visible
                                                        text: "󰂚"
                                                        color: Theme.fgPrimaryContainer
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 16
                                                    }
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    elide: Text.ElideRight
                                                    text: grpSlot.appName + "  ·  " + grpSlot.latestTime
                                                    color: Theme.fgSurfaceVariant
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 12
                                                    font.weight: Font.Medium
                                                }

                                                // Hover dismiss × for entire group (steady slot, zero reflow)
                                                Rectangle {
                                                    Layout.preferredWidth: 22
                                                    Layout.preferredHeight: 22
                                                    radius: 11
                                                    readonly property bool shown: expHdrHover.containsMouse || expCloseM.containsMouse || expPillM.containsMouse
                                                    opacity: shown ? 1.0 : 0.0
                                                    color: expCloseM.containsMouse ? Theme.primaryContainer : Theme.alpha(Theme.fgSurface, 0.10)
                                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰅖"
                                                        color: expCloseM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 11
                                                    }

                                                    MouseArea {
                                                        id: expCloseM
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        enabled: parent.shown
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: grpSlot.requestDismissGroup()
                                                    }
                                                }

                                                // Android `[ N ⌃ ]` collapse pill
                                                Rectangle {
                                                    Layout.preferredHeight: 22
                                                    Layout.preferredWidth: expPillRow.implicitWidth + 12
                                                    radius: 11
                                                    color: expPillM.containsMouse
                                                        ? Theme.primaryContainer
                                                        : Theme.alpha(Theme.fgSurface, 0.12)
                                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                                    Row {
                                                        id: expPillRow
                                                        anchors.centerIn: parent
                                                        spacing: 3

                                                        Text {
                                                            text: grpSlot.itemCount
                                                            color: expPillM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurface
                                                            font.family: Theme.fontSans
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                        }
                                                        Text {
                                                            text: "󰅃"
                                                            color: expPillM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                                                            font.family: Theme.fontMono
                                                            font.pixelSize: 11
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: expPillM
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: grpSlot.expanded = false
                                                    }
                                                }
                                            }
                                        }

                                        // Seamless Android hairline-divided child notification rows
                                        Repeater {
                                            model: (grpSlot.isGroup && expandedGroupCol.visible) ? grpSlot.items : []

                                            delegate: Item {
                                                id: childSlot
                                                required property var modelData
                                                property bool childExpanded: false
                                                property bool childRemoving: false

                                                readonly property real naturalH: childInner.implicitHeight + 22 + 1
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: childRemoving ? 0 : naturalH
                                                clip: true

                                                Behavior on Layout.preferredHeight {
                                                    NumberAnimation { duration: 210; easing.type: Easing.OutCubic }
                                                }

                                                Timer {
                                                    id: childDismissTimer
                                                    interval: 215
                                                    onTriggered: Notifications.dismiss(childSlot.modelData.uid)
                                                }

                                                function requestDismissChild() {
                                                    if (childRemoving) return;
                                                    if (grpSlot.items.length <= 1) {
                                                        grpSlot.requestDismissGroup();
                                                        return;
                                                    }
                                                    childRemoving = true;
                                                    childDismissTimer.restart();
                                                }

                                                // Subtle Android horizontal hairline rule
                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    height: 1
                                                    color: Theme.alpha(Theme.fgSurface, 0.08)
                                                }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    anchors.topMargin: 1
                                                    color: childHov.containsMouse
                                                        ? Theme.alpha(Theme.fgSurface, 0.05)
                                                        : "transparent"
                                                    opacity: childSlot.childRemoving ? 0.0 : 1.0
                                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                                    MouseArea {
                                                        id: childHov
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                        onClicked: mouse => {
                                                            if (mouse.button === Qt.RightButton) {
                                                                childSlot.requestDismissChild();
                                                            } else {
                                                                childSlot.childExpanded = !childSlot.childExpanded;
                                                            }
                                                        }
                                                    }

                                                    RowLayout {
                                                        id: childInner
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.top: parent.top
                                                        anchors.leftMargin: 14
                                                        anchors.rightMargin: 12
                                                        anchors.topMargin: 11
                                                        spacing: 12

                                                        // Exact 36px left rail: shows circular context avatar if present (WhatsApp),
                                                        // or stays cleanly empty spacer if no context icon (DiDi Food)
                                                        Item {
                                                            Layout.preferredWidth: 36
                                                            Layout.preferredHeight: 36
                                                            Layout.alignment: Qt.AlignTop

                                                            ClippingRectangle {
                                                                visible: Boolean(childSlot.modelData.isContextImage) && (childSlot.modelData.iconSource || "").length > 0
                                                                anchors.fill: parent
                                                                radius: 18
                                                                color: Theme.primaryContainer

                                                                Image {
                                                                    anchors.fill: parent
                                                                    source: childSlot.modelData.iconSource || ""
                                                                    fillMode: Image.PreserveAspectCrop
                                                                    sourceSize.width: 72
                                                                    sourceSize.height: 72
                                                                    smooth: true
                                                                    mipmap: true
                                                                }
                                                            }
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            Layout.minimumWidth: 0
                                                            spacing: 2

                                                            RowLayout {
                                                                Layout.fillWidth: true
                                                                Layout.minimumWidth: 0
                                                                spacing: 5

                                                                Text {
                                                                    Layout.fillWidth: true
                                                                    Layout.minimumWidth: 0
                                                                    Layout.maximumWidth: implicitWidth
                                                                    elide: Text.ElideRight
                                                                    text: childSlot.modelData.summary || grpSlot.appName
                                                                    color: Theme.fgSurface
                                                                    font.family: Theme.fontSans
                                                                    font.pixelSize: 12
                                                                    font.weight: Font.DemiBold
                                                                }

                                                                Text {
                                                                    id: childTimeTxt
                                                                    text: "·  " + childSlot.modelData.time
                                                                    color: Theme.fgSurfaceVariant
                                                                    font.family: Theme.fontSans
                                                                    font.pixelSize: 11
                                                                }

                                                                Item { Layout.fillWidth: true }
                                                            }

                                                            Text {
                                                                Layout.fillWidth: true
                                                                Layout.minimumWidth: 0
                                                                visible: (childSlot.modelData.body || "").length > 0
                                                                text: childSlot.modelData.body
                                                                wrapMode: childSlot.childExpanded ? Text.WordWrap : Text.NoWrap
                                                                maximumLineCount: childSlot.childExpanded ? 12 : 1
                                                                elide: Text.ElideRight
                                                                color: Theme.fgSurfaceVariant
                                                                font.family: Theme.fontSans
                                                                font.pixelSize: 11
                                                            }

                                                            // Smoothly expanding/collapsing BigPicture + Action row
                                                            Item {
                                                                Layout.fillWidth: true
                                                                Layout.preferredHeight: childSlot.childExpanded ? childExtraCol.implicitHeight : 0
                                                                clip: true
                                                                opacity: childSlot.childExpanded ? 1.0 : 0.0

                                                                Behavior on Layout.preferredHeight {
                                                                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                                                }
                                                                Behavior on opacity {
                                                                    NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
                                                                }

                                                                ColumnLayout {
                                                                    id: childExtraCol
                                                                    anchors.left: parent.left
                                                                    anchors.right: parent.right
                                                                    anchors.top: parent.top
                                                                    spacing: 2

                                                                    BigImagePreview {
                                                                        src: childSlot.modelData.attachmentImage || childSlot.modelData.contextImage || ""
                                                                        onlyIfLarge: !(childSlot.modelData.attachmentImage || "").length
                                                                    }

                                                                    ActionRow {
                                                                        uid: childSlot.modelData.uid
                                                                        actions: childSlot.modelData.actions
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        // Separate hover dismiss × button (steady slot, zero reflow)
                                                        Rectangle {
                                                            Layout.preferredWidth: 24
                                                            Layout.preferredHeight: 24
                                                            Layout.alignment: Qt.AlignTop
                                                            radius: 12
                                                            readonly property bool shown: childHov.containsMouse || cDisM.containsMouse || cExpM.containsMouse
                                                            opacity: shown ? 1.0 : 0.0
                                                            color: cDisM.containsMouse
                                                                ? Theme.primaryContainer
                                                                : Theme.alpha(Theme.fgSurface, 0.10)
                                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "󰅖"
                                                                color: cDisM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                                                                font.family: Theme.fontMono
                                                                font.pixelSize: 11
                                                            }

                                                            MouseArea {
                                                                id: cDisM
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                enabled: parent.shown
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: childSlot.requestDismissChild()
                                                            }
                                                        }

                                                        // Dedicated expand/collapse chevron pill
                                                        Rectangle {
                                                            Layout.preferredWidth: 24
                                                            Layout.preferredHeight: 24
                                                            Layout.alignment: Qt.AlignTop
                                                            radius: 12
                                                            color: cExpM.containsMouse
                                                                ? Theme.surfaceContainerHighest
                                                                : Theme.alpha(Theme.fgSurface, 0.10)
                                                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: childSlot.childExpanded ? "󰅃" : "󰅀"
                                                                color: Theme.fgSurfaceVariant
                                                                font.family: Theme.fontMono
                                                                font.pixelSize: 12
                                                            }

                                                            MouseArea {
                                                                id: cExpM
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: childSlot.childExpanded = !childSlot.childExpanded
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Android 17 Notification Overflow Shelf (compact app-icon pill when cards extend below the fold)
                Item {
                    id: notifShelf
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 43
                    z: 20

                    readonly property bool hasOverflow: notifFlick.contentHeight > notifFlick.height + 6
                        && notifFlick.contentY < (notifFlick.contentHeight - notifFlick.height - 6)

                    readonly property int overflowCount: {
                        const cy = notifFlick.contentY;
                        const vh = notifFlick.height;
                        const _ch = notifFlick.contentHeight;
                        const _lh = notifListCol.implicitHeight;
                        const n = groupModel.count;
                        if (!hasOverflow || n === 0) return 0;

                        const cutoff = cy + vh - 34;
                        let cnt = 0;
                        for (let i = 0; i < n; i++) {
                            const slot = groupRepeater.itemAt(i);
                            if (slot && (slot.y + slot.height > cutoff)) cnt++;
                        }
                        return cnt;
                    }

                    readonly property bool shown: hasOverflow && overflowCount > 0
                    opacity: shown ? 1.0 : 0.0
                    visible: opacity > 0.01
                    transform: Translate {
                        y: notifShelf.shown ? 0 : 12
                        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    // Crisp 3px backing lip so the card above crops cleanly right above the rounded shelf
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.glassSurface
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 40
                        radius: 20
                        color: shelfM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            clip: true

                            // Stable delegates bound directly to groupModel so each icon smoothly
                            // pops/scales/slides into and out of the shelf as you scroll
                            Repeater {
                                model: groupModel

                                delegate: Item {
                                    id: shelfSlot
                                    required property string appIcon
                                    required property int index

                                    readonly property bool inShelf: {
                                        const cy = notifFlick.contentY;
                                        const vh = notifFlick.height;
                                        const _ch = notifFlick.contentHeight;
                                        const _lh = notifListCol.implicitHeight;
                                        if (!notifShelf.hasOverflow) return false;
                                        const slot = groupRepeater.itemAt(index);
                                        return slot !== null && (slot.y + slot.height > cy + vh - 34);
                                    }

                                    width: inShelf ? 26 : 0
                                    height: 22
                                    clip: false

                                    Behavior on width {
                                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                    }

                                    Item {
                                        width: 18
                                        height: 18
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter

                                        opacity: shelfSlot.inShelf ? 1.0 : 0.0
                                        scale: shelfSlot.inShelf ? 1.0 : 0.35
                                        transform: Translate {
                                            y: shelfSlot.inShelf ? 0 : -6
                                            Behavior on y { SpringAnimation { spring: Motion.popSpring; damping: Motion.popDamping } }
                                        }

                                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                        Behavior on scale { SpringAnimation { spring: Motion.popSpring; damping: Motion.popDamping } }

                                        Image {
                                            id: shelfIconImg
                                            anchors.fill: parent
                                            visible: shelfSlot.appIcon.length > 0 && status === Image.Ready
                                            source: shelfSlot.appIcon
                                            fillMode: Image.PreserveAspectFit
                                            sourceSize.width: 36
                                            sourceSize.height: 36
                                            smooth: true
                                            mipmap: true
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: !shelfIconImg.visible
                                            text: "󰂚"
                                            color: Theme.fgSurfaceVariant
                                            font.family: Theme.fontMono
                                            font.pixelSize: 13
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: shelfM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const maxY = Math.max(0, notifFlick.contentHeight - notifFlick.height);
                                shelfScrollAnim.to = Math.min(maxY, notifFlick.contentY + 200);
                                shelfScrollAnim.restart();
                            }
                        }
                    }
                }
            }

            // Expressive Shell Bottom Action Bar: [DND Circle] [   Clear all   ] [Settings Circle]
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Left pill: DND / Silent mode toggle
                Rectangle {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 38
                    radius: 19
                    color: ShellState.dnd
                        ? Theme.primary
                        : (dndBtnM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                    scale: dndBtnM.pressed ? 0.92 : 1.0

                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: ShellState.dnd ? "󰂛" : "󰂚"
                        color: ShellState.dnd ? Theme.fgPrimary : Theme.fgSurface
                        font.family: Theme.fontMono
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: dndBtnM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.dnd = !ShellState.dnd
                    }
                }

                // Center wide pill: Clear all
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 19
                    color: clearAllM.containsMouse && Notifications.count > 0
                        ? Theme.surfaceContainerHighest
                        : Theme.surfaceContainerHigh
                    opacity: Notifications.count > 0 ? 1.0 : 0.55
                    scale: clearAllM.pressed && Notifications.count > 0 ? 0.96 : 1.0

                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: "Clear all"
                        color: Theme.fgSurface
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: clearAllM
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: Notifications.count > 0
                        cursorShape: Qt.PointingHandCursor
                        onClicked: notifWin.animateClearAll()
                    }
                }

                // Right pill: Open Quick Settings / Controls
                Rectangle {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 38
                    radius: 19
                    color: qsBtnM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    scale: qsBtnM.pressed ? 0.92 : 1.0

                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒓"
                        color: Theme.fgSurface
                        font.family: Theme.fontMono
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: qsBtnM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.toggleOverlay("quicksettings")
                    }
                }
            }
        }
    }
}
