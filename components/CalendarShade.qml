import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

PanelWindow {
    id: calWin

    required property var modelData
    screen: modelData

    readonly property bool isOpen: ShellState.activeOverlay === "calendar"
    property bool windowVisible: false
    visible: windowVisible

    Timer { id: openTrigger; interval: 25; onTriggered: card.state = "open" }

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

    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth() // 0..11
    property int selectedDay: -1
    property int slideDir: 1

    readonly property bool isViewingCurrentMonth: {
        const now = new Date();
        return viewYear === now.getFullYear() && viewMonth === now.getMonth();
    }

    readonly property int effectiveDay: {
        if (selectedDay > 0) return selectedDay;
        if (isViewingCurrentMonth) return new Date().getDate();
        return -1;
    }

    readonly property var activeDayEvents: effectiveDay > 0
        ? CalendarEvents.eventsForDate(viewYear, viewMonth, effectiveDay)
        : []

    readonly property string activeDayLabel: {
        if (effectiveDay <= 0) return "";
        const now = new Date();
        if (viewYear === now.getFullYear() && viewMonth === now.getMonth() && effectiveDay === now.getDate()) {
            return "Today";
        }
        return Qt.formatDate(new Date(viewYear, viewMonth, effectiveDay), "ddd, MMM d");
    }

    onIsOpenChanged: {
        if (isOpen) {
            const now = new Date();
            viewYear = now.getFullYear();
            viewMonth = now.getMonth();
            selectedDay = -1;
            card.state = "closed";
            windowVisible = true;
            openTrigger.restart();
            CalendarEvents.refresh();
        } else {
            openTrigger.stop();
            card.state = "closed";
        }
    }

    readonly property var calendarCells: {
        const first = new Date(viewYear, viewMonth, 1);
        const startDay = first.getDay(); // 0=Sun
        const daysInMonth = new Date(viewYear, viewMonth + 1, 0).getDate();
        const prevDays = new Date(viewYear, viewMonth, 0).getDate();
        const now = new Date();
        const isCurrentMonth = (now.getFullYear() === viewYear && now.getMonth() === viewMonth);
        const todayDate = now.getDate();

        const cells = [];
        for (let i = startDay - 1; i >= 0; i--) {
            cells.push({ day: prevDays - i, inMonth: false, isToday: false, col: cells.length % 7 });
        }
        for (let d = 1; d <= daysInMonth; d++) {
            cells.push({ day: d, inMonth: true, isToday: isCurrentMonth && d === todayDate, col: cells.length % 7 });
        }
        while (cells.length % 7 !== 0) {
            cells.push({ day: cells.length - (startDay + daysInMonth) + 1, inMonth: false, isToday: false, col: cells.length % 7 });
        }
        return cells;
    }

    readonly property string monthLabel: Qt.formatDate(new Date(viewYear, viewMonth, 1), "MMMM yyyy")

    function stepMonth(delta) {
        slideDir = delta >= 0 ? 1 : -1;
        let m = viewMonth + delta;
        let y = viewYear;
        if (m < 0) { m = 11; y -= 1; }
        else if (m > 11) { m = 0; y += 1; }
        selectedDay = -1;
        viewYear = y;
        viewMonth = m;
        monthSlideAnim.restart();
    }

    function jumpToToday() {
        const now = new Date();
        const curVal = viewYear * 12 + viewMonth;
        const nowVal = now.getFullYear() * 12 + now.getMonth();
        slideDir = nowVal >= curVal ? 1 : -1;
        selectedDay = -1;
        viewYear = now.getFullYear();
        viewMonth = now.getMonth();
        monthSlideAnim.restart();
    }

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.closeOverlay()
    }

    // Pop-in M3E Calendar Card (anchored right below the top-left clock)
    Rectangle {
        id: card
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 6
        anchors.leftMargin: 12
        width: 324
        height: calCol.implicitHeight + 32
        radius: Theme.radiusExtraLarge
        color: Theme.glassSurface
        border.width: 1
        border.color: Theme.glassBorder
        clip: true

        Behavior on height {
            enabled: card.state === "open"
            SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping }
        }

        focus: calWin.isOpen
        Keys.onEscapePressed: ShellState.closeOverlay()
        Keys.onLeftPressed: calWin.stepMonth(-1)
        Keys.onRightPressed: calWin.stepMonth(1)

        MouseArea { anchors.fill: parent }

        WheelHandler {
            onWheel: event => {
                if (event.angleDelta.y > 0) calWin.stepMonth(-1);
                else if (event.angleDelta.y < 0) calWin.stepMonth(1);
            }
        }

        transformOrigin: Item.TopLeft
        state: "closed"
        opacity: 0.0
        scale: 0.86
        transform: Translate { id: cardTranslate; y: -12 }

        states: [
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
                        script: { if (!calWin.isOpen) calWin.windowVisible = false; }
                    }
                }
            }
        ]

        ColumnLayout {
            id: calCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 10

            // Top today banner + "Today" jump pill when viewing another month
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: SystemStatus.weekdayFull
                        color: Theme.primary
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: SystemStatus.monthDay
                        color: Theme.fgSurface
                        font.family: Theme.fontSans
                        font.pixelSize: 17
                        font.weight: Font.Bold
                    }
                }

                // Jump back to Today pill
                Rectangle {
                    visible: !calWin.isViewingCurrentMonth
                    Layout.preferredHeight: 26
                    Layout.preferredWidth: todayTxt.implicitWidth + 18
                    radius: 13
                    color: todayBtnM.containsMouse ? Theme.primary : Theme.primaryContainer
                    scale: todayBtnM.pressed ? 0.92 : 1.0
                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        id: todayTxt
                        anchors.centerIn: parent
                        text: "Today"
                        color: todayBtnM.containsMouse ? Theme.fgPrimary : Theme.fgPrimaryContainer
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: todayBtnM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calWin.jumpToToday()
                    }
                }
            }

            // Month navigation header
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: calWin.monthLabel
                    color: Theme.fgSurface
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: 14
                    color: prevM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                    scale: prevM.pressed ? 0.88 : 1.0
                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Text { anchors.centerIn: parent; text: "󰅁"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                    MouseArea { id: prevM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: calWin.stepMonth(-1) }
                }

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: 14
                    color: nextM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                    scale: nextM.pressed ? 0.88 : 1.0
                    Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Text { anchors.centerIn: parent; text: "󰅂"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                    MouseArea { id: nextM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: calWin.stepMonth(1) }
                }
            }

            // Weekday headers
            GridLayout {
                Layout.fillWidth: true
                columns: 7
                columnSpacing: 2

                Repeater {
                    model: ["S", "M", "T", "W", "T", "F", "S"]
                    delegate: Text {
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: (index === 0 || index === 6) ? Theme.alpha(Theme.primary, 0.8) : Theme.fgSurfaceVariant
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }

            // Animated day grid (slides & fades smoothly when switching months)
            Item {
                id: gridHost
                Layout.fillWidth: true
                Layout.preferredHeight: dayGrid.implicitHeight
                clip: true

                ParallelAnimation {
                    id: monthSlideAnim
                    NumberAnimation {
                        target: gridSlide
                        property: "x"
                        from: calWin.slideDir * 28
                        to: 0
                        duration: 210
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: dayGrid
                        property: "opacity"
                        from: 0.0
                        to: 1.0
                        duration: 180
                        easing.type: Easing.OutQuad
                    }
                }

                GridLayout {
                    id: dayGrid
                    anchors.left: parent.left
                    anchors.right: parent.right
                    columns: 7
                    columnSpacing: 2
                    rowSpacing: 3
                    transform: Translate { id: gridSlide; x: 0 }

                    Repeater {
                        model: calWin.calendarCells

                        delegate: Item {
                            id: dayCell
                            required property var modelData
                            readonly property bool isSelected: modelData.inMonth && calWin.selectedDay === modelData.day && !modelData.isToday
                            readonly property var dayEvents: modelData.inMonth
                                ? CalendarEvents.eventsForDate(calWin.viewYear, calWin.viewMonth, modelData.day)
                                : []
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34

                            Rectangle {
                                anchors.centerIn: parent
                                width: 32
                                height: 32
                                radius: modelData.isToday ? 16 : (dayCell.isSelected ? 11 : 16)
                                color: modelData.isToday
                                    ? Theme.primary
                                    : (dayCell.isSelected
                                        ? Theme.primaryContainer
                                        : (dayM.containsMouse ? Theme.surfaceContainerHighest : "transparent"))
                                scale: dayM.pressed ? 0.88 : (dayM.containsMouse ? 1.08 : 1.0)

                                Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Behavior on radius { SpringAnimation { spring: Motion.morphSpring; damping: Motion.morphDamping } }

                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: dayCell.dayEvents.length > 0 ? -2 : 0
                                    text: modelData.day
                                    color: modelData.isToday
                                        ? Theme.fgPrimary
                                        : (dayCell.isSelected
                                            ? Theme.fgPrimaryContainer
                                            : (modelData.inMonth
                                                ? ((modelData.col === 0 || modelData.col === 6) ? Theme.alpha(Theme.fgSurface, 0.82) : Theme.fgSurface)
                                                : Theme.alpha(Theme.fgSurfaceVariant, 0.34)))
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    font.weight: (modelData.isToday || dayCell.isSelected) ? Font.Bold : Font.Normal
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }

                                // Colored event dots under the day number
                                Row {
                                    visible: dayCell.dayEvents.length > 0
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 3
                                    spacing: 2

                                    Repeater {
                                        model: Math.min(3, dayCell.dayEvents.length)
                                        delegate: Rectangle {
                                            required property int index
                                            width: 4
                                            height: 4
                                            radius: 2
                                            color: modelData.isToday ? Theme.fgPrimary : (dayCell.dayEvents[index].color || Theme.primary)
                                        }
                                    }
                                }

                                MouseArea {
                                    id: dayM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.inMonth) {
                                            calWin.selectedDay = (calWin.selectedDay === modelData.day) ? -1 : modelData.day;
                                        } else {
                                            calWin.stepMonth(modelData.day > 15 ? -1 : 1);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Divider + Google Calendar Agenda section (only shown when a Google account is connected)
            Rectangle {
                visible: CalendarEvents.status === "ok"
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 2
                color: Theme.glassBorder
            }

            // Agenda header (selected day + sync/refresh button)
            RowLayout {
                visible: CalendarEvents.status === "ok"
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: calWin.activeDayLabel ? (calWin.activeDayLabel + " · Agenda") : "Agenda"
                    color: Theme.fgSurfaceVariant
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 12
                    color: syncM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "󰑐"
                        color: CalendarEvents.syncing ? Theme.primary : Theme.fgSurfaceVariant
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: syncM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: CalendarEvents.refresh()
                    }
                }
            }

            // Empty agenda text when signed in but day has no events
            Text {
                visible: CalendarEvents.status === "ok" && calWin.activeDayEvents.length === 0
                Layout.fillWidth: true
                text: "No events scheduled"
                color: Theme.fgSurfaceVariant
                font.family: Theme.fontSans
                font.pixelSize: 11
            }

            // Event list for the selected day
            ColumnLayout {
                visible: calWin.activeDayEvents.length > 0
                Layout.fillWidth: true
                spacing: 5

                Repeater {
                    model: calWin.activeDayEvents.slice(0, 5)

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: evCol.implicitHeight + 12
                        radius: 12
                        color: Theme.surfaceContainerHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 3
                                Layout.fillHeight: true
                                radius: 2
                                color: modelData.color || Theme.primary
                            }

                            ColumnLayout {
                                id: evCol
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelData.title
                                    color: Theme.fgSurface
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelData.time + (modelData.location ? (" · " + modelData.location) : "")
                                    color: Theme.fgSurfaceVariant
                                    font.family: Theme.fontSans
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
