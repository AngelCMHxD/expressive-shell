import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../theme"
import "../services"

PanelWindow {
    id: mediaWin

    required property var modelData
    screen: modelData

    readonly property bool isOpen: ShellState.activeOverlay === "media"
    property bool windowVisible: false
    property bool morphStart: false
    property bool morphBehaviorsEnabled: false
    property int morphSlideDir: 1
    visible: windowVisible

    Timer {
        id: morphOutTimer
        interval: 45
        onTriggered: {
            if (!mediaWin.isOpen) {
                mediaWin.windowVisible = false;
                card.state = "closed";
            }
        }
    }

    Timer {
        id: openTrigger
        interval: 25
        onTriggered: {
            const wasMorph = mediaWin.morphStart;
            mediaWin.morphBehaviorsEnabled = true;
            mediaWin.morphStart = false;
            card.state = "open";
            if (wasMorph) mediaSlideAnim.restart();
            ShellState.reportOverlayGeometry("media", 396, 194, 72);
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
            const doMorph = ShellState.overlaysShareRegion(ShellState.previousOverlay, "media")
                && ShellState.morphFromW > 40 && ShellState.morphFromH > 40;
            morphBehaviorsEnabled = false;
            morphStart = doMorph;
            if (doMorph) {
                morphSlideDir = ShellState.overlaySlideDir(ShellState.previousOverlay, "media");
                mediaContentCol.opacity = 0.0;
            } else {
                mediaContentCol.opacity = 1.0;
                mediaContentSlide.x = 0;
            }
            card.state = doMorph ? "morph" : "closed";
            windowVisible = true;
            if (doMorph) morphBehaviorsEnabled = true;
            openTrigger.restart();
        } else {
            openTrigger.stop();
            if (ShellState.overlaysShareRegion("media", ShellState.activeOverlay)) {
                morphOutTimer.restart();
            } else {
                card.state = "closed";
            }
        }
    }

    // Auto-close if player vanishes while open
    Connections {
        target: Media
        function onHasPlayerChanged() {
            if (!Media.hasPlayer && mediaWin.isOpen) {
                ShellState.closeOverlay();
            }
        }
    }

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.closeOverlay()
    }

    // Expressive Shell / Android 17 Standalone Floating Media Player Card
    ClippingRectangle {
        id: card
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: mediaWin.morphStart ? ShellState.morphFromRight : 72
        width: mediaWin.morphStart ? ShellState.morphFromW : 396
        height: mediaWin.morphStart ? ShellState.morphFromH : 194
        Behavior on anchors.rightMargin { enabled: mediaWin.morphBehaviorsEnabled; SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 } }
        Behavior on width { enabled: mediaWin.morphBehaviorsEnabled; SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 } }
        Behavior on height { enabled: mediaWin.morphBehaviorsEnabled; SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping; epsilon: 0.4 } }
        radius: Theme.radiusExtraLarge
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.alpha("#FFFFFF", 0.16)
        contentUnderBorder: false

        focus: mediaWin.isOpen
        Keys.onEscapePressed: ShellState.closeOverlay()
        Keys.onSpacePressed: Media.togglePlay()

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
                        script: { if (!mediaWin.isOpen) mediaWin.windowVisible = false; }
                    }
                }
            }
        ]

        // Full-bleed album art backdrop (matches Expressive Shell screenshot)
        Image {
            anchors.fill: parent
            source: Media.artUrl
            fillMode: Image.PreserveAspectCrop
            visible: Media.artUrl.length > 0
            smooth: true
        }

        // Rich tonal gradient scrim for crisp legibility over any cover art
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Media.artUrl.length > 0 ? Qt.rgba(0.06, 0.05, 0.12, 0.42) : Theme.alpha(Theme.primaryContainer, 0.55) }
                GradientStop { position: 0.55; color: Media.artUrl.length > 0 ? Qt.rgba(0.05, 0.04, 0.10, 0.62) : Theme.alpha(Theme.surfaceContainerHigh, 0.85) }
                GradientStop { position: 1.0; color: Media.artUrl.length > 0 ? Qt.rgba(0.04, 0.03, 0.08, 0.82) : Theme.alpha(Theme.surfaceContainer, 0.96) }
            }
        }

        // Android 13–17 Play/Pause Sparkle Ripple Wave across the entire media card
        Canvas {
            id: rippleCanvas
            anchors.fill: parent
            visible: rippleAnim.running

            property real originX: width * 0.82
            property real originY: height * 0.55
            property real progress: 0.0
            property var sparkles: []

            function trigger(ox, oy) {
                originX = ox;
                originY = oy;
                const pts = [];
                for (let i = 0; i < 64; i++) {
                    pts.push({
                        angle: Math.random() * Math.PI * 2,
                        distFrac: 0.08 + Math.random() * 0.92,
                        size: 0.7 + Math.random() * 0.9,
                        phase: Math.random() * Math.PI * 2
                    });
                }
                sparkles = pts;
                rippleAnim.restart();
            }

            NumberAnimation {
                id: rippleAnim
                target: rippleCanvas
                property: "progress"
                from: 0.0
                to: 1.0
                duration: 1450
                easing.type: Easing.OutQuad
                onFinished: rippleCanvas.progress = 0.0
            }

            onProgressChanged: {
                if (visible) requestPaint();
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (progress <= 0 || progress >= 1) return;

                // Broad, slow, dreamy Android 17 radial wash sweeping across the full card
                const maxR = Math.hypot(width, height) * 1.22;
                const r = Math.max(24, maxR * progress);
                // Smooth fade-in then long gentle fade-out so the wash stays lush mid-travel
                const fadeIn = Math.min(1.0, progress / 0.14);
                const fadeOut = Math.pow(1.0 - progress, 1.15);
                const alpha = fadeIn * fadeOut;

                const c = Theme.primary;
                const lr = Math.min(1, c.r * 0.45 + 0.55);
                const lg = Math.min(1, c.g * 0.45 + 0.55);
                const lb = Math.min(1, c.b * 0.45 + 0.55);

                const grad = ctx.createRadialGradient(originX, originY, 0, originX, originY, r);
                grad.addColorStop(0.0, Qt.rgba(lr, lg, lb, 0.12 * alpha));
                grad.addColorStop(0.32, Qt.rgba(lr, lg, lb, 0.24 * alpha));
                grad.addColorStop(0.62, Qt.rgba(lr, lg, lb, 0.34 * alpha));
                grad.addColorStop(0.82, Qt.rgba(1, 1, 1, 0.22 * alpha));
                grad.addColorStop(1.0, "rgba(255, 255, 255, 0)");

                ctx.fillStyle = grad;
                ctx.beginPath();
                ctx.arc(originX, originY, r, 0, Math.PI * 2);
                ctx.fill();

                // Fine, subtle shimmer specks across the wide wave band
                const bandHalf = Math.max(55, maxR * 0.34);
                const waveCenter = r * 0.68;
                for (let i = 0; i < sparkles.length; i++) {
                    const s = sparkles[i];
                    const d = s.distFrac * maxR;
                    const delta = Math.abs(d - waveCenter);
                    if (delta > bandHalf) continue;
                    const env = (1.0 - delta / bandHalf) * alpha;
                    const twinkle = 0.5 + 0.5 * Math.sin(progress * 14.0 + s.phase);
                    const a = Math.min(0.45, env * twinkle * 0.48);
                    if (a <= 0.015) continue;

                    const px = originX + Math.cos(s.angle) * d;
                    const py = originY + Math.sin(s.angle) * d;
                    ctx.fillStyle = Qt.rgba(1, 1, 1, a);
                    ctx.beginPath();
                    ctx.arc(px, py, s.size, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
        }

        // Absorb clicks inside the card
        MouseArea { anchors.fill: parent }

        ParallelAnimation {
            id: mediaSlideAnim
            NumberAnimation { target: mediaContentSlide; property: "x"; from: mediaWin.morphSlideDir * 26; to: 0; duration: 210; easing.type: Easing.OutCubic }
            NumberAnimation { target: mediaContentCol; property: "opacity"; from: 0.0; to: 1.0; duration: 170; easing.type: Easing.OutQuad }
        }

        ColumnLayout {
            id: mediaContentCol
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.topMargin: 16
            anchors.bottomMargin: 14
            spacing: 0
            transform: Translate { id: mediaContentSlide; x: 0 }

            // Top row: Player app icon (left) + Output switcher pill (right)
            RowLayout {
                Layout.fillWidth: true

                Item {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24

                    Image {
                        id: appIconImg
                        anchors.fill: parent
                        visible: Media.playerIconSource.length > 0 && status === Image.Ready
                        source: Media.playerIconSource
                        sourceSize.width: 48
                        sourceSize.height: 48
                        smooth: true
                        mipmap: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !appIconImg.visible
                        text: "󰎆"
                        color: "#FFFFFF"
                        font.family: Theme.fontMono
                        font.pixelSize: 19
                    }
                }

                Item { Layout.fillWidth: true }

                // Output / audio mixer pill button (outlined like screenshot's cast pill)
                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 30
                    radius: 15
                    color: outM.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.24)
                    border.width: 1.2
                    border.color: Qt.rgba(1, 1, 1, 0.48)
                    scale: outM.pressed ? 0.92 : 1.0
                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰕾"
                        color: "#FFFFFF"
                        font.family: Theme.fontMono
                        font.pixelSize: 15
                    }

                    MouseArea {
                        id: outM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.openQuickSettingsPage("audio")
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // Middle row: Bold track title & artist + big M3E morphing Play/Pause squircle-pill
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Media.title
                        color: "#FFFFFF"
                        font.family: Theme.fontSans
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: Media.artist.length > 0
                        elide: Text.ElideRight
                        text: Media.artist
                        color: Qt.rgba(1, 1, 1, 0.84)
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }

                // Large Expressive Shell M3E Play/Pause pill-squircle button
                Rectangle {
                    id: playBtn
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 50
                    radius: Media.isPlaying ? 18 : 25
                    color: "#FFFFFF"

                    scale: playBtnM.pressed ? 0.90 : (playBtnM.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on radius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }

                    Text {
                        anchors.centerIn: parent
                        text: Media.isPlaying ? "󰏤" : "󰐊"
                        color: "#1B1630"
                        font.family: Theme.fontMono
                        font.pixelSize: 22
                    }

                    MouseArea {
                        id: playBtnM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const pt = playBtn.mapToItem(card, playBtn.width / 2, playBtn.height / 2);
                            rippleCanvas.trigger(pt.x, pt.y);
                            Media.togglePlay();
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 14 }

            // Bottom row: Prev + Android 17 Squiggly Seek Bar with vertical thumb + Next
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 15
                    color: prevBtnM.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                    Text { anchors.centerIn: parent; text: "󰒮"; color: "#FFFFFF"; font.family: Theme.fontMono; font.pixelSize: 18 }
                    MouseArea { id: prevBtnM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Media.previous() }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24

                    Canvas {
                        id: seekCanvas
                        anchors.fill: parent

                        property real phase: 0
                        property real amp: Media.isPlaying ? 2.4 : 0.0
                        property real progress: Media.progress

                        Behavior on amp { NumberAnimation { duration: 240; easing.type: Easing.InOutCubic } }
                        Behavior on progress {
                            enabled: !seekDrag.pressed
                            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                        }

                        onPhaseChanged: requestPaint()
                        onAmpChanged: requestPaint()
                        onProgressChanged: requestPaint()
                        onWidthChanged: requestPaint()

                        NumberAnimation on phase {
                            from: 0
                            to: Math.PI * 2
                            duration: 1400
                            loops: Animation.Infinite
                            running: Media.isPlaying && mediaWin.isOpen
                        }

                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            const cy = height / 2;
                            const pad = 4;
                            const usable = Math.max(1, width - pad * 2);
                            const splitX = pad + usable * progress;

                            // Remaining straight track
                            if (splitX + 6 < width - pad) {
                                ctx.beginPath();
                                ctx.moveTo(splitX + 6, cy);
                                ctx.lineTo(width - pad, cy);
                                ctx.strokeStyle = "rgba(255, 255, 255, 0.34)";
                                ctx.lineWidth = 3;
                                ctx.lineCap = "round";
                                ctx.stroke();
                            }

                            // Played wave
                            if (splitX > pad + 2) {
                                ctx.beginPath();
                                const freq = 0.28;
                                for (let x = pad; x <= splitX - 5; x += 1.5) {
                                    const y = cy + amp * Math.sin(x * freq - phase);
                                    if (x === pad) ctx.moveTo(x, y);
                                    else ctx.lineTo(x, y);
                                }
                                ctx.strokeStyle = "#FFFFFF";
                                ctx.lineWidth = 3;
                                ctx.lineCap = "round";
                                ctx.stroke();
                            }

                            // Vertical rounded white thumb bar (matches screenshot)
                            ctx.fillStyle = "#FFFFFF";
                            ctx.beginPath();
                            ctx.roundedRect(splitX - 2, cy - 8, 4, 16, 2, 2);
                            ctx.fill();
                        }
                    }

                    MouseArea {
                        id: seekDrag
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function seekAt(mx) {
                            const frac = Math.max(0, Math.min(1, (mx - 4) / Math.max(1, width - 8)));
                            Media.seekToFraction(frac);
                        }
                        onPressed: mouse => seekAt(mouse.x)
                        onPositionChanged: mouse => { if (pressed) seekAt(mouse.x); }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 15
                    color: nextBtnM.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                    Text { anchors.centerIn: parent; text: "󰒭"; color: "#FFFFFF"; font.family: Theme.fontMono; font.pixelSize: 18 }
                    MouseArea { id: nextBtnM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Media.next() }
                }
            }
        }
    }
}
