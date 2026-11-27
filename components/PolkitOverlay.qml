import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Polkit
import "../theme"
import "../services"

// Native Expressive Shell / Android 17 Polkit Authentication Agent
Scope {
    id: polkitScope

    PolkitAgent {
        id: agent
    }

    readonly property var flow: agent.flow
    readonly property bool isActive: agent.isActive && flow !== null

    PanelWindow {
        id: polkitWin
        visible: polkitScope.isActive

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
        WlrLayershell.keyboardFocus: polkitScope.isActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                pwInput.text = "";
                card.scale = 0.88;
                card.opacity = 0.0;
                openAnim.restart();
                focusTimer.restart();
            }
        }

        Timer {
            id: focusTimer
            interval: 40
            onTriggered: pwInput.forceActiveFocus()
        }

        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0.0; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
            SpringAnimation { target: card; property: "scale"; from: 0.88; to: 1.0; spring: 8.5; damping: 0.45; epsilon: 0.004 }
        }

        // Soft backdrop scrim
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.46)
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (polkitScope.flow) polkitScope.flow.cancelAuthenticationRequest();
                }
            }
        }

        // Centered M3E Polkit Dialog Card
        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 404
            height: contentCol.implicitHeight + 36
            radius: Theme.radiusExtraLarge
            color: Theme.glassSurfaceHigh
            border.width: 1
            border.color: Theme.glassBorder
            clip: true

            Behavior on height {
                SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping }
            }

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: contentCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                spacing: 14

                // Header: Avatar / Shield + Title + Action ID
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ClippingRectangle {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: 22
                        color: Theme.primaryContainer

                        Image {
                            id: polkitAvatar
                            anchors.fill: parent
                            source: ShellState.resolvedUserAvatarPath ? ("file://" + ShellState.resolvedUserAvatarPath) : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                            smooth: true
                            mipmap: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !polkitAvatar.visible
                            text: "󰒃"
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
                            text: "Authentication required"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                            font.weight: Font.Bold
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: polkitScope.flow !== null && String(polkitScope.flow.actionId || "").length > 0
                            elide: Text.ElideRight
                            text: polkitScope.flow ? String(polkitScope.flow.actionId || "") : ""
                            color: Theme.fgSurfaceVariant
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                        }
                    }
                }

                // Polkit prompt message
                Text {
                    Layout.fillWidth: true
                    visible: polkitScope.flow !== null && String(polkitScope.flow.message || "").length > 0
                    text: polkitScope.flow ? String(polkitScope.flow.message || "") : ""
                    wrapMode: Text.WordWrap
                    color: Theme.fgSurface
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                }

                // Fingerprint sensor prompt pill (only when system has an enrolled fingerprint reader)
                Rectangle {
                    visible: SystemStatus.hasFingerprint && polkitScope.flow !== null && !polkitScope.flow.isResponseRequired && !polkitScope.flow.isCompleted
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    radius: 23
                    color: Theme.primaryContainer

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 10

                        Text {
                            text: "󰈷"
                            color: Theme.fgPrimaryContainer
                            font.family: Theme.fontMono
                            font.pixelSize: 20
                        }

                        Text {
                            text: "Touch fingerprint sensor"
                            color: Theme.fgPrimaryContainer
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // Password / response input pill + side fingerprint retry button
                RowLayout {
                    visible: polkitScope.flow === null || polkitScope.flow.isResponseRequired
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 22
                        color: Theme.surfaceContainerHigh
                        border.width: pwInput.activeFocus ? 1.5 : 1
                        border.color: (polkitScope.flow && (polkitScope.flow.failed || polkitScope.flow.supplementaryIsError))
                            ? Theme.error
                            : (pwInput.activeFocus ? Theme.primary : Theme.glassBorder)

                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 10

                            Text {
                                text: "󰌾"
                                color: Theme.primary
                                font.family: Theme.fontMono
                                font.pixelSize: 15
                            }

                            TextInput {
                                id: pwInput
                                Layout.fillWidth: true
                                echoMode: (polkitScope.flow && polkitScope.flow.responseVisible)
                                    ? TextInput.Normal
                                    : TextInput.Password
                                color: Theme.fgSurface
                                selectionColor: Theme.primaryContainer
                                selectedTextColor: Theme.fgPrimaryContainer
                                font.family: Theme.fontSans
                                font.pixelSize: 13
                                clip: true

                                Keys.onEscapePressed: {
                                    if (polkitScope.flow) polkitScope.flow.cancelAuthenticationRequest();
                                }
                                Keys.onReturnPressed: submitNow()
                                Keys.onEnterPressed: submitNow()

                                function submitNow() {
                                    if (!polkitScope.flow || !polkitScope.flow.isResponseRequired) return;
                                    const val = text;
                                    text = "";
                                    polkitScope.flow.submit(val);
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: pwInput.text.length === 0
                                    text: (polkitScope.flow && polkitScope.flow.inputPrompt)
                                        ? String(polkitScope.flow.inputPrompt)
                                        : "Enter password..."
                                    color: Theme.fgSurfaceVariant
                                    font.family: Theme.fontSans
                                    font.pixelSize: 13
                                }
                            }
                        }
                    }

                    // Side fingerprint button to retry fingerprint auth (only shown when fingerprint is configured)
                    Rectangle {
                        visible: SystemStatus.hasFingerprint
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: 22
                        color: fpRetryM.containsMouse ? Theme.primaryContainer : Theme.surfaceContainerHigh
                        border.width: 1
                        border.color: Theme.glassBorder
                        scale: fpRetryM.pressed ? 0.90 : 1.0
                        Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰈷"
                            color: fpRetryM.containsMouse ? Theme.fgPrimaryContainer : Theme.primary
                            font.family: Theme.fontMono
                            font.pixelSize: 20
                        }

                        MouseArea {
                            id: fpRetryM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (polkitScope.flow && polkitScope.flow.isResponseRequired) {
                                    pwInput.text = "";
                                    polkitScope.flow.submit("");
                                }
                            }
                        }
                    }
                }

                // Error / info feedback pill (high-contrast tinted surface)
                Rectangle {
                    readonly property string msg: polkitScope.flow
                        ? (String(polkitScope.flow.supplementaryMessage || "")
                            || (polkitScope.flow.failed ? "Authentication failed — please try again" : ""))
                        : ""
                    readonly property bool isErr: polkitScope.flow
                        ? (Boolean(polkitScope.flow.supplementaryIsError) || Boolean(polkitScope.flow.failed))
                        : false
                    visible: msg.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: errTxt.implicitHeight + 14
                    radius: 12
                    color: isErr ? Theme.alpha(Theme.error, 0.18) : Theme.primaryContainer
                    border.width: 1
                    border.color: isErr ? Theme.alpha(Theme.error, 0.45) : "transparent"

                    Text {
                        id: errTxt
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        wrapMode: Text.WordWrap
                        text: parent.msg
                        color: parent.isErr ? Theme.error : Theme.fgPrimaryContainer
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }

                // Bottom action buttons
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        radius: 20
                        color: cancelM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        scale: cancelM.pressed ? 0.96 : 1.0
                        Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.fgSurface
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: cancelM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (polkitScope.flow) polkitScope.flow.cancelAuthenticationRequest();
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        radius: 20
                        color: Theme.primary
                        opacity: (polkitScope.flow && polkitScope.flow.isResponseRequired) ? 1.0 : 0.6
                        scale: authM.pressed ? 0.96 : 1.0
                        Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }

                        Text {
                            anchors.centerIn: parent
                            text: "Authenticate"
                            color: Theme.fgPrimary
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: authM
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pwInput.submitNow()
                        }
                    }
                }
            }
        }
    }
}
