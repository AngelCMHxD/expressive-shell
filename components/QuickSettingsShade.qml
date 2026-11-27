import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../theme"
import "../services"

// Android 17 Material 3 Expressive Quick Settings Shade
PanelWindow {
    id: qsWin

    required property var modelData
    screen: modelData

    readonly property bool isOpen: ShellState.activeOverlay === "quicksettings"
    property bool windowVisible: false
    property bool morphStart: false
    property bool morphBehaviorsEnabled: false
    visible: windowVisible

    Timer {
        id: morphOutTimer
        interval: 45
        onTriggered: {
            if (!qsWin.isOpen) {
                qsWin.windowVisible = false;
                card.state = "closed";
            }
        }
    }

    // Active sub-page inside the control center: "" | "wifi" | "bluetooth" | "audio" | "settings" | "templates" | "wallpaper_settings" | "customize"
    property string activePage: ""
    property string passwordTargetSsid: ""
    property int pageSlideDir: 1

    onIsOpenChanged: {
        if (isOpen) {
            morphOutTimer.stop();
            passwordTargetSsid = "";
            const initial = ShellState.qsInitialPage || "";
            ShellState.qsInitialPage = "";
            if (initial) {
                openSubPage(initial);
            } else {
                activePage = "";
            }
            const doMorph = ShellState.overlaysShareRegion(ShellState.previousOverlay, "quicksettings")
                && ShellState.morphFromW > 40 && ShellState.morphFromH > 40;
            morphBehaviorsEnabled = false;
            morphStart = doMorph;
            if (doMorph) {
                pageSlideDir = ShellState.overlaySlideDir(ShellState.previousOverlay, "quicksettings");
                mainCol.opacity = 0.0;
                subPageCol.opacity = 0.0;
            } else {
                mainCol.opacity = 1.0;
                subPageCol.opacity = 1.0;
                mainPageSlide.x = 0;
                subPageSlide.x = 0;
            }
            card.state = doMorph ? "morph" : "closed";
            windowVisible = true;
            if (doMorph) morphBehaviorsEnabled = true;
            openTrigger.restart();
        } else {
            openTrigger.stop();
            if (ShellState.overlaysShareRegion("quicksettings", ShellState.activeOverlay)) {
                morphOutTimer.restart();
            } else {
                card.state = "closed";
            }
        }
    }

    function openSubPage(page) {
        pageSlideDir = 1;
        passwordTargetSsid = "";
        activePage = page;
        if (page === "wifi") SystemStatus.refreshWifiNetworks(true);
        else if (page === "bluetooth") SystemStatus.refreshBtDevices();
        else if (page === "audio") {
            syncAudioAppsModel();
            SystemStatus.refreshAudioDetails();
        } else if (page === "settings" || page === "templates") {
            ShellState.refreshTemplates();
        }
        if (card.state === "open") subPageSlideAnim.restart();
    }

    function goBackPage() {
        pageSlideDir = -1;
        passwordTargetSsid = "";
        if (activePage === "templates" || activePage === "wallpaper_settings") {
            activePage = "settings";
            subPageSlideAnim.restart();
        } else {
            activePage = "";
            mainPageSlideAnim.restart();
        }
    }

    // Incremental ListModel for per-app audio streams so dragging a slider never recreates delegates
    ListModel {
        id: audioAppsModel
    }

    function syncAudioAppsModel() {
        const list = (SystemStatus.audioApps || []).slice(0, 6);
        const nextIds = new Set(list.map(a => a.id));

        for (let i = audioAppsModel.count - 1; i >= 0; i--) {
            if (!nextIds.has(audioAppsModel.get(i).streamId)) {
                audioAppsModel.remove(i);
            }
        }

        for (let target = 0; target < list.length; target++) {
            const a = list[target];
            let cur = -1;
            for (let j = target; j < audioAppsModel.count; j++) {
                if (audioAppsModel.get(j).streamId === a.id) {
                    cur = j;
                    break;
                }
            }
            if (cur === -1) {
                audioAppsModel.insert(target, {
                    streamId: a.id,
                    name: a.name || "Audio stream",
                    media: a.media || "",
                    muted: Boolean(a.muted),
                    volume: Number(a.volume || 0)
                });
            } else {
                if (cur !== target) audioAppsModel.move(cur, target, 1);
                const row = audioAppsModel.get(target);
                if (row.name !== (a.name || "Audio stream")) audioAppsModel.setProperty(target, "name", a.name || "Audio stream");
                if (row.media !== (a.media || "")) audioAppsModel.setProperty(target, "media", a.media || "");
                if (row.muted !== Boolean(a.muted)) audioAppsModel.setProperty(target, "muted", Boolean(a.muted));
                if (Math.abs(row.volume - Number(a.volume || 0)) > 0.002) {
                    audioAppsModel.setProperty(target, "volume", Number(a.volume || 0));
                }
            }
        }
    }

    Connections {
        target: SystemStatus
        function onAudioAppsChanged() {
            qsWin.syncAudioAppsModel();
        }
    }

    Timer {
        id: openTrigger
        interval: 25
        onTriggered: {
            const wasMorph = qsWin.morphStart;
            qsWin.morphBehaviorsEnabled = true;
            qsWin.morphStart = false;
            card.state = "open";
            if (wasMorph) {
                if (qsWin.activePage === "") mainPageSlideAnim.restart();
                else subPageSlideAnim.restart();
            }
            ShellState.reportOverlayGeometry("quicksettings", 372, card.targetH, 12);
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

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.closeOverlay()
    }

    // =========================================================================
    // Android 17 Split-Track Expressive Slider (detached vertical handle + smart-flipping icon)
    // =========================================================================
    component A17Slider: Item {
        id: slider
        property string icon: ""
        property real value: 0.5
        property bool muted: false
        signal valueEdited(real v)

        Layout.fillWidth: true
        Layout.preferredHeight: 40

        // Local drag mirror so dragging is always instant and never fights external updates
        property real animValue: Math.max(0.0, Math.min(1.0, value))
        Behavior on animValue {
            enabled: !dragArea.isDragging
            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }

        readonly property real handleW: 4
        readonly property real gap: 5
        readonly property real minX: handleW / 2
        readonly property real maxX: Math.max(minX + 1, width - handleW / 2)
        readonly property real handleX: minX + (maxX - minX) * animValue
        readonly property real rightTrackW: Math.max(0, width - (handleX + handleW / 2 + gap))
        // Flip icon to the left of the handle before the right track gets too tight for it
        readonly property bool iconOnLeft: rightTrackW < 34

        Canvas {
            id: sliderCanvas
            anchors.fill: parent

            property real val: slider.animValue
            property color activeCol: slider.muted ? Theme.outlineVariant : Theme.primary
            property color trackCol: Theme.surfaceContainerHigh

            onValChanged: requestPaint()
            onActiveColChanged: requestPaint()
            onTrackColChanged: requestPaint()
            onWidthChanged: requestPaint()

            function drawAsymRect(ctx, x, y, w, h, rL, rR) {
                if (w <= 1) return;
                const rl = Math.min(rL, w / 2, h / 2);
                const rr = Math.min(rR, w / 2, h / 2);
                ctx.beginPath();
                ctx.moveTo(x + rl, y);
                ctx.lineTo(x + w - rr, y);
                ctx.quadraticCurveTo(x + w, y, x + w, y + rr);
                ctx.lineTo(x + w, y + h - rr);
                ctx.quadraticCurveTo(x + w, y + h, x + w - rr, y + h);
                ctx.lineTo(x + rl, y + h);
                ctx.quadraticCurveTo(x, y + h, x, y + h - rl);
                ctx.lineTo(x, y + rl);
                ctx.quadraticCurveTo(x, y, x + rl, y);
                ctx.closePath();
                ctx.fill();
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                const barH = 34;
                const barY = (height - barH) / 2;
                const gap = slider.gap;
                const handleW = slider.handleW;
                const handleX = slider.handleX;

                // Left active bar (fills cleanly all the way to handle at 100%, vanishes cleanly at 0%)
                const leftW = Math.max(0, handleX - handleW / 2 - gap);
                if (leftW > 1.5) {
                    ctx.fillStyle = activeCol;
                    drawAsymRect(ctx, 0, barY, leftW, barH, 12, 4);
                }

                // Detached tall vertical handle pill
                ctx.fillStyle = activeCol;
                drawAsymRect(ctx, handleX - handleW / 2, 1, handleW, height - 2, 2, 2);

                // Right inactive track (vanishes cleanly at 100%)
                const rightX = handleX + handleW / 2 + gap;
                const rightW = Math.max(0, width - rightX);
                if (rightW > 1.5) {
                    ctx.fillStyle = trackCol;
                    drawAsymRect(ctx, rightX, barY, rightW, barH, 4, 12);
                }
            }
        }

        // Decorative slider icon (never clickable): sits in the right track while there is room,
        // and flips smoothly to the left of the handle before it can be covered or clipped
        Text {
            id: rightSideIcon
            anchors.verticalCenter: parent.verticalCenter
            x: slider.width - 28
            text: slider.icon
            color: Theme.fgSurface
            font.family: Theme.fontMono
            font.pixelSize: 16
            opacity: slider.iconOnLeft ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        }

        Text {
            id: leftSideIcon
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(10, slider.handleX - slider.handleW / 2 - slider.gap - 28)
            text: slider.icon
            color: slider.muted ? Theme.fgSurface : Theme.fgPrimary
            font.family: Theme.fontMono
            font.pixelSize: 16
            opacity: slider.iconOnLeft ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            property bool isDragging: false
            property real pressX: 0

            function updateFromX(mx) {
                const span = Math.max(1, slider.maxX - slider.minX);
                const v = Math.max(0, Math.min(1, (mx - slider.minX) / span));
                slider.valueEdited(v);
            }
            onPressed: mouse => {
                isDragging = false;
                pressX = mouse.x;
                updateFromX(mouse.x);
            }
            onPositionChanged: mouse => {
                if (!pressed) return;
                if (!isDragging && Math.abs(mouse.x - pressX) > 4) {
                    isDragging = true;
                }
                if (isDragging) updateFromX(mouse.x);
            }
            onReleased: isDragging = false
            onCanceled: isDragging = false
        }
    }

    // =========================================================================
    // Android 17 Split-Action 2x1 Tile (left icon toggles on/off; body opens menu)
    // =========================================================================
    component SplitTile: Rectangle {
        id: stile
        property string icon: ""
        property string label: ""
        property string sublabel: ""
        property bool active: false
        property bool squishBoost: false
        property real expandAmt: (bodyMouse.pressed || iconMouse.pressed || squishBoost) ? 1.0 : 0.0
        signal toggleClicked()
        signal menuClicked()

        Behavior on expandAmt {
            SpringAnimation { spring: 16.0; damping: 0.52; epsilon: 0.002 }
        }

        Timer {
            id: stileImpulse
            interval: 45
            onTriggered: stile.squishBoost = false
        }

        function triggerSquish() {
            squishBoost = true;
            stileImpulse.restart();
        }

        height: 64
        // Android 17 M3E: full pill when inactive, expressive rounded-rect when active
        radius: active ? 20 : 32
        color: active
            ? (bodyMouse.containsMouse ? Theme.alpha(Theme.primaryContainer, 0.95) : Theme.primaryContainer)
            : (bodyMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)

        Behavior on radius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        // Body click opens configuration sub-menu
        MouseArea {
            id: bodyMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                stile.triggerSquish();
                stile.menuClicked();
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 12
            spacing: 10

            // Left toggle button (morphs concentrically with outer tile: circle inactive -> rounded squircle active)
            Rectangle {
                id: iconCircle
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46
                radius: stile.active ? 12 : 23
                color: stile.active
                    ? (iconMouse.containsMouse ? Theme.primary : Theme.alpha(Theme.primary, 0.24))
                    : (iconMouse.containsMouse ? Theme.outlineVariant : Theme.surfaceContainerHighest)

                scale: iconMouse.pressed ? 0.90 : (iconMouse.containsMouse ? 1.05 : 1.0)
                Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                Behavior on radius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Text {
                    anchors.centerIn: parent
                    text: stile.icon
                    color: stile.active
                        ? (iconMouse.containsMouse ? Theme.fgPrimary : Theme.fgPrimaryContainer)
                        : Theme.fgSurface
                    font.family: Theme.fontMono
                    font.pixelSize: 19
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                MouseArea {
                    id: iconMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        stile.triggerSquish();
                        stile.toggleClicked();
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: stile.label
                    elide: Text.ElideRight
                    color: stile.active ? Theme.fgPrimaryContainer : Theme.fgSurface
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    visible: stile.sublabel.length > 0
                    text: stile.sublabel
                    elide: Text.ElideRight
                    color: stile.active
                        ? Theme.alpha(Theme.fgPrimaryContainer, 0.78)
                        : Theme.fgSurfaceVariant
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                }
            }

            Text {
                text: "󰅂"
                color: stile.active
                    ? Theme.alpha(Theme.fgPrimaryContainer, 0.7)
                    : Theme.fgSurfaceVariant
                font.family: Theme.fontMono
                font.pixelSize: 14
            }
        }
    }

    // =========================================================================
    // Android 17 / Expressive Wide 2x1 Toggle Tile (vibrant primary squircle when active)
    // =========================================================================
    component WideTile: Rectangle {
        id: wtile
        property string icon: ""
        property string label: ""
        property string sublabel: ""
        property bool active: false
        property bool squishBoost: false
        property real expandAmt: (wm.pressed || squishBoost) ? 1.0 : 0.0
        signal clicked()

        Behavior on expandAmt {
            SpringAnimation { spring: 16.0; damping: 0.52; epsilon: 0.002 }
        }

        Timer {
            id: wtileImpulse
            interval: 45
            onTriggered: wtile.squishBoost = false
        }

        height: 58
        radius: active ? 18 : 29
        color: active
            ? Theme.primary
            : (wm.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)

        Behavior on radius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            spacing: 11

            Text {
                text: wtile.icon
                color: wtile.active ? Theme.fgPrimary : Theme.fgSurface
                font.family: Theme.fontMono
                font.pixelSize: 18
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: wtile.label
                    color: wtile.active ? Theme.fgPrimary : Theme.fgSurface
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                Text {
                    Layout.fillWidth: true
                    visible: wtile.sublabel.length > 0
                    elide: Text.ElideRight
                    text: wtile.sublabel
                    color: wtile.active ? Theme.alpha(Theme.fgPrimary, 0.78) : Theme.fgSurfaceVariant
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                }
            }
        }

        MouseArea {
            id: wm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                wtile.squishBoost = true;
                wtileImpulse.restart();
                wtile.clicked();
            }
        }
    }

    // =========================================================================
    // Android 17 Compact 1x1 Icon Tile (circle inactive -> glowing squircle active + immediate-neighbor squish)
    // =========================================================================
    component IconTile: Rectangle {
        id: itile
        property string icon: ""
        property string tooltip: ""
        property bool active: false
        property bool squishBoost: false
        property real expandAmt: (im.pressed || squishBoost) ? 1.0 : 0.0
        signal clicked()

        Behavior on expandAmt {
            SpringAnimation { spring: 16.0; damping: 0.52; epsilon: 0.002 }
        }

        Timer {
            id: itileImpulse
            interval: 45
            onTriggered: itile.squishBoost = false
        }

        height: 58
        // Exact Android 17 M3E morph: circle (29) inactive -> rounded squircle (18) active
        radius: active ? 18 : 29
        color: active
            ? Theme.primary
            : (im.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)

        Behavior on radius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Text {
            anchors.centerIn: parent
            text: itile.icon
            color: itile.active ? Theme.fgPrimary : Theme.fgSurface
            font.family: Theme.fontMono
            font.pixelSize: 20
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        MouseArea {
            id: im
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                itile.squishBoost = true;
                itileImpulse.restart();
                itile.clicked();
            }
        }
    }

    // =========================================================================
    // Main Pop-in M3E Control Center Card
    // =========================================================================
    Rectangle {
        id: card
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: qsWin.morphStart ? ShellState.morphFromRight : 12
        width: qsWin.morphStart ? ShellState.morphFromW : 372
        readonly property real maxCardHeight: Math.max(360, qsWin.height - 84)
        readonly property real targetH: Math.min(maxCardHeight, (qsWin.activePage === "" ? mainCol.implicitHeight : subPageCol.implicitHeight) + 32)
        height: qsWin.morphStart ? ShellState.morphFromH : targetH
        radius: Theme.radiusExtraLarge
        color: Theme.glassSurface
        border.width: 1
        border.color: Theme.glassBorder
        clip: true

        onTargetHChanged: if (qsWin.isOpen && !qsWin.morphStart) ShellState.reportOverlayGeometry("quicksettings", 372, targetH, 12)

        Behavior on anchors.rightMargin {
            enabled: qsWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }
        Behavior on width {
            enabled: qsWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }
        Behavior on height {
            enabled: qsWin.morphBehaviorsEnabled
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 }
        }

        focus: qsWin.isOpen
        Keys.onEscapePressed: {
            if (qsWin.activePage !== "") {
                qsWin.goBackPage();
            } else {
                ShellState.closeOverlay();
            }
        }

        MouseArea { anchors.fill: parent }

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
                        script: { if (!qsWin.isOpen) qsWin.windowVisible = false; }
                    }
                }
            }
        ]

        ParallelAnimation {
            id: mainPageSlideAnim
            NumberAnimation { target: mainPageSlide; property: "x"; from: qsWin.pageSlideDir * 28; to: 0; duration: 210; easing.type: Easing.OutCubic }
            NumberAnimation { target: mainCol; property: "opacity"; from: 0.0; to: 1.0; duration: 170; easing.type: Easing.OutQuad }
        }

        ParallelAnimation {
            id: subPageSlideAnim
            NumberAnimation { target: subPageSlide; property: "x"; from: qsWin.pageSlideDir * 28; to: 0; duration: 210; easing.type: Easing.OutCubic }
            NumberAnimation { target: subPageCol; property: "opacity"; from: 0.0; to: 1.0; duration: 170; easing.type: Easing.OutQuad }
        }

        // =====================================================================
        // PAGE 1: Main Expressive Shell / Android 17 Quick Settings View
        // =====================================================================
        ColumnLayout {
            id: mainCol
            visible: qsWin.activePage === ""
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 11
            transform: Translate { id: mainPageSlide; x: 0 }

            // Top action header (Expressive Shell style: Wallpapers & Lock left, Power dropdown right)
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: wpHdrM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                    Text { anchors.centerIn: parent; text: "󰸉"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 17 }
                    MouseArea { id: wpHdrM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleOverlay("wallpapers") }
                }

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: cfgHdrM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                    Text { anchors.centerIn: parent; text: "󰒓"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 17 }
                    MouseArea { id: cfgHdrM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: qsWin.openSubPage("settings") }
                }

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: lockHdrM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                    Text { anchors.centerIn: parent; text: "󰌾"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 16 }
                    MouseArea { id: lockHdrM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { ShellState.closeOverlay(); SystemStatus.lockSession(); } }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: pwrHdrRow.implicitWidth + 14
                    radius: 16
                    color: pwrHdrM.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                    RowLayout {
                        id: pwrHdrRow
                        anchors.centerIn: parent
                        spacing: 3
                        Text { text: "󰐥"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 17 }
                        Text { text: "󰅀"; color: Theme.fgSurfaceVariant; font.family: Theme.fontMono; font.pixelSize: 13 }
                    }

                    MouseArea { id: pwrHdrM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleOverlay("session") }
                }
            }

            // Brightness slider + circular companion button (Night / Dark toggle, matching Expressive Shell)
            RowLayout {
                visible: SystemStatus.hasBrightness
                Layout.fillWidth: true
                spacing: 8

                A17Slider {
                    icon: "󰃠"
                    value: SystemStatus.brightness
                    onValueEdited: v => SystemStatus.setBrightness(v)
                }

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 17
                    color: ShellState.darkMode ? Theme.primaryContainer : Theme.surfaceContainerHigh
                    scale: nightM.pressed ? 0.9 : 1.0
                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Text {
                        anchors.centerIn: parent
                        text: ShellState.darkMode ? "󰖔" : "󰖨"
                        color: ShellState.darkMode ? Theme.fgPrimaryContainer : Theme.fgSurface
                        font.family: Theme.fontMono
                        font.pixelSize: 16
                    }
                    MouseArea { id: nightM; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.darkMode = !ShellState.darkMode }
                }
            }

            // Volume slider + built-in Sound & Volume panel button
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                A17Slider {
                    icon: SystemStatus.muted ? "󰖁" : (SystemStatus.volume > 0.5 ? "󰕾" : "󰖀")
                    value: SystemStatus.volume
                    muted: SystemStatus.muted
                    onValueEdited: v => SystemStatus.setVolume(v)
                }

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 17
                    color: mixM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    scale: mixM.pressed ? 0.9 : 1.0
                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Text { anchors.centerIn: parent; text: "󰒓"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 16 }
                    MouseArea {
                        id: mixM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: qsWin.openSubPage("audio")
                    }
                }
            }

            // Configurable 2-column Control Center tile grid (ordered & toggled via ShellState.qsTiles)
            GridLayout {
                id: tilesGrid
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: ShellState.qsTiles

                    delegate: Item {
                        id: tileSlot
                        required property string modelData
                        readonly property string tid: modelData
                        readonly property bool isAvailable: tid !== "ppd" || SystemStatus.hasPowerProfiles

                        visible: isAvailable
                        Layout.fillWidth: true
                        Layout.preferredHeight: (tid === "wifi" || tid === "bluetooth") ? 62 : 58

                        // Wi-Fi SplitTile
                        SplitTile {
                            visible: tileSlot.tid === "wifi"
                            anchors.fill: parent
                            icon: SystemStatus.wifiIconForSignal(SystemStatus.wifiSignal)
                            label: "Wi-Fi"
                            sublabel: SystemStatus.wifiConnected
                                ? SystemStatus.wifiSsid
                                : (SystemStatus.wifiEnabled ? "Networks available" : "Off")
                            active: SystemStatus.wifiEnabled
                            onToggleClicked: SystemStatus.toggleWifi()
                            onMenuClicked: qsWin.openSubPage("wifi")
                        }

                        // Bluetooth SplitTile
                        SplitTile {
                            visible: tileSlot.tid === "bluetooth"
                            anchors.fill: parent
                            icon: SystemStatus.btPowered ? "󰂯" : "󰂲"
                            label: "Bluetooth"
                            sublabel: !SystemStatus.btAvailable
                                ? "Unavailable"
                                : (SystemStatus.btPowered
                                    ? (SystemStatus.btConnectedName || "On")
                                    : "Off")
                            active: SystemStatus.btPowered
                            onToggleClicked: SystemStatus.toggleBluetooth()
                            onMenuClicked: qsWin.openSubPage("bluetooth")
                        }

                        // Microphone WideTile
                        WideTile {
                            visible: tileSlot.tid === "mic"
                            anchors.fill: parent
                            icon: SystemStatus.micMuted ? "󰍭" : "󰍬"
                            label: "Microphone"
                            sublabel: SystemStatus.micMuted ? "Muted" : "Active"
                            active: !SystemStatus.micMuted
                            onClicked: SystemStatus.toggleMicMute()
                        }

                        // Desktop Widgets WideTile
                        WideTile {
                            visible: tileSlot.tid === "widgets"
                            anchors.fill: parent
                            icon: "󰕰"
                            label: "Widgets"
                            sublabel: ShellState.desktopWidgetsVisible ? "Shown" : "Hidden"
                            active: ShellState.desktopWidgetsVisible
                            onClicked: ShellState.desktopWidgetsVisible = !ShellState.desktopWidgetsVisible
                        }

                        // Dark / Light Theme WideTile
                        WideTile {
                            visible: tileSlot.tid === "theme"
                            anchors.fill: parent
                            icon: ShellState.darkMode ? "󰔎" : "󰖨"
                            label: ShellState.darkMode ? "Dark theme" : "Light theme"
                            active: ShellState.darkMode
                            onClicked: ShellState.darkMode = !ShellState.darkMode
                        }

                        // Taskbar Mode WideTile
                        WideTile {
                            visible: tileSlot.tid === "dock"
                            anchors.fill: parent
                            icon: ShellState.dockMode === "always" ? "󰘔" : (ShellState.dockMode === "popup" ? "󰘕" : "󰘖")
                            label: "Taskbar"
                            sublabel: ShellState.dockMode === "always" ? "Fixed" : (ShellState.dockMode === "popup" ? "Pop-up" : "Off")
                            active: ShellState.dockMode !== "off"
                            onClicked: ShellState.cycleDockMode()
                        }

                        // Do Not Disturb WideTile
                        WideTile {
                            visible: tileSlot.tid === "dnd"
                            anchors.fill: parent
                            icon: ShellState.dnd ? "󰂛" : "󰂚"
                            label: "Modes"
                            sublabel: ShellState.dnd ? "Do Not Disturb" : "Normal"
                            active: ShellState.dnd
                            onClicked: ShellState.dnd = !ShellState.dnd
                        }

                        // Power Profile (PPD) WideTile
                        WideTile {
                            visible: tileSlot.tid === "ppd"
                            anchors.fill: parent
                            icon: SystemStatus.powerProfile === "performance"
                                ? "󰓅"
                                : (SystemStatus.powerProfile === "power-saver" ? "󰌪" : "󰾅")
                            label: "Power"
                            sublabel: SystemStatus.powerProfileLabel
                            active: SystemStatus.powerProfile !== "balanced"
                            onClicked: SystemStatus.cyclePowerProfile()
                        }

                        // Screen Capture WideTile (greys out if grim is not installed)
                        WideTile {
                            visible: tileSlot.tid === "screenshot"
                            anchors.fill: parent
                            opacity: ShellState.hasGrim ? 1.0 : 0.45
                            icon: "󰹑"
                            label: "Screen capture"
                            sublabel: ShellState.hasGrim ? "Region & full" : "Install grim"
                            active: false
                            onClicked: if (ShellState.hasGrim) ShellState.toggleOverlay("screenshot")
                        }
                    }
                }
            }

            // Subtle Expressive Shell footer readout
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2

                Text {
                    text: "Umbriel · " + (SystemStatus.hasBattery
                        ? ((SystemStatus.batteryCharging ? "Charging " : "Battery ") + SystemStatus.batteryPercent + "%")
                        : "Desktop")
                    color: Theme.fgSurfaceVariant
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    font.weight: Font.Medium
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: Wallpaper.useAwww ? "awww" : "Static BG"
                    color: Theme.fgSurfaceVariant
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                }
            }
        }

        // =====================================================================
        // PAGE 2: Inline Wi-Fi / Bluetooth Sub-Menu
        // =====================================================================
        ColumnLayout {
            id: subPageCol
            visible: qsWin.activePage !== ""
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 12
            transform: Translate { id: subPageSlide; x: 0 }

            // Sub-page header: Back + Title + Scan + Power Switch
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: backM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    Text { anchors.centerIn: parent; text: "󰁍"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 16 }
                    MouseArea {
                        id: backM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: qsWin.goBackPage()
                    }
                }

                Text {
                    text: qsWin.activePage === "wifi"
                        ? "Internet & Wi-Fi"
                        : (qsWin.activePage === "bluetooth"
                            ? "Bluetooth"
                            : (qsWin.activePage === "audio"
                                ? "Sound & volume"
                                : (qsWin.activePage === "templates"
                                    ? "App templates"
                                    : (qsWin.activePage === "wallpaper_settings"
                                        ? "Wallpaper"
                                        : (qsWin.activePage === "customize" ? "Customize bar & controls" : "Shell settings")))))
                    color: Theme.fgSurface
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                // Refresh / Scan button
                Rectangle {
                    visible: qsWin.activePage !== "settings" && qsWin.activePage !== "wallpaper_settings" && qsWin.activePage !== "customize"
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: scanM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    readonly property bool isScanning: (qsWin.activePage === "wifi" && SystemStatus.wifiScanning)
                        || (qsWin.activePage === "bluetooth" && SystemStatus.btScanning)
                        || (qsWin.activePage === "templates" && ShellState.syncingTemplates)

                    Text {
                        anchors.centerIn: parent
                        visible: !parent.isScanning
                        text: "󰑐"
                        color: Theme.fgSurface
                        font.family: Theme.fontMono
                        font.pixelSize: 15
                    }

                    // Pixel-centered Canvas M3 arc spinner (same as LockScreen, zero font-glyph wobble)
                    Canvas {
                        id: scanSpinner
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        visible: parent.isScanning
                        property color col: Theme.primary
                        onColChanged: requestPaint()
                        onVisibleChanged: if (visible) requestPaint()
                        Component.onCompleted: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            ctx.strokeStyle = col;
                            ctx.lineWidth = 2.0;
                            ctx.lineCap = "round";
                            ctx.beginPath();
                            ctx.arc(width / 2, height / 2, 6.5, 0, Math.PI * 1.45, false);
                            ctx.stroke();
                        }
                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 850
                            loops: Animation.Infinite
                            running: scanSpinner.visible
                        }
                    }
                    MouseArea {
                        id: scanM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (qsWin.activePage === "wifi") SystemStatus.refreshWifiNetworks(true);
                            else if (qsWin.activePage === "bluetooth") SystemStatus.scanBluetooth();
                            else if (qsWin.activePage === "audio") SystemStatus.refreshAudioDetails();
                            else if (qsWin.activePage === "templates") ShellState.syncTemplates();
                            else if (qsWin.activePage === "templates") ShellState.refreshTemplates();
                        }
                    }
                }

                // Power toggle pill (Wi-Fi / Bluetooth only)
                Rectangle {
                    visible: qsWin.activePage === "wifi" || qsWin.activePage === "bluetooth"
                    readonly property bool isOn: qsWin.activePage === "wifi" ? SystemStatus.wifiEnabled : SystemStatus.btPowered
                    Layout.preferredHeight: 30
                    Layout.preferredWidth: 52
                    radius: 15
                    opacity: (qsWin.activePage === "bluetooth" && !SystemStatus.btAvailable) ? 0.45 : 1.0
                    color: isOn ? Theme.primary : Theme.surfaceContainerHighest
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.isOn ? (parent.width - width - 3) : 3
                        width: 24
                        height: 24
                        radius: 12
                        color: parent.isOn ? Theme.fgPrimary : Theme.fgSurfaceVariant
                        Behavior on x { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (qsWin.activePage === "wifi") SystemStatus.toggleWifi();
                            else SystemStatus.toggleBluetooth();
                        }
                    }
                }
            }

            // --- WI-FI NETWORK LIST ---
            ColumnLayout {
                visible: qsWin.activePage === "wifi"
                Layout.fillWidth: true
                spacing: 6

                // Inline Wi-Fi password bar when connecting to a secured network
                Rectangle {
                    visible: qsWin.passwordTargetSsid.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 21
                    color: Theme.surfaceContainerHigh
                    border.width: 1.5
                    border.color: Theme.primary

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 6
                        spacing: 8

                        TextInput {
                            id: wifiPwInput
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            clip: true
                            Keys.onReturnPressed: {
                                SystemStatus.connectWifi(qsWin.passwordTargetSsid, text);
                                text = "";
                                qsWin.passwordTargetSsid = "";
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: wifiPwInput.text.length === 0
                                text: "Password for " + qsWin.passwordTargetSsid
                                color: Theme.fgSurfaceVariant
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            radius: 15
                            color: Theme.primary
                            Text { anchors.centerIn: parent; text: "󰁔"; color: Theme.fgPrimary; font.family: Theme.fontMono; font.pixelSize: 14 }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    SystemStatus.connectWifi(qsWin.passwordTargetSsid, wifiPwInput.text);
                                    wifiPwInput.text = "";
                                    qsWin.passwordTargetSsid = "";
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: SystemStatus.wifiStatusMsg.length > 0
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: SystemStatus.wifiStatusMsg
                    color: Theme.primary
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                }

                Rectangle {
                    visible: !SystemStatus.wifiEnabled || SystemStatus.wifiNetworks.length === 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    radius: Theme.radiusLarge
                    color: Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: !SystemStatus.wifiEnabled
                            ? "Wi-Fi is turned off"
                            : (SystemStatus.wifiScanning ? "Scanning networks..." : "No networks found")
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                    }
                }

                Repeater {
                    model: SystemStatus.wifiEnabled ? SystemStatus.wifiNetworks.slice(0, 7) : []

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        radius: modelData.inUse ? 18 : 14
                        color: modelData.inUse
                            ? Theme.primaryContainer
                            : (wm.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 10

                            Text {
                                text: modelData.signal >= 85 ? "󰤨" : (modelData.signal >= 65 ? "󰤥" : (modelData.signal >= 40 ? "󰤢" : "󰤟"))
                                color: modelData.inUse ? Theme.fgPrimaryContainer : Theme.fgSurface
                                font.family: Theme.fontMono
                                font.pixelSize: 16
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelData.ssid
                                    color: modelData.inUse ? Theme.fgPrimaryContainer : Theme.fgSurface
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: modelData.inUse ? Font.DemiBold : Font.Normal
                                }
                                Text {
                                    visible: modelData.inUse
                                    text: "Connected · click to disconnect"
                                    color: Theme.alpha(Theme.fgPrimaryContainer, 0.8)
                                    font.family: Theme.fontSans
                                    font.pixelSize: 10
                                }
                            }

                            Text {
                                visible: modelData.secured && !modelData.inUse
                                text: "󰌾"
                                color: Theme.fgSurfaceVariant
                                font.family: Theme.fontMono
                                font.pixelSize: 12
                            }

                            Text {
                                text: modelData.signal + "%"
                                color: modelData.inUse ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                                font.family: Theme.fontSans
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: wm
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (modelData.inUse) {
                                    SystemStatus.disconnectWifi(modelData.ssid);
                                } else if (mouse.button === Qt.RightButton && modelData.secured) {
                                    qsWin.passwordTargetSsid = modelData.ssid;
                                    wifiPwInput.forceActiveFocus();
                                } else {
                                    SystemStatus.connectWifi(modelData.ssid, "");
                                }
                            }
                        }
                    }
                }
            }

            // --- BLUETOOTH DEVICE LIST ---
            ColumnLayout {
                visible: qsWin.activePage === "bluetooth"
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    visible: !SystemStatus.btAvailable || !SystemStatus.btPowered || SystemStatus.btDevices.length === 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    radius: Theme.radiusLarge
                    color: Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: !SystemStatus.btAvailable
                            ? "No Bluetooth adapter detected"
                            : (!SystemStatus.btPowered
                                ? "Bluetooth is turned off"
                                : (SystemStatus.btScanning ? "Scanning for devices..." : "No paired devices — press 󰑐 to scan"))
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                    }
                }

                Repeater {
                    model: (SystemStatus.btAvailable && SystemStatus.btPowered) ? SystemStatus.btDevices.slice(0, 7) : []

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        radius: modelData.connected ? 18 : 14
                        color: modelData.connected
                            ? Theme.primaryContainer
                            : (bm.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 10

                            Text {
                                text: modelData.connected ? "󰂱" : "󰂯"
                                color: modelData.connected ? Theme.fgPrimaryContainer : Theme.fgSurface
                                font.family: Theme.fontMono
                                font.pixelSize: 16
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelData.name
                                    color: modelData.connected ? Theme.fgPrimaryContainer : Theme.fgSurface
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: modelData.connected ? Font.DemiBold : Font.Normal
                                }
                                Text {
                                    text: modelData.connected ? "Connected · click to disconnect" : "Click to connect"
                                    color: modelData.connected
                                        ? Theme.alpha(Theme.fgPrimaryContainer, 0.8)
                                        : Theme.fgSurfaceVariant
                                    font.family: Theme.fontSans
                                    font.pixelSize: 10
                                }
                            }
                        }

                        MouseArea {
                            id: bm
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SystemStatus.toggleBtDevice(modelData.mac, modelData.connected)
                        }
                    }
                }
            }

            // --- BUILT-IN SOUND & VOLUME CONTROL PANEL ---
            ColumnLayout {
                visible: qsWin.activePage === "audio"
                Layout.fillWidth: true
                spacing: 12

                // Master Output Volume + side mute button
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Output volume"
                            color: Theme.fgSurfaceVariant
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: SystemStatus.muted ? "Muted" : (Math.round(SystemStatus.volume * 100) + "%")
                            color: SystemStatus.muted ? Theme.error : Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        A17Slider {
                            icon: SystemStatus.muted ? "󰖁" : (SystemStatus.volume > 0.5 ? "󰕾" : "󰖀")
                            value: SystemStatus.volume
                            muted: SystemStatus.muted
                            onValueEdited: v => SystemStatus.setVolume(v)
                        }

                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            radius: 17
                            color: SystemStatus.muted
                                ? Theme.error
                                : (outMuteM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                            scale: outMuteM.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            Text {
                                anchors.centerIn: parent
                                text: SystemStatus.muted ? "󰖁" : "󰕾"
                                color: SystemStatus.muted ? Theme.fgError : Theme.fgSurface
                                font.family: Theme.fontMono
                                font.pixelSize: 16
                            }

                            MouseArea {
                                id: outMuteM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: SystemStatus.toggleMute()
                            }
                        }
                    }
                }

                // Microphone Input Volume + side mute button
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Microphone"
                            color: Theme.fgSurfaceVariant
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: SystemStatus.micMuted ? "Muted" : (Math.round(SystemStatus.micVolume * 100) + "%")
                            color: SystemStatus.micMuted ? Theme.error : Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        A17Slider {
                            icon: SystemStatus.micMuted ? "󰍭" : "󰍬"
                            value: SystemStatus.micVolume
                            muted: SystemStatus.micMuted
                            onValueEdited: v => SystemStatus.setMicVolume(v)
                        }

                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            radius: 17
                            color: SystemStatus.micMuted
                                ? Theme.error
                                : (micMuteM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                            scale: micMuteM.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            Text {
                                anchors.centerIn: parent
                                text: SystemStatus.micMuted ? "󰍭" : "󰍬"
                                color: SystemStatus.micMuted ? Theme.fgError : Theme.fgSurface
                                font.family: Theme.fontMono
                                font.pixelSize: 16
                            }

                            MouseArea {
                                id: micMuteM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: SystemStatus.toggleMicMute()
                            }
                        }
                    }
                }

                // Per-App Audio Streams (backed by incremental ListModel so dragging never breaks)
                ColumnLayout {
                    visible: audioAppsModel.count > 0
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Apps"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: audioAppsModel

                        delegate: ColumnLayout {
                            id: appAudioRow
                            required property int streamId
                            required property string name
                            required property string media
                            required property bool muted
                            required property real volume

                            Layout.fillWidth: true
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: appAudioRow.media ? (appAudioRow.name + " · " + appAudioRow.media) : appAudioRow.name
                                    color: Theme.fgSurface
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                                Text {
                                    text: appAudioRow.muted ? "Muted" : (Math.round(appAudioRow.volume * 100) + "%")
                                    color: appAudioRow.muted ? Theme.error : Theme.fgSurfaceVariant
                                    font.family: Theme.fontSans
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                A17Slider {
                                    icon: appAudioRow.muted ? "󰖁" : "󰎆"
                                    value: Math.min(1.0, appAudioRow.volume)
                                    muted: appAudioRow.muted
                                    onValueEdited: v => SystemStatus.setAppVolume(appAudioRow.streamId, v)
                                }

                                Rectangle {
                                    Layout.preferredWidth: 34
                                    Layout.preferredHeight: 34
                                    radius: 17
                                    color: appAudioRow.muted
                                        ? Theme.error
                                        : (appMuteM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                                    scale: appMuteM.pressed ? 0.9 : 1.0
                                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: appAudioRow.muted ? "󰖁" : "󰕾"
                                        color: appAudioRow.muted ? Theme.fgError : Theme.fgSurface
                                        font.family: Theme.fontMono
                                        font.pixelSize: 15
                                    }

                                    MouseArea {
                                        id: appMuteM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: SystemStatus.toggleAppMute(appAudioRow.streamId)
                                    }
                                }
                            }
                        }
                    }
                }

                // Output Device Picker
                ColumnLayout {
                    visible: SystemStatus.audioSinks.length > 0
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Output device"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 3

                        Repeater {
                            id: sinkRepeater
                            model: SystemStatus.audioSinks

                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool isFirst: index === 0
                                readonly property bool isLast: index === sinkRepeater.count - 1

                                width: parent.width
                                height: 44
                                topLeftRadius: modelData.isDefault ? 22 : (isFirst ? 18 : 6)
                                topRightRadius: modelData.isDefault ? 22 : (isFirst ? 18 : 6)
                                bottomLeftRadius: modelData.isDefault ? 22 : (isLast ? 18 : 6)
                                bottomRightRadius: modelData.isDefault ? 22 : (isLast ? 18 : 6)

                                color: modelData.isDefault
                                    ? Theme.primaryContainer
                                    : (sinkM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                                Behavior on color { ColorAnimation { duration: Motion.fast } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 10

                                    Text {
                                        text: modelData.isDefault ? "󰕾" : "󰓃"
                                        color: modelData.isDefault ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                                        font.family: Theme.fontMono
                                        font.pixelSize: 15
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: modelData.description
                                        color: modelData.isDefault ? Theme.fgPrimaryContainer : Theme.fgSurface
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        font.weight: modelData.isDefault ? Font.DemiBold : Font.Normal
                                    }

                                    Text {
                                        visible: modelData.isDefault
                                        text: "󰄬"
                                        color: Theme.fgPrimaryContainer
                                        font.family: Theme.fontMono
                                        font.pixelSize: 14
                                    }
                                }

                                MouseArea {
                                    id: sinkM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: SystemStatus.setDefaultSink(modelData.name)
                                }
                            }
                        }
                    }
                }

                // Input Device Picker
                ColumnLayout {
                    visible: SystemStatus.audioSources.length > 0
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Input device"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 3

                        Repeater {
                            id: srcRepeater
                            model: SystemStatus.audioSources

                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool isFirst: index === 0
                                readonly property bool isLast: index === srcRepeater.count - 1

                                width: parent.width
                                height: 44
                                topLeftRadius: modelData.isDefault ? 22 : (isFirst ? 18 : 6)
                                topRightRadius: modelData.isDefault ? 22 : (isFirst ? 18 : 6)
                                bottomLeftRadius: modelData.isDefault ? 22 : (isLast ? 18 : 6)
                                bottomRightRadius: modelData.isDefault ? 22 : (isLast ? 18 : 6)

                                color: modelData.isDefault
                                    ? Theme.primaryContainer
                                    : (srcM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                                Behavior on color { ColorAnimation { duration: Motion.fast } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 10

                                    Text {
                                        text: "󰍬"
                                        color: modelData.isDefault ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                                        font.family: Theme.fontMono
                                        font.pixelSize: 15
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: modelData.description
                                        color: modelData.isDefault ? Theme.fgPrimaryContainer : Theme.fgSurface
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        font.weight: modelData.isDefault ? Font.DemiBold : Font.Normal
                                    }

                                    Text {
                                        visible: modelData.isDefault
                                        text: "󰄬"
                                        color: Theme.fgPrimaryContainer
                                        font.family: Theme.fontMono
                                        font.pixelSize: 14
                                    }
                                }

                                MouseArea {
                                    id: srcM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: SystemStatus.setDefaultSource(modelData.name)
                                }
                            }
                        }
                    }
                }
            }

            // --- SHELL SETTINGS & PATH CONFIG PANEL ---
            ColumnLayout {
                visible: qsWin.activePage === "settings"
                Layout.fillWidth: true
                spacing: 12

                // Profile picture path + smooth crossfading circular preview + file picker
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        text: "Profile picture"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ClippingRectangle {
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 38
                            radius: 19
                            color: Theme.primaryContainer

                            Text {
                                anchors.centerIn: parent
                                text: "󰀄"
                                color: Theme.fgPrimaryContainer
                                font.family: Theme.fontMono
                                font.pixelSize: 18
                                opacity: avatarPrevImg.status === Image.Ready ? 0.0 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }

                            Image {
                                id: avatarPrevImg
                                anchors.fill: parent
                                source: ShellState.resolvedUserAvatarPath ? ("file://" + ShellState.resolvedUserAvatarPath) : ""
                                fillMode: Image.PreserveAspectCrop
                                opacity: status === Image.Ready ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                smooth: true
                                mipmap: true
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            radius: 19
                            color: Theme.surfaceContainerHigh
                            border.width: avatarInput.activeFocus ? 1.5 : 1
                            border.color: avatarInput.activeFocus ? Theme.primary : Theme.glassBorder

                            TextInput {
                                id: avatarInput
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                clip: true
                                text: ShellState.userAvatarPath
                                onEditingFinished: {
                                    const v = text.trim();
                                    ShellState.userAvatarPath = v.length > 0 ? v : "~/.face";
                                }
                                Keys.onReturnPressed: {
                                    focus = false;
                                    editingFinished();
                                }
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 18
                            color: pickAvM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            scale: pickAvM.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Text { anchors.centerIn: parent; text: "󰉋"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                            MouseArea {
                                id: pickAvM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.pickAvatarFile()
                            }
                        }
                    }
                }

                // Screenshots folder path + folder picker
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        text: "Screenshots folder"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            radius: 19
                            color: Theme.surfaceContainerHigh
                            border.width: shotDirInput.activeFocus ? 1.5 : 1
                            border.color: shotDirInput.activeFocus ? Theme.primary : Theme.glassBorder

                            TextInput {
                                id: shotDirInput
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                clip: true
                                text: ShellState.screenshotsDir
                                onEditingFinished: {
                                    const v = text.trim();
                                    ShellState.screenshotsDir = v.length > 0 ? v : "~/Pictures/Screenshots";
                                }
                                Keys.onReturnPressed: {
                                    focus = false;
                                    editingFinished();
                                }
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 18
                            color: pickShotM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            scale: pickShotM.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Text { anchors.centerIn: parent; text: "󰉋"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                            MouseArea {
                                id: pickShotM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.pickScreenshotsFolder()
                            }
                        }
                    }
                }

                // Taskbar mode 3-way M3E segmented control
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        text: "Taskbar mode"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: [
                                { id: "always", label: "Fixed" },
                                { id: "popup", label: "Pop-up" },
                                { id: "off", label: "Off" }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected: ShellState.dockMode === modelData.id
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                radius: selected ? 17 : 10
                                color: selected ? Theme.primary : Theme.surfaceContainerHigh
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Behavior on radius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: selected ? Theme.fgPrimary : Theme.fgSurface
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: selected ? Font.DemiBold : Font.Medium
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ShellState.dockMode = modelData.id
                                }
                            }
                        }
                    }
                }

                // Shell toggles (24h clock + Desktop widgets)
                Column {
                    Layout.fillWidth: true
                    spacing: 3

                    // 24-hour clock
                    Rectangle {
                        width: parent.width
                        height: 46
                        topLeftRadius: 18; topRightRadius: 18
                        bottomLeftRadius: 6; bottomRightRadius: 6
                        color: Theme.surfaceContainerHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            Text {
                                Layout.fillWidth: true
                                text: "24-hour clock"
                                color: Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            Rectangle {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 24
                                radius: 12
                                color: ShellState.use24HourClock ? Theme.primary : Theme.surfaceContainerHighest
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: ShellState.use24HourClock ? (parent.width - width - 3) : 3
                                    width: 18; height: 18; radius: 9
                                    color: ShellState.use24HourClock ? Theme.fgPrimary : Theme.fgSurfaceVariant
                                    Behavior on x { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.use24HourClock = !ShellState.use24HourClock
                        }
                    }

                    // Desktop widgets
                    Rectangle {
                        width: parent.width
                        height: 46
                        radius: 6
                        color: Theme.surfaceContainerHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            Text {
                                Layout.fillWidth: true
                                text: "Desktop widgets"
                                color: Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            Rectangle {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 24
                                radius: 12
                                color: ShellState.desktopWidgetsVisible ? Theme.primary : Theme.surfaceContainerHighest
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: ShellState.desktopWidgetsVisible ? (parent.width - width - 3) : 3
                                    width: 18; height: 18; radius: 9
                                    color: ShellState.desktopWidgetsVisible ? Theme.fgPrimary : Theme.fgSurfaceVariant
                                    Behavior on x { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.desktopWidgetsVisible = !ShellState.desktopWidgetsVisible
                        }
                    }

                    // Polkit authentication agent
                    Rectangle {
                        width: parent.width
                        height: 46
                        topLeftRadius: 6; topRightRadius: 6
                        bottomLeftRadius: 18; bottomRightRadius: 18
                        color: Theme.surfaceContainerHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            Text {
                                Layout.fillWidth: true
                                text: "Polkit authentication agent"
                                color: Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            Rectangle {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 24
                                radius: 12
                                color: ShellState.polkitEnabled ? Theme.primary : Theme.surfaceContainerHighest
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: ShellState.polkitEnabled ? (parent.width - width - 3) : 3
                                    width: 18; height: 18; radius: 9
                                    color: ShellState.polkitEnabled ? Theme.fgPrimary : Theme.fgSurfaceVariant
                                    Behavior on x { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.polkitEnabled = !ShellState.polkitEnabled
                        }
                    }
                }

                // Idle & Auto-lock settings (swayidle) — greyed out with tooltip if swayidle is not installed
                Rectangle {
                    id: idleCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: idleCfgCol.implicitHeight + 20
                    radius: 18
                    color: Theme.surfaceContainerHigh
                    opacity: ShellState.hasSwayidle ? 1.0 : 0.48

                    MouseArea {
                        id: idleDisabledHover
                        visible: !ShellState.hasSwayidle
                        anchors.fill: parent
                        hoverEnabled: true
                        z: 5
                    }

                    // Tooltip when swayidle is missing
                    Rectangle {
                        visible: !ShellState.hasSwayidle && idleDisabledHover.containsMouse
                        z: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 4
                        width: Math.min(parent.width, idleTipTxt.implicitWidth + 18)
                        height: idleTipTxt.implicitHeight + 10
                        radius: 10
                        color: Theme.surfaceContainerHighest
                        border.width: 1
                        border.color: Theme.glassBorder

                        Text {
                            id: idleTipTxt
                            anchors.centerIn: parent
                            text: "Install `swayidle` to enable idle auto-lock & sleep"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                    }

                    ColumnLayout {
                        id: idleCfgCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text { text: "󰒲"; color: Theme.primary; font.family: Theme.fontMono; font.pixelSize: 15 }
                            Text {
                                Layout.fillWidth: true
                                text: "Idle auto-lock & sleep"
                                color: Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }

                            Rectangle {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 22
                                radius: 11
                                color: (ShellState.hasSwayidle && ShellState.idleEnabled) ? Theme.primary : Theme.surfaceContainerHighest
                                Behavior on color { ColorAnimation { duration: Motion.fast } }

                                Rectangle {
                                    width: 16; height: 16; radius: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: (ShellState.hasSwayidle && ShellState.idleEnabled) ? 19 : 3
                                    color: (ShellState.hasSwayidle && ShellState.idleEnabled) ? Theme.fgPrimary : Theme.fgSurfaceVariant
                                    Behavior on x { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: ShellState.hasSwayidle
                                    cursorShape: ShellState.hasSwayidle ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: ShellState.idleEnabled = !ShellState.idleEnabled
                                }
                            }
                        }

                        // Lock timeout chips
                        RowLayout {
                            visible: ShellState.hasSwayidle && ShellState.idleEnabled
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: "Lock"
                                Layout.preferredWidth: 46
                                color: Theme.fgSurfaceVariant
                                font.family: Theme.fontSans
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }

                            Repeater {
                                model: [
                                    { sec: 120,  label: "2m" },
                                    { sec: 300,  label: "5m" },
                                    { sec: 600,  label: "10m" },
                                    { sec: 1800, label: "30m" },
                                    { sec: 0,    label: "Off" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: ShellState.idleLockSec === modelData.sec
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 24
                                    radius: 12
                                    color: sel ? Theme.primary : Theme.surfaceContainerHighest
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: sel ? Theme.fgPrimary : Theme.fgSurface
                                        font.family: Theme.fontSans
                                        font.pixelSize: 10
                                        font.weight: sel ? Font.DemiBold : Font.Medium
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ShellState.idleLockSec = modelData.sec
                                    }
                                }
                            }
                        }

                        // Suspend timeout chips
                        RowLayout {
                            visible: ShellState.hasSwayidle && ShellState.idleEnabled
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: "Sleep"
                                Layout.preferredWidth: 46
                                color: Theme.fgSurfaceVariant
                                font.family: Theme.fontSans
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }

                            Repeater {
                                model: [
                                    { sec: 600,  label: "10m" },
                                    { sec: 900,  label: "15m" },
                                    { sec: 1800, label: "30m" },
                                    { sec: 3600, label: "1h" },
                                    { sec: 0,    label: "Off" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: ShellState.idleSleepSec === modelData.sec
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 24
                                    radius: 12
                                    color: sel ? Theme.primary : Theme.surfaceContainerHighest
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: sel ? Theme.fgPrimary : Theme.fgSurface
                                        font.family: Theme.fontSans
                                        font.pixelSize: 10
                                        font.weight: sel ? Font.DemiBold : Font.Medium
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ShellState.idleSleepSec = modelData.sec
                                    }
                                }
                            }
                        }
                    }
                }

                // Google Calendar (GNOME Online Accounts) — greyed out with tooltip if goa / goa-gtk aren't installed
                Rectangle {
                    id: goaBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 21
                    color: (ShellState.hasGoaCalendar && goaBtnM.containsMouse) ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    opacity: ShellState.hasGoaCalendar ? 1.0 : 0.48
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    // Tooltip when GOA or goa-gtk is missing
                    Rectangle {
                        visible: !ShellState.hasGoaCalendar && goaBtnM.containsMouse
                        z: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 4
                        width: Math.min(parent.width, goaTipTxt.implicitWidth + 18)
                        height: goaTipTxt.implicitHeight + 10
                        radius: 10
                        color: Theme.surfaceContainerHighest
                        border.width: 1
                        border.color: Theme.glassBorder

                        Text {
                            id: goaTipTxt
                            anchors.centerIn: parent
                            text: "Install `gnome-online-accounts` & `gnome-online-accounts-gtk`"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text { text: "󰊭"; color: Theme.primary; font.family: Theme.fontMono; font.pixelSize: 16 }
                        Text {
                            Layout.fillWidth: true
                            text: "Google Calendar"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        Text {
                            text: CalendarEvents.accounts.length > 0
                                ? (CalendarEvents.accounts.length + " connected")
                                : (ShellState.hasGoaCalendar ? "Connect" : "Unavailable")
                            color: Theme.fgSurfaceVariant
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                        }
                        Text { text: "󰅂"; color: Theme.fgSurfaceVariant; font.family: Theme.fontMono; font.pixelSize: 15 }
                    }

                    MouseArea {
                        id: goaBtnM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: ShellState.hasGoaCalendar ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (!ShellState.hasGoaCalendar) return;
                            ShellState.closeOverlay();
                            CalendarEvents.openOnlineAccounts();
                        }
                    }
                }

                // Wallpaper settings sub-menu button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 21
                    color: wpSetBtnM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text { text: "󰸉"; color: Theme.primary; font.family: Theme.fontMono; font.pixelSize: 16 }
                        Text {
                            Layout.fillWidth: true
                            text: "Wallpaper"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        Text {
                            text: Wallpaper.autoRotate ? "Auto" : (Wallpaper.useAwww ? "awww" : "Static")
                            color: Theme.fgSurfaceVariant
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                        }
                        Text { text: "󰅂"; color: Theme.fgSurfaceVariant; font.family: Theme.fontMono; font.pixelSize: 15 }
                    }

                    MouseArea {
                        id: wpSetBtnM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: qsWin.openSubPage("wallpaper_settings")
                    }
                }

                // App templates sub-menu button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 21
                    color: tplBtnM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text { text: "󰏘"; color: Theme.primary; font.family: Theme.fontMono; font.pixelSize: 16 }
                        Text {
                            Layout.fillWidth: true
                            text: "App templates"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        Text {
                            text: ShellState.availableTemplates.length > 0 ? String(ShellState.availableTemplates.length) : ""
                            color: Theme.fgSurfaceVariant
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                        }
                        Text { text: "󰅂"; color: Theme.fgSurfaceVariant; font.family: Theme.fontMono; font.pixelSize: 15 }
                    }

                    MouseArea {
                        id: tplBtnM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: qsWin.openSubPage("templates")
                    }
                }

                // Hidden tray apps management (only shown when tray apps are running or hidden)
                ColumnLayout {
                    visible: SystemTray.items.values.length > 0 || ShellState.hiddenTrayIds.length > 0
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Background tray icons"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: SystemTray.items

                            delegate: Rectangle {
                                required property var modelData
                                readonly property string tid: String(modelData.id || modelData.title || "")
                                readonly property bool shown: !ShellState.isTrayHidden(tid)

                                height: 28
                                width: trayChipRow.implicitWidth + 16
                                radius: 14
                                color: shown ? Theme.primaryContainer : Theme.surfaceContainerHigh
                                opacity: shown ? 1.0 : 0.65
                                Behavior on color { ColorAnimation { duration: Motion.fast } }

                                Row {
                                    id: trayChipRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Image {
                                        width: 14; height: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: modelData.icon || ""
                                        smooth: true
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.title || modelData.id || "App"
                                        color: shown ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        font.weight: shown ? Font.DemiBold : Font.Normal
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ShellState.toggleHideTray(tid)
                                }
                            }
                        }
                    }
                }

                // Customize bar & Control Center button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    radius: 16
                    color: custBtnM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Text { text: "󰕮"; color: Theme.primary; font.family: Theme.fontMono; font.pixelSize: 16 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: "Customize bar & controls"
                                color: Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            Text {
                                text: ShellState.qsTiles.length + " tiles · " + ShellState.topBarItems.length + " bar items"
                                color: Theme.fgSurfaceVariant
                                font.family: Theme.fontSans
                                font.pixelSize: 10
                            }
                        }
                        Text { text: "󰅂"; color: Theme.fgSurfaceVariant; font.family: Theme.fontMono; font.pixelSize: 16 }
                    }

                    MouseArea {
                        id: custBtnM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: qsWin.openSubPage("customize")
                    }
                }

                // Open raw state.json shortcut
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: 18
                    color: rawCfgM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰈔  Open settings.json"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: rawCfgM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ShellState.closeOverlay();
                            Quickshell.execDetached([
                                "sh", "-c",
                                "zed ~/.config/expressive-shell/settings.json || xdg-open ~/.config/expressive-shell/settings.json"
                            ]);
                        }
                    }
                }
            }

            // --- APP TEMPLATES TOGGLE PANEL (Noctalia-compatible matugen templates) ---
            ColumnLayout {
                id: templatesPage
                visible: qsWin.activePage === "templates"
                Layout.fillWidth: true
                spacing: 10

                property string searchQuery: ""
                property string activeFilter: "all" // "all" | "enabled" | category name

                readonly property var filterTabs: {
                    const cats = new Set();
                    const all = ShellState.availableTemplates || [];
                    for (let i = 0; i < all.length; i++) {
                        const c = String(all[i].category || "").toLowerCase();
                        if (c && c !== "community-templates" && c !== "noctalia-builtin") cats.add(c);
                    }
                    const tabs = [
                        { id: "all", label: "All" },
                        { id: "enabled", label: "Enabled (" + ShellState.enabledTemplates.length + ")" }
                    ];
                    const sorted = Array.from(cats).sort();
                    for (let i = 0; i < sorted.length; i++) {
                        const c = sorted[i];
                        tabs.push({ id: c, label: c.charAt(0).toUpperCase() + c.slice(1) });
                    }
                    return tabs;
                }

                readonly property var filteredTemplates: {
                    const q = searchQuery.trim().toLowerCase();
                    const f = activeFilter;
                    const all = ShellState.availableTemplates || [];
                    return all.filter(t => {
                        if (f === "enabled" && ShellState.enabledTemplates.indexOf(t.id) === -1) return false;
                        if (f !== "all" && f !== "enabled" && String(t.category || "").toLowerCase() !== f) return false;
                        if (q.length === 0) return true;
                        return t.name.toLowerCase().indexOf(q) !== -1
                            || t.id.toLowerCase().indexOf(q) !== -1
                            || t.category.toLowerCase().indexOf(q) !== -1;
                    });
                }

                // Search bar with clear button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: 18
                    color: Theme.surfaceContainerHigh
                    border.width: tplSearchInput.activeFocus ? 1.5 : 1
                    border.color: tplSearchInput.activeFocus ? Theme.primary : Theme.glassBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8

                        Text { text: "󰍉"; color: Theme.fgSurfaceVariant; font.family: Theme.fontMono; font.pixelSize: 14 }

                        TextInput {
                            id: tplSearchInput
                            Layout.fillWidth: true
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            clip: true
                            onTextChanged: templatesPage.searchQuery = text

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: tplSearchInput.text.length === 0
                                text: "Search " + ShellState.availableTemplates.length + " templates..."
                                color: Theme.fgSurfaceVariant
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                            }
                        }

                        Rectangle {
                            visible: tplSearchInput.text.length > 0
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            radius: 10
                            color: clrTplM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                            Text { anchors.centerIn: parent; text: "󰅖"; color: Theme.fgSurfaceVariant; font.family: Theme.fontMono; font.pixelSize: 11 }
                            MouseArea {
                                id: clrTplM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: tplSearchInput.text = ""
                            }
                        }
                    }
                }

                // Horizontal scrollable filter chips (All | Enabled | Categories)
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    contentWidth: chipRow.implicitWidth
                    contentHeight: height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: chipRow
                        spacing: 6

                        Repeater {
                            model: templatesPage.filterTabs

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected: templatesPage.activeFilter === modelData.id
                                height: 28
                                width: chipTxt.implicitWidth + 18
                                radius: 14
                                color: selected
                                    ? Theme.primary
                                    : (chipM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                                Behavior on color { ColorAnimation { duration: Motion.fast } }

                                Text {
                                    id: chipTxt
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: selected ? Theme.fgPrimary : Theme.fgSurface
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    font.weight: selected ? Font.DemiBold : Font.Medium
                                }

                                MouseArea {
                                    id: chipM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        templatesPage.activeFilter = modelData.id;
                                        tplFlick.contentY = 0;
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: templatesPage.filteredTemplates.length === 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    radius: Theme.radiusLarge
                    color: Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: templatesPage.activeFilter === "enabled" ? "No templates enabled yet" : "No matching templates"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                    }
                }

                // Incremental ListModel + ListView with launcher-style add/remove/move/displaced animations
                ListModel {
                    id: tplModel
                }

                function syncTplModel() {
                    const list = filteredTemplates || [];
                    const nextIds = new Set(list.map(t => t.id));

                    for (let i = tplModel.count - 1; i >= 0; i--) {
                        if (!nextIds.has(tplModel.get(i).tplId)) {
                            tplModel.remove(i);
                        }
                    }

                    for (let target = 0; target < list.length; target++) {
                        const t = list[target];
                        let cur = -1;
                        for (let j = target; j < tplModel.count; j++) {
                            if (tplModel.get(j).tplId === t.id) {
                                cur = j;
                                break;
                            }
                        }
                        if (cur === -1) {
                            tplModel.insert(target, {
                                tplId: t.id,
                                name: t.name,
                                category: t.category,
                                docUrl: t.docUrl || ""
                            });
                        } else if (cur !== target) {
                            tplModel.move(cur, target, 1);
                        }
                    }
                }

                onFilteredTemplatesChanged: syncTplModel()
                Component.onCompleted: syncTplModel()

                // Fixed-height scrollable M3E template list (steady viewport prevents pop-in while filtering)
                ClippingRectangle {
                    visible: tplModel.count > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 380
                    radius: 18
                    color: "transparent"

                    ListView {
                        id: tplFlick
                        anchors.fill: parent
                        model: tplModel
                        spacing: 3
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
                                SpringAnimation { property: "scale"; from: 0.92; to: 1.0; spring: Motion.popSpring; damping: Motion.popDamping }
                            }
                        }
                        remove: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; to: 0.0; duration: 120; easing.type: Easing.InQuad }
                                NumberAnimation { property: "scale"; to: 0.92; duration: 120; easing.type: Easing.InQuad }
                            }
                        }
                        move: Transition {
                            NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic }
                        }
                        displaced: Transition {
                            NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic }
                        }

                        delegate: Rectangle {
                            id: tplRow
                            required property string tplId
                            required property string name
                            required property string category
                            required property string docUrl
                            required property int index

                            readonly property bool isFirst: index === 0
                            readonly property bool isLast: index === tplModel.count - 1
                            readonly property bool tplEnabled: ShellState.enabledTemplates.indexOf(tplId) !== -1

                            width: tplFlick.width
                            height: 48
                            topLeftRadius: isFirst ? 18 : 6
                            topRightRadius: isFirst ? 18 : 6
                            bottomLeftRadius: isLast ? 18 : 6
                            bottomRightRadius: isLast ? 18 : 6
                            color: tplRowM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            MouseArea {
                                id: tplRowM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.toggleTemplate(tplRow.tplId)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 12
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 0
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: tplRow.name
                                        color: Theme.fgSurface
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: tplRow.category
                                        color: Theme.fgSurfaceVariant
                                        font.family: Theme.fontSans
                                        font.pixelSize: 10
                                    }
                                }

                                // Noctalia docs external link button
                                Rectangle {
                                    visible: tplRow.docUrl.length > 0
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    radius: 13
                                    color: docBtnM.containsMouse ? Theme.primaryContainer : "transparent"
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰏌"
                                        color: docBtnM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurfaceVariant
                                        font.family: Theme.fontMono
                                        font.pixelSize: 14
                                    }

                                    MouseArea {
                                        id: docBtnM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["xdg-open", tplRow.docUrl])
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 44
                                    Layout.preferredHeight: 24
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    radius: 12
                                    color: tplRow.tplEnabled ? Theme.primary : Theme.surfaceContainerHighest
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: tplRow.tplEnabled ? (parent.width - width - 3) : 3
                                        width: 18
                                        height: 18
                                        radius: 9
                                        color: tplRow.tplEnabled ? Theme.fgPrimary : Theme.fgSurfaceVariant
                                        Behavior on x { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom actions: Apply now + Open templates folder
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 18
                        color: Theme.primary
                        scale: applyTplM.pressed ? 0.96 : 1.0
                        Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰏘  Apply now"
                            color: Theme.fgPrimary
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: applyTplM
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.applyTemplatesNow()
                        }
                    }

                    Rectangle {
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: openDirTxt.implicitWidth + 24
                        radius: 18
                        color: openDirM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Text {
                            id: openDirTxt
                            anchors.centerIn: parent
                            text: "󰉋  Folder"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: openDirM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                ShellState.closeOverlay();
                                Quickshell.execDetached(["xdg-open", ShellState.configDir + "/templates"]);
                            }
                        }
                    }
                }
            }

            // --- WALLPAPER SETTINGS SUB-PANEL ---
            ColumnLayout {
                visible: qsWin.activePage === "wallpaper_settings"
                Layout.fillWidth: true
                spacing: 12

                // Wallpapers folder path + folder picker
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        text: "Wallpapers folder"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            radius: 19
                            color: Theme.surfaceContainerHigh
                            border.width: wpDirInput.activeFocus ? 1.5 : 1
                            border.color: wpDirInput.activeFocus ? Theme.primary : Theme.glassBorder

                            TextInput {
                                id: wpDirInput
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                clip: true
                                text: ShellState.wallpapersDir
                                onEditingFinished: {
                                    const v = text.trim();
                                    ShellState.wallpapersDir = v.length > 0 ? v : "~/Pictures/Wallpapers";
                                }
                                Keys.onReturnPressed: {
                                    focus = false;
                                    editingFinished();
                                }
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 18
                            color: pickWpM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            scale: pickWpM.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Text { anchors.centerIn: parent; text: "󰉋"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                            MouseArea {
                                id: pickWpM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.pickWallpapersFolder()
                            }
                        }
                    }
                }

                // Engine & Auto-rotate toggles
                Column {
                    Layout.fillWidth: true
                    spacing: 3

                    Rectangle {
                        width: parent.width
                        height: 46
                        topLeftRadius: 18; topRightRadius: 18
                        bottomLeftRadius: 6; bottomRightRadius: 6
                        color: Theme.surfaceContainerHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            Text {
                                Layout.fillWidth: true
                                text: "Animated wallpaper (awww)"
                                color: Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            Rectangle {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 24
                                radius: 12
                                color: Wallpaper.useAwww ? Theme.primary : Theme.surfaceContainerHighest
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Wallpaper.useAwww ? (parent.width - width - 3) : 3
                                    width: 18; height: 18; radius: 9
                                    color: Wallpaper.useAwww ? Theme.fgPrimary : Theme.fgSurfaceVariant
                                    Behavior on x { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Wallpaper.toggleAwww()
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 54
                        topLeftRadius: 6; topRightRadius: 6
                        bottomLeftRadius: 18; bottomRightRadius: 18
                        color: Theme.surfaceContainerHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: "Automatic Rotation"
                                    color: Theme.fgSurface
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Cycle wallpapers automatically on a timer"
                                    color: Theme.fgSurfaceVariant
                                    font.family: Theme.fontSans
                                    font.pixelSize: 10
                                }
                            }
                            Rectangle {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 24
                                radius: 12
                                color: Wallpaper.autoRotate ? Theme.primary : Theme.surfaceContainerHighest
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Wallpaper.autoRotate ? (parent.width - width - 3) : 3
                                    width: 18; height: 18; radius: 9
                                    color: Wallpaper.autoRotate ? Theme.fgPrimary : Theme.fgSurfaceVariant
                                    Behavior on x { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Wallpaper.autoRotate = !Wallpaper.autoRotate
                        }
                    }
                }

                // Order (Random | Alphabetical)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: "Order"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: "Pick wallpapers randomly or alphabetically"
                            color: Theme.fgSurfaceVariant
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: [
                                { id: "random", label: "Random" },
                                { id: "alphabetical", label: "Alphabetical" }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected: ShellState.rotateOrder === modelData.id
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                radius: selected ? 17 : 10
                                color: selected ? Theme.primary : Theme.surfaceContainerHigh
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Behavior on radius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: selected ? Theme.fgPrimary : Theme.fgSurface
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: selected ? Font.DemiBold : Font.Medium
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ShellState.rotateOrder = modelData.id
                                }
                            }
                        }
                    }
                }

                // Rotation Interval (presets + expandable Custom 10s stepper row)
                ColumnLayout {
                    id: rotIntSecCol
                    Layout.fillWidth: true
                    spacing: 6

                    property bool customOpen: [60, 300, 900, 1800, 3600].indexOf(ShellState.rotateIntervalSec) === -1

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: "Rotation Interval"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: "Time between wallpaper changes"
                            color: Theme.fgSurfaceVariant
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: [
                                { sec: 60, label: "1m" },
                                { sec: 300, label: "5m" },
                                { sec: 900, label: "15m" },
                                { sec: 1800, label: "30m" },
                                { sec: 3600, label: "1h" },
                                { sec: -1, label: "Custom" }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool isCustomBtn: modelData.sec === -1
                                readonly property bool selected: isCustomBtn
                                    ? rotIntSecCol.customOpen
                                    : (!rotIntSecCol.customOpen && ShellState.rotateIntervalSec === modelData.sec)

                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                radius: selected ? 17 : 10
                                color: selected ? Theme.primary : Theme.surfaceContainerHigh
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Behavior on radius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: selected ? Theme.fgPrimary : Theme.fgSurface
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    font.weight: selected ? Font.DemiBold : Font.Medium
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (isCustomBtn) {
                                            rotIntSecCol.customOpen = true;
                                        } else {
                                            rotIntSecCol.customOpen = false;
                                            ShellState.rotateIntervalSec = modelData.sec;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Smoothly expanding Custom interval row (±10s step or direct seconds input)
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: rotIntSecCol.customOpen ? 38 : 0
                        clip: true
                        opacity: rotIntSecCol.customOpen ? 1.0 : 0.0
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 36
                            radius: 18
                            color: Theme.surfaceContainerHigh
                            border.width: secInput.activeFocus ? 1.5 : 1
                            border.color: secInput.activeFocus ? Theme.primary : Theme.glassBorder

                            RowLayout {
                                anchors.fill: parent
                                spacing: 0

                                Rectangle {
                                    Layout.preferredWidth: 42
                                    Layout.fillHeight: true
                                    radius: 18
                                    color: decSecM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                                    Text { anchors.centerIn: parent; text: "−10s"; color: Theme.fgSurface; font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold }
                                    MouseArea {
                                        id: decSecM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ShellState.rotateIntervalSec = Math.max(10, ShellState.rotateIntervalSec - 10)
                                    }
                                }

                                TextInput {
                                    id: secInput
                                    Layout.fillWidth: true
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.fgSurface
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    text: ShellState.rotateIntervalSec + "s"
                                    onActiveFocusChanged: {
                                        if (activeFocus) text = String(ShellState.rotateIntervalSec);
                                        else {
                                            const n = parseInt(text.replace(/[^0-9]/g, ""), 10);
                                            if (!isNaN(n) && n >= 10) ShellState.rotateIntervalSec = n;
                                            text = ShellState.rotateIntervalSec + "s";
                                        }
                                    }
                                    Keys.onReturnPressed: focus = false
                                }

                                Rectangle {
                                    Layout.preferredWidth: 42
                                    Layout.fillHeight: true
                                    radius: 18
                                    color: incSecM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                                    Text { anchors.centerIn: parent; text: "+10s"; color: Theme.fgSurface; font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold }
                                    MouseArea {
                                        id: incSecM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ShellState.rotateIntervalSec = ShellState.rotateIntervalSec + 10
                                    }
                                }
                            }
                        }
                    }
                }

                // Matugen Color Scheme Style
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: "Color Scheme"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: "Matugen palette generation style"
                            color: Theme.fgSurfaceVariant
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { id: "scheme-tonal-spot", label: "Tonal Spot" },
                                { id: "scheme-expressive", label: "Expressive" },
                                { id: "scheme-vibrant", label: "Vibrant" },
                                { id: "scheme-fidelity", label: "Fidelity" },
                                { id: "scheme-content", label: "Content" },
                                { id: "scheme-fruit-salad", label: "Fruit Salad" },
                                { id: "scheme-rainbow", label: "Rainbow" },
                                { id: "scheme-neutral", label: "Neutral" },
                                { id: "scheme-monochrome", label: "Monochrome" }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected: ShellState.matugenScheme === modelData.id
                                height: 28
                                width: schTxt.implicitWidth + 18
                                radius: 14
                                color: selected
                                    ? Theme.primary
                                    : (schM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                                Behavior on color { ColorAnimation { duration: Motion.fast } }

                                Text {
                                    id: schTxt
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: selected ? Theme.fgPrimary : Theme.fgSurface
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    font.weight: selected ? Font.DemiBold : Font.Medium
                                }

                                MouseArea {
                                    id: schM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ShellState.matugenScheme = modelData.id
                                }
                            }
                        }
                    }
                }

                // Bottom actions: Next wallpaper + Open picker
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 18
                        color: Theme.primary
                        scale: nextWpM.pressed ? 0.96 : 1.0
                        Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰒝  Next wallpaper"
                            color: Theme.fgPrimary
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: nextWpM
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Wallpaper.nextWallpaper()
                        }
                    }

                    Rectangle {
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: browseWpTxt.implicitWidth + 24
                        radius: 18
                        color: browseWpM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Text {
                            id: browseWpTxt
                            anchors.centerIn: parent
                            text: "󰸉  Browse"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: browseWpM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.toggleOverlay("wallpapers")
                        }
                    }
                }
            }

            // --- CUSTOMIZE CONTROL CENTER & TOP BAR PANEL ---
            Flickable {
                id: customizePage
                visible: qsWin.activePage === "customize"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(460, custCol.implicitHeight)
                contentHeight: custCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: custCol
                    width: parent.width
                    spacing: 10

                    readonly property var qsMeta: ({
                        "wifi": { label: "Wi-Fi", icon: "󰤨" },
                        "bluetooth": { label: "Bluetooth", icon: "󰂯" },
                        "mic": { label: "Microphone", icon: "󰍬" },
                        "widgets": { label: "Desktop widgets", icon: "󰕰" },
                        "theme": { label: "Dark / Light theme", icon: "󰔎" },
                        "dock": { label: "Taskbar mode", icon: "󰘔" },
                        "dnd": { label: "Do Not Disturb", icon: "󰂚" },
                        "ppd": { label: "Power profile", icon: "󰾅" },
                        "screenshot": { label: "Screen capture", icon: "󰹑" }
                    })

                    readonly property var barMeta: ({
                        "media": { label: "Live media pill", icon: "󰎆" },
                        "tray": { label: "Background tray", icon: "󰀻" },
                        "keyboard": { label: "Keyboard layout", icon: "󰌌" },
                        "notifications": { label: "Notification bell", icon: "󰂚" },
                        "status": { label: "Status cluster", icon: "󰕾" }
                    })

                    // Build ordered list: enabled items first (in their current order), then disabled items
                    readonly property var orderedQsIds: {
                        const res = ShellState.qsTiles.slice();
                        for (const id of ShellState.allQsTileIds) {
                            if (res.indexOf(id) === -1) res.push(id);
                        }
                        return res;
                    }

                    readonly property var orderedBarIds: {
                        const res = ShellState.topBarItems.slice();
                        for (const id of ShellState.allTopBarItemIds) {
                            if (res.indexOf(id) === -1) res.push(id);
                        }
                        return res;
                    }

                    // Section 1: Control Center buttons
                    Text {
                        text: "CONTROL CENTER BUTTONS"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0.7
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Repeater {
                            model: custCol.orderedQsIds

                            delegate: Rectangle {
                                id: qRow
                                required property string modelData
                                required property int index
                                readonly property string tid: modelData
                                readonly property bool isOn: ShellState.isQsTileEnabled(tid)
                                readonly property int enabledIdx: ShellState.qsTiles.indexOf(tid)
                                readonly property var meta: custCol.qsMeta[tid] || { label: tid, icon: "󰒓" }
                                readonly property bool isFirst: index === 0
                                readonly property bool isLast: index === custCol.orderedQsIds.length - 1

                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                topLeftRadius: isFirst ? 16 : 6
                                topRightRadius: isFirst ? 16 : 6
                                bottomLeftRadius: isLast ? 16 : 6
                                bottomRightRadius: isLast ? 16 : 6
                                color: Theme.surfaceContainerHigh

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Text {
                                        text: qRow.meta.icon
                                        color: qRow.isOn ? Theme.primary : Theme.fgSurfaceVariant
                                        font.family: Theme.fontMono
                                        font.pixelSize: 15
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: qRow.meta.label
                                        color: qRow.isOn ? Theme.fgSurface : Theme.fgSurfaceVariant
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }

                                    // Reorder up
                                    Rectangle {
                                        visible: qRow.isOn
                                        Layout.preferredWidth: 24
                                        Layout.preferredHeight: 24
                                        radius: 12
                                        color: qUpM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                                        opacity: qRow.enabledIdx > 0 ? 1.0 : 0.3
                                        Text { anchors.centerIn: parent; text: "󰅃"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 14 }
                                        MouseArea {
                                            id: qUpM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: qRow.enabledIdx > 0
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: ShellState.moveQsTile(qRow.tid, -1)
                                        }
                                    }

                                    // Reorder down
                                    Rectangle {
                                        visible: qRow.isOn
                                        Layout.preferredWidth: 24
                                        Layout.preferredHeight: 24
                                        radius: 12
                                        color: qDnM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                                        opacity: qRow.enabledIdx < ShellState.qsTiles.length - 1 ? 1.0 : 0.3
                                        Text { anchors.centerIn: parent; text: "󰅀"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 14 }
                                        MouseArea {
                                            id: qDnM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: qRow.enabledIdx < ShellState.qsTiles.length - 1
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: ShellState.moveQsTile(qRow.tid, 1)
                                        }
                                    }

                                    // Toggle switch
                                    Rectangle {
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 20
                                        radius: 10
                                        color: qRow.isOn ? Theme.primary : Theme.surfaceContainerHighest
                                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                                        Rectangle {
                                            width: 14
                                            height: 14
                                            radius: 7
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: qRow.isOn ? 19 : 3
                                            color: qRow.isOn ? Theme.fgPrimary : Theme.fgSurfaceVariant
                                            Behavior on x { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: ShellState.toggleQsTile(qRow.tid)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Section 2: Top Bar icons
                    Text {
                        Layout.topMargin: 6
                        text: "TOP BAR ICONS"
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0.7
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Repeater {
                            model: custCol.orderedBarIds

                            delegate: Rectangle {
                                id: bRow
                                required property string modelData
                                required property int index
                                readonly property string bid: modelData
                                readonly property bool isOn: ShellState.isTopBarItemEnabled(bid)
                                readonly property int enabledIdx: ShellState.topBarItems.indexOf(bid)
                                readonly property var meta: custCol.barMeta[bid] || { label: bid, icon: "󰒓" }
                                readonly property bool isFirst: index === 0
                                readonly property bool isLast: index === custCol.orderedBarIds.length - 1

                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                topLeftRadius: isFirst ? 16 : 6
                                topRightRadius: isFirst ? 16 : 6
                                bottomLeftRadius: isLast ? 16 : 6
                                bottomRightRadius: isLast ? 16 : 6
                                color: Theme.surfaceContainerHigh

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Text {
                                        text: bRow.meta.icon
                                        color: bRow.isOn ? Theme.primary : Theme.fgSurfaceVariant
                                        font.family: Theme.fontMono
                                        font.pixelSize: 15
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: bRow.meta.label
                                        color: bRow.isOn ? Theme.fgSurface : Theme.fgSurfaceVariant
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }

                                    // Reorder up (left on bar)
                                    Rectangle {
                                        visible: bRow.isOn
                                        Layout.preferredWidth: 24
                                        Layout.preferredHeight: 24
                                        radius: 12
                                        color: bUpM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                                        opacity: bRow.enabledIdx > 0 ? 1.0 : 0.3
                                        Text { anchors.centerIn: parent; text: "󰅃"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 14 }
                                        MouseArea {
                                            id: bUpM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: bRow.enabledIdx > 0
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: ShellState.moveTopBarItem(bRow.bid, -1)
                                        }
                                    }

                                    // Reorder down (right on bar)
                                    Rectangle {
                                        visible: bRow.isOn
                                        Layout.preferredWidth: 24
                                        Layout.preferredHeight: 24
                                        radius: 12
                                        color: bDnM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                                        opacity: bRow.enabledIdx < ShellState.topBarItems.length - 1 ? 1.0 : 0.3
                                        Text { anchors.centerIn: parent; text: "󰅀"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 14 }
                                        MouseArea {
                                            id: bDnM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: bRow.enabledIdx < ShellState.topBarItems.length - 1
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: ShellState.moveTopBarItem(bRow.bid, 1)
                                        }
                                    }

                                    // Toggle switch
                                    Rectangle {
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 20
                                        radius: 10
                                        color: bRow.isOn ? Theme.primary : Theme.surfaceContainerHighest
                                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                                        Rectangle {
                                            width: 14
                                            height: 14
                                            radius: 7
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: bRow.isOn ? 19 : 3
                                            color: bRow.isOn ? Theme.fgPrimary : Theme.fgSurfaceVariant
                                            Behavior on x { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: ShellState.toggleTopBarItem(bRow.bid)
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
