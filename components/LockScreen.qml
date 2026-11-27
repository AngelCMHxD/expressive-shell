import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pam
import "../theme"
import "../services"

// Native Wayland M3 Expressive Lockscreen (ext-session-lock-v1 + Linux PAM + logind sleep lock)
Scope {
    id: lockScope

    // Listen to systemd-logind PrepareForSleep & Lock so suspend / `loginctl lock-session` locks natively
    Process {
        id: sleepLockProc
        command: ["python3", Quickshell.shellPath("scripts/sleep-lock-watcher.py")]
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (line.trim() === "LOCK") {
                    ShellState.lock();
                }
            }
        }
        onExited: sleepLockReconnect.restart()
    }

    Timer {
        id: sleepLockReconnect
        interval: 2000
        onTriggered: sleepLockProc.running = true
    }

    property string passwordBuffer: ""
    property string statusMessage: ""
    property bool isError: false
    property bool authenticating: false
    property bool unlocking: false
    property int shakeTick: 0

    // Pre-lock & post-unlock overlay curtain so apps smoothly dissolve into/out of the lockscreen
    property bool sessionLocked: false
    property bool curtainVisible: false
    property real curtainOpacity: 0.0

    readonly property string username: Quickshell.env("USER") || "user"

    Connections {
        target: ShellState
        function onLockedChanged() {
            if (ShellState.locked && !lockScope.sessionLocked) {
                // Phase 1: fade frosted wallpaper curtain directly over live apps
                curtainFadeOut.stop();
                curtainHideAfterLock.stop();
                lockScope.curtainOpacity = 0.0;
                lockScope.curtainVisible = true;
                curtainFadeIn.restart();
            } else if (!ShellState.locked && lockScope.sessionLocked) {
                lockScope.sessionLocked = false;
            }
        }
    }

    NumberAnimation {
        id: curtainFadeIn
        target: lockScope
        property: "curtainOpacity"
        from: 0.0
        to: 1.0
        duration: 240
        easing.type: Easing.OutCubic
        onFinished: {
            if (ShellState.locked) {
                // Phase 2: engage native WlSessionLock seamlessly behind the opaque curtain
                lockScope.sessionLocked = true;
                curtainHideAfterLock.restart();
            } else {
                lockScope.curtainVisible = false;
            }
        }
    }

    Timer {
        id: curtainHideAfterLock
        interval: 90
        onTriggered: {
            if (lockScope.sessionLocked) {
                lockScope.curtainVisible = false;
            }
        }
    }

    NumberAnimation {
        id: curtainFadeOut
        target: lockScope
        property: "curtainOpacity"
        from: 1.0
        to: 0.0
        duration: 220
        easing.type: Easing.OutCubic
        onFinished: lockScope.curtainVisible = false
    }

    // Parallel fingerprint authentication (`fprintd-verify`) alongside password entry
    property bool fprintActive: false
    property string fprintHint: ""

    Process {
        id: fprintProc
        command: ["fprintd-verify"]
        running: false

        stdout: SplitParser {
            onRead: line => {
                const s = line.trim().toLowerCase();
                if (s.indexOf("verify-match") !== -1) {
                    lockScope.fprintHint = "";
                    lockScope.statusMessage = "";
                    lockScope.isError = false;
                    lockScope.fprintActive = false;
                    fprintProc.running = false;
                    lockScope.unlocking = true;
                    unlockFinishTimer.restart();
                } else if (s.indexOf("verify-no-match") !== -1) {
                    lockScope.fprintHint = "Fingerprint not recognized";
                } else if (s.indexOf("verify-retry-scan") !== -1) {
                    lockScope.fprintHint = "Try scanning again";
                }
            }
        }

        onRunningChanged: lockScope.fprintActive = running

        onExited: code => {
            lockScope.fprintActive = false;
            // If still locked and not unlocking, re-arm sensor briefly after a failed scan
            if (SystemStatus.hasFingerprint && lockScope.sessionLocked && !lockScope.unlocking && code !== 0) {
                fprintRetryTimer.restart();
            }
        }
    }

    Timer {
        id: fprintRetryTimer
        interval: 900
        onTriggered: {
            if (SystemStatus.hasFingerprint && lockScope.sessionLocked && !lockScope.unlocking && !fprintProc.running) {
                lockScope.fprintHint = "";
                fprintProc.running = true;
            }
        }
    }

    onSessionLockedChanged: {
        if (sessionLocked && SystemStatus.hasFingerprint) {
            fprintHint = "";
            fprintRetryTimer.stop();
            if (!fprintProc.running) fprintProc.running = true;
        } else {
            fprintRetryTimer.stop();
            if (fprintProc.running) fprintProc.running = false;
            fprintHint = "";
        }
    }

    Timer {
        id: unlockFinishTimer
        interval: 170
        onTriggered: {
            // Phase 3a: map opaque curtain FIRST while WlSessionLock is still active
            lockScope.curtainOpacity = 1.0;
            lockScope.curtainVisible = true;
            unlockReleaseTimer.restart();
        }
    }

    // Give Wayland 55ms to commit the opaque curtain surface before releasing WlSessionLock
    Timer {
        id: unlockReleaseTimer
        interval: 55
        onTriggered: {
            lockScope.unlocking = false;
            lockScope.sessionLocked = false;
            ShellState.locked = false;
            curtainFadeOut.restart();
        }
    }

    // Fullscreen Overlay Curtain per monitor (only mapped during the 240ms lock / 220ms unlock handoff)
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            visible: lockScope.curtainVisible

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            exclusiveZone: -1
            color: "transparent"
            WlrLayershell.namespace: "expressive-session"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                anchors.fill: parent
                opacity: lockScope.curtainOpacity

                Image {
                    anchors.fill: parent
                    source: Wallpaper.currentWallpaper ? ("file://" + Wallpaper.currentWallpaper) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: false
                    smooth: implicitWidth >= 1280 && !Wallpaper.currentWallpaper.toLowerCase().endsWith(".gif")
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.alpha(Theme.surface, 0.52) }
                        GradientStop { position: 0.5; color: Theme.alpha(Theme.surface, 0.62) }
                        GradientStop { position: 1.0; color: Theme.alpha(Theme.surface, 0.78) }
                    }
                }
            }
        }
    }

    function submitPassword(pw) {
        if (authenticating || unlocking || !pw) return;
        passwordBuffer = pw;
        authenticating = true;
        isError = false;
        statusMessage = "Unlocking...";
        if (!pam.start()) {
            authenticating = false;
            passwordBuffer = "";
            isError = true;
            statusMessage = "PAM failed to start";
            shakeTick++;
        }
    }

    PamContext {
        id: pam
        config: "system-auth"
        user: lockScope.username

        onResponseRequiredChanged: {
            if (responseRequired && lockScope.authenticating) {
                const pw = lockScope.passwordBuffer;
                lockScope.passwordBuffer = "";
                respond(pw);
            }
        }

        onCompleted: result => {
            lockScope.authenticating = false;
            lockScope.passwordBuffer = "";
            if (result === PamResult.Success) {
                lockScope.statusMessage = "";
                lockScope.isError = false;
                lockScope.unlocking = true;
                unlockFinishTimer.restart();
            } else {
                lockScope.isError = true;
                lockScope.statusMessage = result === PamResult.MaxTries
                    ? "Too many attempts"
                    : "Incorrect password";
                lockScope.shakeTick++;
            }
        }

        onError: err => {
            lockScope.authenticating = false;
            lockScope.passwordBuffer = "";
            lockScope.isError = true;
            lockScope.statusMessage = "Auth error: " + PamError.toString(err);
            lockScope.shakeTick++;
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: lockScope.sessionLocked

        WlSessionLockSurface {
            id: lockSurface
            color: Theme.surface

            property bool entered: false
            readonly property bool activeView: entered && !lockScope.unlocking

            Timer {
                interval: 25
                running: true
                onTriggered: {
                    lockSurface.entered = true;
                    pwInput.forceActiveFocus();
                }
            }

            // Wallpaper renders synchronously at full opacity from frame 0 (matches the pre-lock curtain 1:1)
            Image {
                anchors.fill: parent
                source: Wallpaper.currentWallpaper ? ("file://" + Wallpaper.currentWallpaper) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                smooth: implicitWidth >= 1280 && !Wallpaper.currentWallpaper.toLowerCase().endsWith(".gif")
            }

            // Frosted atmospheric scrim at full opacity from frame 0 (matches the pre-lock curtain 1:1)
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.alpha(Theme.surface, 0.52) }
                    GradientStop { position: 0.5; color: Theme.alpha(Theme.surface, 0.62) }
                    GradientStop { position: 1.0; color: Theme.alpha(Theme.surface, 0.78) }
                }
            }

            // Lock UI animates cleanly over the frosted backdrop
            Item {
                id: rootFade
                anchors.fill: parent
                opacity: lockSurface.activeView ? 1.0 : 0.0
                scale: lockSurface.activeView ? 1.0 : 0.95
                transform: Translate {
                    y: lockSurface.activeView ? 0 : 22
                    Behavior on y { SpringAnimation { spring: 7.5; damping: 0.56; epsilon: 0.4 } }
                }
                Behavior on scale { SpringAnimation { spring: 7.5; damping: 0.56; epsilon: 0.002 } }
                Behavior on opacity {
                    NumberAnimation {
                        duration: lockScope.unlocking ? 160 : 280
                        easing.type: lockScope.unlocking ? Easing.InCubic : Easing.OutCubic
                    }
                }

                // Top-right minimal status readout (Wi-Fi + Battery)
                RowLayout {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 22
                    anchors.rightMargin: 28
                    spacing: 12

                    Text {
                        text: SystemStatus.wifiConnected ? "󰤨" : "󰤭"
                        color: Theme.fgSurface
                        font.family: Theme.fontMono
                        font.pixelSize: 15
                    }

                    RowLayout {
                        visible: SystemStatus.hasBattery
                        spacing: 4
                        Text {
                            text: SystemStatus.batteryCharging ? "󰂄" : "󰁹"
                            color: SystemStatus.batteryCharging ? Theme.primary : Theme.fgSurface
                            font.family: Theme.fontMono
                            font.pixelSize: 15
                        }
                        Text {
                            text: SystemStatus.batteryPercent + "%"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // Main centered M3 Expressive Lock Layout
                ColumnLayout {
                    id: mainCol
                    anchors.centerIn: parent
                    spacing: 28

                    scale: lockSurface.activeView ? 1.0 : 0.88
                    transform: Translate {
                        y: lockSurface.activeView ? 0 : 18
                        Behavior on y { SpringAnimation { spring: 7.5; damping: 0.38; epsilon: 0.05 } }
                    }
                    Behavior on scale { SpringAnimation { spring: 7.5; damping: 0.38; epsilon: 0.004 } }

                // Giant M3 Expressive Clock & Date
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 2

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: SystemStatus.timeShort
                        color: Theme.fgSurface
                        font.family: Theme.fontSans
                        font.pixelSize: 84
                        font.weight: Font.Bold
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: SystemStatus.weekdayFull + ", " + SystemStatus.monthDay
                        color: Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 16
                        font.weight: Font.Medium
                    }
                }

                // Frosted M3E Unlock Card (smooth spring height resize when status pill appears/disappears)
                Rectangle {
                    id: authCard
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 340
                    Layout.preferredHeight: authCol.implicitHeight + 36
                    radius: Theme.radiusExtraLarge
                    color: Theme.alpha(Theme.surfaceContainer, 0.84)
                    border.width: 1
                    border.color: lockScope.isError ? Theme.error : Theme.glassBorder
                    clip: true

                    Behavior on Layout.preferredHeight {
                        SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping }
                    }
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                    Connections {
                        target: lockScope
                        function onShakeTickChanged() {
                            pwInput.text = "";
                            pwInput.forceActiveFocus();
                        }
                    }

                    ColumnLayout {
                        id: authCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 18
                        spacing: 14

                        // User badge row
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                radius: 17
                                color: Theme.primaryContainer

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰀄"
                                    color: Theme.fgPrimaryContainer
                                    font.family: Theme.fontMono
                                    font.pixelSize: 17
                                }
                            }

                            Text {
                                text: lockScope.username
                                color: Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                        }

                        // Pill password input (tints softly on error instead of shaking)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            radius: Theme.radiusPill
                            color: lockScope.isError
                                ? Theme.alpha(Theme.error, 0.16)
                                : Theme.surfaceContainerHigh
                            border.width: (pwInput.activeFocus || lockScope.isError) ? 1.5 : 1
                            border.color: lockScope.isError
                                ? Theme.error
                                : (pwInput.activeFocus ? Theme.primary : Theme.glassBorder)

                            Behavior on color { ColorAnimation { duration: Motion.medium } }
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 8

                                // Left mirror spacer so the dots & placeholder sit dead-center in the pill
                                Item {
                                    Layout.preferredWidth: 34
                                    Layout.preferredHeight: 34
                                }

                                // Android M3 Expressive shape-morphing password field
                                // Hidden TextInput handles real typing; visible Row renders M3E shapes -> dots
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true

                                    property int shapeCounter: 0

                                    ListModel { id: pwDotsModel }

                                    function syncDots(len) {
                                        if (len < pwDotsModel.count) {
                                            while (pwDotsModel.count > len) {
                                                pwDotsModel.remove(pwDotsModel.count - 1);
                                            }
                                            return;
                                        }
                                        // Morph any previous active shapes to dots immediately
                                        for (let i = 0; i < pwDotsModel.count; i++) {
                                            if (!pwDotsModel.get(i).morphed) {
                                                pwDotsModel.setProperty(i, "morphed", true);
                                            }
                                        }
                                        while (pwDotsModel.count < len) {
                                            pwDotsModel.append({
                                                shapeKind: (shapeCounter++) % 5,
                                                morphed: false
                                            });
                                        }
                                    }

                                    TextInput {
                                        id: pwInput
                                        anchors.fill: parent
                                        echoMode: TextInput.Password
                                        opacity: 0
                                        enabled: !lockScope.authenticating

                                        Component.onCompleted: forceActiveFocus()

                                        onTextChanged: {
                                            parent.syncDots(text.length);
                                            if (text.length > 0 && lockScope.isError) {
                                                lockScope.isError = false;
                                                lockScope.statusMessage = "";
                                            }
                                        }

                                        Keys.onReturnPressed: lockScope.submitPassword(text)
                                        Keys.onEnterPressed: lockScope.submitPassword(text)
                                        Keys.onEscapePressed: {
                                            text = "";
                                            lockScope.statusMessage = "";
                                            lockScope.isError = false;
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.IBeamCursor
                                        onClicked: pwInput.forceActiveFocus()
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: pwInput.text.length === 0
                                        text: lockScope.isError ? "Try again..." : "Enter password..."
                                        color: lockScope.isError ? Theme.error : Theme.fgSurfaceVariant
                                        font.family: Theme.fontSans
                                        font.pixelSize: 13
                                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                                    }

                                    Row {
                                        id: dotsRow
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: width > parent.width ? (parent.width - width) : Math.round((parent.width - width) / 2)
                                        spacing: 5

                                        Behavior on x { SpringAnimation { spring: 9.0; damping: 0.45; epsilon: 0.1 } }

                                        Repeater {
                                            model: pwDotsModel

                                            delegate: Item {
                                                id: dotCell
                                                required property int shapeKind
                                                required property bool morphed
                                                required property int index

                                                width: morphed ? 8 : 15
                                                height: 16
                                                anchors.verticalCenter: parent.verticalCenter

                                                Behavior on width {
                                                    SpringAnimation { spring: 9.0; damping: 0.45; epsilon: 0.05 }
                                                }

                                                property bool popped: false
                                                Component.onCompleted: popped = true

                                                // Auto-morph shape into dot after 340ms
                                                Timer {
                                                    interval: 340
                                                    running: !dotCell.morphed
                                                    onTriggered: {
                                                        if (dotCell.index >= 0 && dotCell.index < pwDotsModel.count) {
                                                            pwDotsModel.setProperty(dotCell.index, "morphed", true);
                                                        }
                                                    }
                                                }

                                                // Expressive M3 shape (pops in on keypress, shrinks away as dot appears)
                                                Canvas {
                                                    id: glyphShape
                                                    anchors.centerIn: parent
                                                    width: 16
                                                    height: 16
                                                    property color fillColor: Theme.primary

                                                    scale: (!dotCell.morphed && dotCell.popped) ? 1.0 : 0.25
                                                    opacity: (!dotCell.morphed && dotCell.popped) ? 1.0 : 0.0
                                                    visible: opacity > 0.02

                                                    Behavior on scale { SpringAnimation { spring: 9.5; damping: 0.34; epsilon: 0.005 } }
                                                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                                    onFillColorChanged: requestPaint()
                                                    Component.onCompleted: requestPaint()

                                                    onPaint: {
                                                        const ctx = getContext("2d");
                                                        ctx.clearRect(0, 0, width, height);
                                                        const cx = width / 2;
                                                        const cy = height / 2;
                                                        ctx.fillStyle = fillColor;
                                                        ctx.beginPath();

                                                        if (dotCell.shapeKind === 0) {
                                                            // 4-point M3 clover / star
                                                            const steps = 64;
                                                            for (let i = 0; i <= steps; i++) {
                                                                const t = (i / steps) * Math.PI * 2;
                                                                const r = 5.4 + 1.9 * Math.cos(4 * t);
                                                                const px = cx + r * Math.cos(t);
                                                                const py = cy + r * Math.sin(t);
                                                                if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                                                            }
                                                        } else if (dotCell.shapeKind === 1) {
                                                            // Soft rounded diamond
                                                            const steps = 64;
                                                            for (let i = 0; i <= steps; i++) {
                                                                const t = (i / steps) * Math.PI * 2;
                                                                const c = Math.cos(t), s = Math.sin(t);
                                                                const r = 6.8 / Math.pow(Math.pow(Math.abs(c), 1.45) + Math.pow(Math.abs(s), 1.45), 1 / 1.45);
                                                                const px = cx + r * c;
                                                                const py = cy + r * s;
                                                                if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                                                            }
                                                        } else if (dotCell.shapeKind === 2) {
                                                            // 6-scallop cookie
                                                            const steps = 72;
                                                            for (let i = 0; i <= steps; i++) {
                                                                const t = (i / steps) * Math.PI * 2;
                                                                const r = 5.7 + 1.3 * Math.cos(6 * t);
                                                                const px = cx + r * Math.cos(t);
                                                                const py = cy + r * Math.sin(t);
                                                                if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                                                            }
                                                        } else if (dotCell.shapeKind === 3) {
                                                            // Soft 3-lobe clover
                                                            const steps = 64;
                                                            for (let i = 0; i <= steps; i++) {
                                                                const t = (i / steps) * Math.PI * 2;
                                                                const r = 5.5 + 1.7 * Math.cos(3 * t - Math.PI / 2);
                                                                const px = cx + r * Math.cos(t);
                                                                const py = cy + r * Math.sin(t);
                                                                if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                                                            }
                                                        } else {
                                                            // Rounded squircle
                                                            const steps = 64;
                                                            for (let i = 0; i <= steps; i++) {
                                                                const t = (i / steps) * Math.PI * 2;
                                                                const c = Math.cos(t), s = Math.sin(t);
                                                                const r = 6.2 / Math.pow(Math.pow(Math.abs(c), 4) + Math.pow(Math.abs(s), 4), 0.25);
                                                                const px = cx + r * c;
                                                                const py = cy + r * s;
                                                                if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                                                            }
                                                        }

                                                        ctx.closePath();
                                                        ctx.fill();
                                                    }
                                                }

                                                // Settled clean dot (scales in as the M3E shape morphs down)
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 7
                                                    height: 7
                                                    radius: 3.5
                                                    color: Theme.fgSurface
                                                    scale: dotCell.morphed ? 1.0 : 0.2
                                                    opacity: dotCell.morphed ? 1.0 : 0.0

                                                    Behavior on scale { SpringAnimation { spring: 9.0; damping: 0.42; epsilon: 0.005 } }
                                                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Submit circular pill button (morphs to squircle + spins while authenticating)
                                Rectangle {
                                    Layout.preferredWidth: 34
                                    Layout.preferredHeight: 34
                                    radius: lockScope.authenticating ? 10 : 17
                                    color: lockScope.isError
                                        ? Theme.error
                                        : ((pwInput.text.length > 0 || lockScope.authenticating) ? Theme.primary : Theme.surfaceContainerHighest)

                                    scale: submitM.pressed ? 0.9 : 1.0
                                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                                    Behavior on radius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                    // Static arrow / error icon (never rotated)
                                    Text {
                                        visible: !lockScope.authenticating
                                        anchors.centerIn: parent
                                        text: lockScope.isError ? "󰀦" : "󰁔"
                                        color: lockScope.isError
                                            ? Theme.fgError
                                            : (pwInput.text.length > 0 ? Theme.fgPrimary : Theme.fgSurfaceVariant)
                                        font.family: Theme.fontMono
                                        font.pixelSize: 16
                                    }

                                    // Pixel-centered Material 3 arc spinner (only visible while authenticating)
                                    Canvas {
                                        id: spinnerArc
                                        visible: lockScope.authenticating
                                        anchors.centerIn: parent
                                        width: 18
                                        height: 18
                                        property color strokeColor: Theme.fgPrimary

                                        onStrokeColorChanged: requestPaint()
                                        onVisibleChanged: if (visible) requestPaint()

                                        onPaint: {
                                            const ctx = getContext("2d");
                                            ctx.clearRect(0, 0, width, height);
                                            ctx.beginPath();
                                            ctx.arc(width / 2, height / 2, 6.5, 0, Math.PI * 1.45);
                                            ctx.strokeStyle = strokeColor;
                                            ctx.lineWidth = 2.2;
                                            ctx.lineCap = "round";
                                            ctx.stroke();
                                        }

                                        RotationAnimator on rotation {
                                            from: 0
                                            to: 360
                                            duration: 700
                                            loops: Animation.Infinite
                                            running: lockScope.authenticating
                                        }
                                    }

                                    MouseArea {
                                        id: submitM
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: lockScope.submitPassword(pwInput.text)
                                    }
                                }
                            }
                        }

                        // Smoothly animated M3 status / error chip
                        Rectangle {
                            visible: lockScope.statusMessage.length > 0
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredHeight: 26
                            Layout.preferredWidth: statusRow.implicitWidth + 20
                            radius: 13
                            color: lockScope.isError
                                ? Theme.alpha(Theme.error, 0.2)
                                : Theme.alpha(Theme.primaryContainer, 0.65)

                            opacity: visible ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            RowLayout {
                                id: statusRow
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: lockScope.isError ? "󰀦" : "󰌾"
                                    color: lockScope.isError ? Theme.error : Theme.fgPrimaryContainer
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }

                                Text {
                                    text: lockScope.statusMessage
                                    color: lockScope.isError ? Theme.error : Theme.fgPrimaryContainer
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }
                }

                // Fingerprint sensor status pill (parallel fprintd-verify)
                Row {
                    visible: lockScope.fprintActive || lockScope.fprintHint.length > 0
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6

                    Text {
                        text: "󰈷"
                        color: lockScope.fprintHint.length > 0 ? Theme.error : Theme.primary
                        font.family: Theme.fontMono
                        font.pixelSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: lockScope.fprintHint.length > 0 ? lockScope.fprintHint : "Touch fingerprint sensor"
                        color: lockScope.fprintHint.length > 0 ? Theme.error : Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Shared Android M3 Expressive Lockscreen Media Card
                MediaCard {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 340
                    Layout.preferredHeight: 128
                    cardRadius: Theme.radiusExtraLarge
                    animateWave: ShellState.locked
                }
            }

            // Bottom-right quick power pills
            RowLayout {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.bottomMargin: 24
                anchors.rightMargin: 28
                spacing: 10

                Repeater {
                    model: [
                        { icon: "󰤄", action: "suspend" },
                        { icon: "󰜉", action: "reboot" },
                        { icon: "󰐥", action: "poweroff" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        radius: pm.pressed ? 12 : 20
                        color: pm.containsMouse
                            ? (modelData.action === "poweroff" ? Theme.error : Theme.primaryContainer)
                            : Theme.alpha(Theme.surfaceContainerHigh, 0.8)
                        border.width: 1
                        border.color: Theme.glassBorder

                        scale: pm.pressed ? 0.92 : 1.0
                        Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            color: pm.containsMouse && modelData.action === "poweroff" ? Theme.fgError : Theme.fgSurface
                            font.family: Theme.fontMono
                            font.pixelSize: 17
                        }

                        MouseArea {
                            id: pm
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.action === "suspend") SystemStatus.suspendSystem();
                                else if (modelData.action === "reboot") SystemStatus.rebootSystem();
                                else if (modelData.action === "poweroff") SystemStatus.poweroffSystem();
                            }
                        }
                    }
                }
            }
            }
        }
    }
}
