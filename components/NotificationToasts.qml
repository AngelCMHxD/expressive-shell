import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../theme"
import "../services"

PanelWindow {
    id: toastWin

    required property var modelData
    screen: modelData

    visible: toastModel.count > 0 && ShellState.activeOverlay !== "notifications"

    anchors {
        top: true
        right: true
    }

    // Extra invisible padding around the stack so spring overshoot never clips
    readonly property int cardWidth: 356
    readonly property int padRight: 14
    readonly property int padTop: 6
    readonly property int overshootPad: 28

    property bool stackExpanded: false
    property int layoutRev: 0

    implicitWidth: padRight + cardWidth + overshootPad
    // Keep Wayland surface tall enough for the full expanded stack so collapsing animations
    // are never clipped; `mask` restricts pointer input strictly to the active stack area.
    implicitHeight: Math.max(1, padTop + toastStack.fullExpandedHeight + overshootPad)
    exclusiveZone: 0
    color: "transparent"

    mask: Region {
        item: toastStack
    }

    WlrLayershell.namespace: "expressive-shade"
    WlrLayershell.layer: WlrLayer.Overlay

    ListModel {
        id: toastModel
        onCountChanged: {
            toastWin.layoutRev++;
            if (count <= 2) toastWin.stackExpanded = false;
        }
    }

    Timer {
        id: collapseDelay
        interval: 260
        onTriggered: {
            if (!stackHover.hovered) toastWin.stackExpanded = false;
        }
    }

    function markClosing(uid) {
        for (let i = 0; i < toastModel.count; i++) {
            if (toastModel.get(i).uid === uid) {
                toastModel.setProperty(i, "closing", true);
                break;
            }
        }
    }

    function removeFromModel(uid) {
        for (let i = 0; i < toastModel.count; i++) {
            if (toastModel.get(i).uid === uid) {
                toastModel.remove(i);
                break;
            }
        }
    }

    Connections {
        target: Notifications
        function onToastAdded(entry) {
            toastModel.insert(0, {
                uid: entry.uid,
                appName: entry.appName || "Notification",
                iconSource: entry.iconSource || "",
                appBadgeSource: entry.appBadgeSource || "",
                isContextImage: Boolean(entry.isContextImage),
                summary: entry.summary || "",
                body: entry.body || "",
                time: entry.time || "",
                closing: false
            });
        }
        function onToastDismissRequested(uid) {
            toastWin.markClosing(uid);
        }
    }

    Item {
        id: toastStack
        x: toastWin.overshootPad
        y: toastWin.padTop
        width: toastWin.cardWidth
        height: stackHeight

        readonly property int gap: 8

        function cardH(idx) {
            const it = toastRepeater.itemAt(idx);
            return it ? it.cardHeight : 68;
        }

        function expandedY(idx) {
            let yPos = 0;
            for (let i = 0; i < idx; i++) {
                yPos += cardH(i) + gap;
            }
            return yPos;
        }

        function collapsedBottomOfSecond() {
            if (toastModel.count <= 0) return 0;
            if (toastModel.count === 1) return cardH(0);
            return cardH(0) + gap + cardH(1);
        }

        readonly property real fullExpandedHeight: {
            const _rev = toastWin.layoutRev;
            const n = toastModel.count;
            if (n === 0) return 0;
            let total = 0;
            for (let i = 0; i < n; i++) {
                total += cardH(i) + (i < n - 1 ? gap : 0);
            }
            return total;
        }

        readonly property real stackHeight: {
            const _rev = toastWin.layoutRev;
            const n = toastModel.count;
            if (n === 0) return 0;
            if (toastWin.stackExpanded || n <= 2) {
                return fullExpandedHeight;
            }
            // Collapsed with 3+ toasts: two full cards + peeking deck below card #2
            const peekExtra = n >= 4 ? 17 : 11;
            return collapsedBottomOfSecond() + peekExtra;
        }

        HoverHandler {
            id: stackHover
            onHoveredChanged: {
                if (hovered) {
                    collapseDelay.stop();
                    if (toastModel.count > 2) toastWin.stackExpanded = true;
                } else {
                    collapseDelay.restart();
                }
            }
        }

        Repeater {
            id: toastRepeater
            model: toastModel

            delegate: Rectangle {
                id: toastCard
                required property int uid
                required property string appName
                required property string iconSource
                required property string appBadgeSource
                required property bool isContextImage
                required property string summary
                required property string body
                required property string time
                required property bool closing
                required property int index

                property bool appeared: false
                readonly property bool activeState: appeared && !closing
                readonly property bool isCollapsedOverflow: !toastWin.stackExpanded && index >= 2
                readonly property real cardHeight: Math.max(64, row.implicitHeight + 24)

                onCardHeightChanged: toastWin.layoutRev++
                Component.onCompleted: {
                    toastWin.layoutRev++;
                    appeared = true;
                }

                // Newer notifications render on top so older ones tuck cleanly underneath
                z: 200 - index
                width: toastStack.width
                height: cardHeight
                radius: Theme.radiusLarge
                color: Theme.glassSurfaceHigh
                border.width: 1
                border.color: Theme.glassBorder

                // Target position: full stack when expanded (or top 2), peeking behind card #2 when collapsed
                y: {
                    const _rev = toastWin.layoutRev;
                    if (!isCollapsedOverflow) {
                        return toastStack.expandedY(index);
                    }
                    const bottom2 = toastStack.collapsedBottomOfSecond();
                    const peekOffset = index === 2 ? 10 : 16;
                    return Math.max(0, bottom2 - cardHeight + peekOffset);
                }

                Behavior on y {
                    SpringAnimation { spring: 10.5; damping: 0.62; epsilon: 0.5 }
                }

                transformOrigin: Item.Bottom
                scale: {
                    if (!activeState) return closing ? 0.84 : 0.78;
                    if (!isCollapsedOverflow) return 1.0;
                    if (index === 2) return 0.94;
                    if (index === 3) return 0.88;
                    return 0.84;
                }
                opacity: {
                    if (!activeState) return 0.0;
                    if (!isCollapsedOverflow) return 1.0;
                    if (index === 2) return 0.86;
                    if (index === 3) return 0.45;
                    return 0.0;
                }
                visible: opacity > 0.01 || !appeared

                transform: Translate {
                    x: toastCard.closing ? 24 : 0
                    y: toastCard.appeared ? 0 : -12
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.InCubic } }
                    Behavior on y { SpringAnimation { spring: Motion.popSpring; damping: Motion.popDamping } }
                }

                Behavior on scale {
                    SpringAnimation { spring: Motion.popSpring; damping: Motion.popDamping }
                }
                Behavior on opacity { NumberAnimation { duration: toastCard.closing ? 160 : 180 } }

                // After exit animation finishes, remove from ListModel
                Timer {
                    id: removeTimer
                    interval: 190
                    running: toastCard.closing
                    onTriggered: toastWin.removeFromModel(toastCard.uid)
                }

                // Smoothly driven countdown for both the ring around × and auto-dismiss;
                // pauses seamlessly while hovering/expanding the stack
                property real timeLeft: 1.0

                NumberAnimation on timeLeft {
                    from: 1.0
                    to: 0.0
                    duration: 5000
                    running: !toastCard.closing
                    paused: stackHover.hovered || toastWin.stackExpanded
                    onFinished: {
                        if (!toastCard.closing) Notifications.dismissToast(toastCard.uid);
                    }
                }

                RowLayout {
                    id: row
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 14
                    spacing: 12
                    opacity: toastCard.isCollapsedOverflow ? 0.0 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 140 } }

                    Item {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40

                        ClippingRectangle {
                            anchors.centerIn: parent
                            width: 38
                            height: 38
                            radius: toastCard.isContextImage ? 19 : 12
                            color: Theme.primaryContainer

                            Image {
                                id: toastIconImg
                                anchors.fill: parent
                                anchors.margins: toastCard.isContextImage ? 0 : 5
                                visible: toastCard.iconSource.length > 0 && status === Image.Ready
                                source: toastCard.iconSource
                                fillMode: toastCard.isContextImage ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                                sourceSize.width: 76
                                sourceSize.height: 76
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !toastIconImg.visible
                                text: "󰂚"
                                color: Theme.fgPrimaryContainer
                                font.family: Theme.fontMono
                                font.pixelSize: 16
                            }
                        }

                        // Small app icon badge in bottom-right corner when a context image is shown
                        Rectangle {
                            visible: toastCard.isContextImage && toastCard.appBadgeSource.length > 0 && toastBadgeImg.status === Image.Ready
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            width: 17
                            height: 17
                            radius: 8.5
                            color: Theme.surfaceContainerHigh
                            border.width: 1.5
                            border.color: Theme.surfaceContainer

                            Image {
                                id: toastBadgeImg
                                anchors.centerIn: parent
                                width: 11
                                height: 11
                                sourceSize.width: 22
                                sourceSize.height: 22
                                smooth: true
                                mipmap: true
                                source: toastCard.appBadgeSource
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: toastCard.summary || toastCard.appName
                                elide: Text.ElideRight
                                color: Theme.fgSurface
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: toastCard.time
                                color: Theme.fgSurfaceVariant
                                font.family: Theme.fontSans
                                font.pixelSize: 10
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: toastCard.body.length > 0
                            text: toastCard.body
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            color: Theme.fgSurfaceVariant
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                        }
                    }

                    Item {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 11
                            color: closeM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }

                        // Auto-dismiss countdown ring around ×
                        Canvas {
                            id: ringCanvas
                            anchors.fill: parent
                            property real frac: toastCard.timeLeft
                            property color ringColor: Theme.primary
                            property color trackColor: Theme.alpha(Theme.fgSurfaceVariant, 0.22)

                            onFracChanged: requestPaint()
                            onRingColorChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                const cx = width / 2;
                                const cy = height / 2;
                                const r = (Math.min(width, height) / 2) - 1.6;

                                // Subtle full track
                                ctx.strokeStyle = trackColor;
                                ctx.lineWidth = 1.7;
                                ctx.beginPath();
                                ctx.arc(cx, cy, r, 0, Math.PI * 2);
                                ctx.stroke();

                                // Remaining time arc
                                if (frac > 0.005) {
                                    ctx.strokeStyle = ringColor;
                                    ctx.lineWidth = 1.7;
                                    ctx.lineCap = "round";
                                    ctx.beginPath();
                                    const start = -Math.PI / 2;
                                    ctx.arc(cx, cy, r, start, start + Math.PI * 2 * frac, false);
                                    ctx.stroke();
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            color: closeM.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: closeM
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !toastCard.isCollapsedOverflow
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifications.dismissToast(toastCard.uid)
                        }
                    }
                }
            }
        }
    }
}
