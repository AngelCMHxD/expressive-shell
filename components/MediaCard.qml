import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../theme"
import "../services"

// Reusable Android M3 Expressive Media Player Card (album-art backdrop + interactive squiggly progress bar)
ClippingRectangle {
    id: mediaCard

    property bool animateWave: true
    property int cardRadius: Theme.radiusLarge

    visible: Media.hasPlayer && Media.title.length > 0
    implicitHeight: 126
    radius: cardRadius
    color: Theme.alpha(Theme.surfaceContainerHigh, 0.90)
    border.width: 1
    border.color: Theme.glassBorder
    contentUnderBorder: false

    // Subtle tinted album art backdrop
    Image {
        anchors.fill: parent
        source: Media.artUrl
        fillMode: Image.PreserveAspectCrop
        visible: Media.artUrl.length > 0
        opacity: 0.24
        smooth: true
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.alpha(Theme.surfaceContainer, 0.52) }
            GradientStop { position: 1.0; color: Theme.alpha(Theme.surfaceContainer, 0.88) }
        }
    }

    // Android Play/Pause Sparkle Ripple Wave across the card
    Canvas {
        id: cardRipple
        anchors.fill: parent
        visible: cardRippleAnim.running

        property real originX: width * 0.85
        property real originY: height * 0.35
        property real progress: 0.0
        property var sparkles: []

        function trigger(ox, oy) {
            originX = ox;
            originY = oy;
            const pts = [];
            for (let i = 0; i < 48; i++) {
                pts.push({
                    angle: Math.random() * Math.PI * 2,
                    distFrac: 0.08 + Math.random() * 0.92,
                    size: 0.7 + Math.random() * 0.9,
                    phase: Math.random() * Math.PI * 2
                });
            }
            sparkles = pts;
            cardRippleAnim.restart();
        }

        NumberAnimation {
            id: cardRippleAnim
            target: cardRipple
            property: "progress"
            from: 0.0
            to: 1.0
            duration: 1450
            easing.type: Easing.OutQuad
            onFinished: cardRipple.progress = 0.0
        }

        onProgressChanged: {
            if (visible) requestPaint();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (progress <= 0 || progress >= 1) return;

            const maxR = Math.hypot(width, height) * 1.22;
            const r = Math.max(24, maxR * progress);
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // Top row: rounded album art, title/artist, morphing play/pause button
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ClippingRectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: 13
                color: Theme.primaryContainer

                Image {
                    anchors.fill: parent
                    source: Media.artUrl
                    fillMode: Image.PreserveAspectCrop
                    visible: Media.artUrl.length > 0
                    smooth: true
                }

                Text {
                    anchors.centerIn: parent
                    visible: Media.artUrl.length === 0
                    text: "󰎆"
                    color: Theme.fgPrimaryContainer
                    font.family: Theme.fontMono
                    font.pixelSize: 21
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Media.title
                    color: Theme.fgSurface
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    visible: Media.artist.length > 0
                    elide: Text.ElideRight
                    text: Media.artist
                    color: Theme.fgSurfaceVariant
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                }
            }

            // M3E morphing play/pause button (squircle while playing, circle while paused)
            Rectangle {
                id: cardPlayBtn
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: Media.isPlaying ? 13 : 21
                color: Theme.primary

                scale: playM.pressed ? 0.9 : (playM.containsMouse ? 1.06 : 1.0)
                Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                Behavior on radius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }

                Text {
                    anchors.centerIn: parent
                    text: Media.isPlaying ? "󰏤" : "󰐊"
                    color: Theme.fgPrimary
                    font.family: Theme.fontMono
                    font.pixelSize: 19
                }

                MouseArea {
                    id: playM
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const pt = cardPlayBtn.mapToItem(mediaCard, cardPlayBtn.width / 2, cardPlayBtn.height / 2);
                        cardRipple.trigger(pt.x, pt.y);
                        Media.togglePlay();
                    }
                }
            }
        }

        // Bottom row: Prev + Interactive Android M3E Squiggly Seek Bar + Next
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: prevM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                Text { anchors.centerIn: parent; text: "󰒮"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                MouseArea { id: prevM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Media.previous() }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 22

                Canvas {
                    id: squiggleBar
                    anchors.fill: parent

                    property real phase: 0
                    property real amp: Media.isPlaying ? 2.5 : 0.0
                    property real progress: Media.progress
                    property color activeColor: Theme.primary
                    property color trackColor: Theme.alpha(Theme.fgSurfaceVariant, 0.30)

                    Behavior on amp { NumberAnimation { duration: 240; easing.type: Easing.InOutCubic } }
                    Behavior on progress {
                        enabled: !seekMouse.pressed
                        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                    }

                    onPhaseChanged: requestPaint()
                    onAmpChanged: requestPaint()
                    onProgressChanged: requestPaint()
                    onActiveColorChanged: requestPaint()
                    onWidthChanged: requestPaint()

                    NumberAnimation on phase {
                        from: 0
                        to: Math.PI * 2
                        duration: 1400
                        loops: Animation.Infinite
                        running: Media.isPlaying && mediaCard.animateWave && mediaCard.visible
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
                            ctx.strokeStyle = trackColor;
                            ctx.lineWidth = 3;
                            ctx.lineCap = "round";
                            ctx.stroke();
                        }

                        // Played squiggly wave
                        if (splitX > pad + 2) {
                            ctx.beginPath();
                            const freq = 0.28;
                            for (let x = pad; x <= splitX - 4; x += 1.5) {
                                const y = cy + amp * Math.sin(x * freq - phase);
                                if (x === pad) ctx.moveTo(x, y);
                                else ctx.lineTo(x, y);
                            }
                            ctx.strokeStyle = activeColor;
                            ctx.lineWidth = 3;
                            ctx.lineCap = "round";
                            ctx.stroke();
                        }

                        // Vertical rounded thumb pill
                        ctx.fillStyle = activeColor;
                        ctx.beginPath();
                        ctx.roundedRect(splitX - 2, cy - 7, 4, 14, 2, 2);
                        ctx.fill();
                    }
                }

                MouseArea {
                    id: seekMouse
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
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: nextM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                Text { anchors.centerIn: parent; text: "󰒭"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                MouseArea { id: nextM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Media.next() }
            }
        }
    }
}
