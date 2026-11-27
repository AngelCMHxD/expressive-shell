import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../services"

// Native Expressive Shell / Android 17 Region Picker, Annotator & Screenshot Utility
PanelWindow {
    id: shotWin

    required property var modelData
    screen: modelData

    readonly property bool isOpen: ShellState.activeOverlay === "screenshot"
    property bool windowVisible: false
    property string freezePath: ""
    property string errorMsg: ""

    // Exact target selection coordinates (used for pixel-accurate cropping)
    property bool hasSelection: false
    property bool springEnabled: true
    property real selX: 0
    property real selY: 0
    property real selW: 0
    property real selH: 0

    // Expressive wobbly spring-smoothed visual coordinates for the cutout & border
    property real visX: selX
    property real visY: selY
    property real visW: selW
    property real visH: selH

    Behavior on visX { enabled: shotWin.springEnabled; SpringAnimation { spring: 10.8; damping: 0.37; epsilon: 0.45 } }
    Behavior on visY { enabled: shotWin.springEnabled; SpringAnimation { spring: 10.8; damping: 0.37; epsilon: 0.45 } }
    Behavior on visW { enabled: shotWin.springEnabled; SpringAnimation { spring: 10.8; damping: 0.37; epsilon: 0.45 } }
    Behavior on visH { enabled: shotWin.springEnabled; SpringAnimation { spring: 10.8; damping: 0.37; epsilon: 0.45 } }

    // Annotation state
    // activeTool: "select" | "pen" | "highlighter" | "line" | "arrow" | "rect" | "ellipse" | "text" | "number" | "eraser" | "eyedrop"
    property string activeTool: "select"
    property string prevToolBeforeEyedrop: "pen"
    property string activeColor: "#22C55E"
    property int strokeWidth: 4
    property bool colorPickerOpen: false
    property var annotations: []
    property var redoStack: []
    property var currentStroke: null

    // Inline text annotation editor state
    property bool textEditing: false
    property real textEditX: 0
    property real textEditY: 0

    function nextMarkerNumber() {
        let maxN = 0;
        for (let i = 0; i < annotations.length; i++) {
            if (annotations[i].tool === "number") {
                maxN = Math.max(maxN, annotations[i].num || 0);
            }
        }
        return maxN + 1;
    }

    function commitTextAnnotation() {
        if (!textEditing) return;
        const txt = inlineTextInput.text.trim();
        if (txt.length > 0) {
            annotations = [...annotations, {
                tool: "text",
                x: textEditX,
                y: textEditY,
                text: txt,
                color: activeColor,
                size: strokeWidth <= 3 ? 18 : (strokeWidth <= 6 ? 26 : 36)
            }];
            redoStack = [];
            annoCanvas.requestPaint();
        }
        inlineTextInput.text = "";
        textEditing = false;
        rootItem.forceActiveFocus();
    }

    function contrastColor(hexStr) {
        const c = Qt.color(hexStr);
        const lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
        return lum > 0.6 ? "#111827" : "#FFFFFF";
    }

    Process {
        id: eyedropProc
        stdout: SplitParser {
            onRead: line => {
                const hex = line.trim();
                if (/^#[0-9a-fA-F]{6}$/.test(hex)) {
                    shotWin.activeColor = hex.toUpperCase();
                    shotWin.activeTool = shotWin.prevToolBeforeEyedrop;
                }
            }
        }
    }

    function pickColorAt(mx, my) {
        if (eyedropProc.running) eyedropProc.running = false;
        eyedropProc.command = [
            "python3", "-c",
            "import sys; from PIL import Image; " +
            "img = Image.open(sys.argv[1]).convert('RGB'); pw, ph = img.size; " +
            "x = max(0, min(pw - 1, int(round(float(sys.argv[2]) * pw / max(1.0, float(sys.argv[4])))))); " +
            "y = max(0, min(ph - 1, int(round(float(sys.argv[3]) * ph / max(1.0, float(sys.argv[5])))))); " +
            "r, g, b = img.getpixel((x, y)); print(f'#{r:02X}{g:02X}{b:02X}')",
            shotWin.tmpFile, String(mx), String(my), String(shotWin.width), String(shotWin.height)
        ];
        eyedropProc.running = true;
    }

    // Expressive wobbly spring-smoothed endpoint for shape tools (line, arrow, rect, ellipse)
    property bool shapeSpringEnabled: true
    property real shapeTargetX2: 0
    property real shapeTargetY2: 0
    property real visShapeX2: shapeTargetX2
    property real visShapeY2: shapeTargetY2

    Behavior on visShapeX2 { enabled: shotWin.shapeSpringEnabled; SpringAnimation { spring: 10.8; damping: 0.37; epsilon: 0.45 } }
    Behavior on visShapeY2 { enabled: shotWin.shapeSpringEnabled; SpringAnimation { spring: 10.8; damping: 0.37; epsilon: 0.45 } }

    onVisShapeX2Changed: if (currentStroke && !currentStroke.points) annoCanvas.requestPaint()
    onVisShapeY2Changed: if (currentStroke && !currentStroke.points) annoCanvas.requestPaint()

    readonly property var paletteColors: [
        "#EF4444", "#F59E0B", "#22C55E", "#38BDF8", "#A855F7", "#FFFFFF", "#111827"
    ]

    function undoAnnotation() {
        if (annotations.length === 0) return;
        const next = annotations.slice();
        const popped = next.pop();
        annotations = next;
        redoStack = [...redoStack, popped];
        annoCanvas.requestPaint();
    }

    function redoAnnotation() {
        if (redoStack.length === 0) return;
        const nextRedo = redoStack.slice();
        const restored = nextRedo.pop();
        redoStack = nextRedo;
        annotations = [...annotations, restored];
        annoCanvas.requestPaint();
    }

    function eraseAt(mx, my) {
        if (annotations.length === 0) return;
        const thresh = 16;
        let removed = null;
        const kept = [];
        for (let i = annotations.length - 1; i >= 0; i--) {
            const s = annotations[i];
            let hit = false;
            if (!removed) {
                if (s.points && s.points.length > 0) {
                    for (let j = 0; j < s.points.length; j++) {
                        const dx = s.points[j][0] - mx;
                        const dy = s.points[j][1] - my;
                        if (dx * dx + dy * dy <= thresh * thresh) { hit = true; break; }
                    }
                } else if (s.tool === "text" || s.tool === "number") {
                    const dx = s.x - mx;
                    const dy = s.y - my;
                    if (dx * dx + dy * dy <= (thresh + 10) * (thresh + 10)) hit = true;
                } else {
                    const minX = Math.min(s.x1, s.x2) - thresh;
                    const maxX = Math.max(s.x1, s.x2) + thresh;
                    const minY = Math.min(s.y1, s.y2) - thresh;
                    const maxY = Math.max(s.y1, s.y2) + thresh;
                    if (mx >= minX && mx <= maxX && my >= minY && my <= maxY) hit = true;
                }
            }
            if (hit && !removed) removed = s;
            else kept.unshift(s);
        }
        if (removed) {
            annotations = kept;
            redoStack = [...redoStack, removed];
            annoCanvas.requestPaint();
        }
    }

    visible: windowVisible

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
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property string tmpFile: "/tmp/expressive-shot-" + (modelData ? modelData.name : "0") + ".png"

    Process {
        id: freezeProc
        command: ["grim", "-o", shotWin.modelData ? shotWin.modelData.name : "", shotWin.tmpFile]
        onExited: code => {
            if (!shotWin.isOpen) return;
            if (code === 0) {
                shotWin.errorMsg = "";
                shotWin.freezePath = "";
                shotWin.freezePath = "file://" + shotWin.tmpFile + "?t=" + Date.now();
            } else {
                shotWin.errorMsg = "Install `grim` & `wl-clipboard` to capture screenshots";
            }
            shotWin.windowVisible = true;
            fadeIn.restart();
        }
    }

    onIsOpenChanged: {
        if (isOpen) {
            hasSelection = false;
            selX = 0; selY = 0; selW = 0; selH = 0;
            activeTool = "select";
            colorPickerOpen = false;
            textEditing = false;
            annotations = [];
            redoStack = [];
            currentStroke = null;
            errorMsg = "";
            rootItem.opacity = 0.0;
            if (freezeProc.running) freezeProc.running = false;
            freezeProc.running = true;
        } else {
            if (freezeProc.running) freezeProc.running = false;
            fadeOut.restart();
        }
    }

    function selectFullScreen() {
        selX = 0;
        selY = 0;
        selW = shotWin.width;
        selH = shotWin.height;
        hasSelection = true;
    }

    function capture(mode) {
        if (!hasSelection || selW < 4 || selH < 4) {
            selectFullScreen();
        }
        const script = Quickshell.shellPath("scripts/screenshot-crop.py");
        const annoJson = annotations.length > 0 ? JSON.stringify(annotations) : "";
        Quickshell.execDetached([
            "python3", script,
            shotWin.tmpFile,
            mode,
            String(Math.round(selX)),
            String(Math.round(selY)),
            String(Math.round(selW)),
            String(Math.round(selH)),
            String(Math.round(shotWin.width)),
            String(Math.round(shotWin.height)),
            ShellState.resolvedScreenshotsDir,
            annoJson
        ]);
        ShellState.closeOverlay();
    }

    NumberAnimation {
        id: fadeIn
        target: rootItem
        property: "opacity"
        from: 0.0
        to: 1.0
        duration: 140
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: fadeOut
        NumberAnimation {
            target: rootItem
            property: "opacity"
            to: 0.0
            duration: 120
            easing.type: Easing.OutQuad
        }
        ScriptAction {
            script: {
                if (!shotWin.isOpen) {
                    shotWin.windowVisible = false;
                    shotWin.freezePath = "";
                }
            }
        }
    }

    Item {
        id: rootItem
        anchors.fill: parent
        opacity: 0.0
        focus: shotWin.isOpen

        Keys.onEscapePressed: ShellState.closeOverlay()
        Keys.onReturnPressed: shotWin.capture("save")
        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
                shotWin.capture("copy");
                event.accepted = true;
            } else if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Z) {
                shotWin.redoAnnotation();
                event.accepted = true;
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Z) {
                shotWin.undoAnnotation();
                event.accepted = true;
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Y) {
                shotWin.redoAnnotation();
                event.accepted = true;
            }
        }

        // Frozen 1:1 screen capture background
        Image {
            anchors.fill: parent
            source: shotWin.freezePath
            asynchronous: false
            cache: false
            fillMode: Image.Stretch
            visible: shotWin.freezePath.length > 0
        }

        // Live Annotation Canvas (rendered over the frozen screenshot, under the selection scrim)
        Canvas {
            id: annoCanvas
            anchors.fill: parent

            function drawStroke(ctx, s) {
                if (!s) return;
                ctx.save();
                ctx.strokeStyle = s.color;
                ctx.fillStyle = s.color;
                ctx.lineWidth = s.width;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.globalAlpha = (s.tool === "highlighter") ? 0.42 : 1.0;

                if (s.tool === "pen" || s.tool === "highlighter") {
                    const pts = s.points || [];
                    if (pts.length === 1) {
                        ctx.beginPath();
                        ctx.arc(pts[0][0], pts[0][1], s.width / 2, 0, Math.PI * 2);
                        ctx.fill();
                    } else if (pts.length >= 2) {
                        ctx.beginPath();
                        ctx.moveTo(pts[0][0], pts[0][1]);
                        for (let i = 1; i < pts.length; i++) {
                            ctx.lineTo(pts[i][0], pts[i][1]);
                        }
                        ctx.stroke();
                    }
                } else if (s.tool === "line") {
                    ctx.beginPath();
                    ctx.moveTo(s.x1, s.y1);
                    ctx.lineTo(s.x2, s.y2);
                    ctx.stroke();
                } else if (s.tool === "arrow") {
                    const angle = Math.atan2(s.y2 - s.y1, s.x2 - s.x1);
                    const headLen = Math.max(14, s.width * 3.0);
                    ctx.beginPath();
                    ctx.moveTo(s.x1, s.y1);
                    ctx.lineTo(s.x2, s.y2);
                    ctx.stroke();

                    ctx.beginPath();
                    ctx.moveTo(s.x2 - headLen * Math.cos(angle - Math.PI / 5.2), s.y2 - headLen * Math.sin(angle - Math.PI / 5.2));
                    ctx.lineTo(s.x2, s.y2);
                    ctx.lineTo(s.x2 - headLen * Math.cos(angle + Math.PI / 5.2), s.y2 - headLen * Math.sin(angle + Math.PI / 5.2));
                    ctx.stroke();
                } else if (s.tool === "text") {
                    ctx.font = "bold " + (s.size || 24) + "px sans-serif";
                    ctx.textBaseline = "top";
                    ctx.fillText(s.text || "", s.x, s.y);
                } else if (s.tool === "number") {
                    const rad = s.radius || 14;
                    ctx.beginPath();
                    ctx.arc(s.x, s.y, rad, 0, Math.PI * 2);
                    ctx.fill();
                    ctx.fillStyle = shotWin.contrastColor(s.color);
                    ctx.font = "bold " + Math.round(rad * 1.15) + "px sans-serif";
                    ctx.textAlign = "center";
                    ctx.textBaseline = "middle";
                    ctx.fillText(String(s.num || 1), s.x, s.y + 0.5);
                } else if (s.tool === "rect") {
                    const rx = Math.min(s.x1, s.x2);
                    const ry = Math.min(s.y1, s.y2);
                    const rw = Math.abs(s.x2 - s.x1);
                    const rh = Math.abs(s.y2 - s.y1);
                    ctx.strokeRect(rx, ry, rw, rh);
                } else if (s.tool === "ellipse") {
                    const cx = (s.x1 + s.x2) / 2;
                    const cy = (s.y1 + s.y2) / 2;
                    const rx = Math.max(1, Math.abs(s.x2 - s.x1) / 2);
                    const ry = Math.max(1, Math.abs(s.y2 - s.y1) / 2);
                    ctx.beginPath();
                    ctx.ellipse(cx - rx, cy - ry, rx * 2, ry * 2);
                    ctx.stroke();
                }
                ctx.restore();
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                for (let i = 0; i < shotWin.annotations.length; i++) {
                    drawStroke(ctx, shotWin.annotations[i]);
                }
                if (shotWin.currentStroke) {
                    if (!shotWin.currentStroke.points) {
                        // Use wobbly spring-smoothed endpoint for live shape preview
                        drawStroke(ctx, {
                            tool: shotWin.currentStroke.tool,
                            color: shotWin.currentStroke.color,
                            width: shotWin.currentStroke.width,
                            x1: shotWin.currentStroke.x1,
                            y1: shotWin.currentStroke.y1,
                            x2: shotWin.visShapeX2,
                            y2: shotWin.visShapeY2
                        });
                    } else {
                        drawStroke(ctx, shotWin.currentStroke);
                    }
                }
            }
        }

        // 4-rectangle cutout scrim so the selected region stays 100% bright & crisp
        Rectangle {
            visible: !shotWin.hasSelection && shotWin.activeTool === "select"
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)
        }

        // Top scrim
        Rectangle {
            visible: shotWin.hasSelection
            x: 0; y: 0
            width: parent.width
            height: Math.max(0, shotWin.visY)
            color: Qt.rgba(0, 0, 0, 0.50)
        }
        // Bottom scrim
        Rectangle {
            visible: shotWin.hasSelection
            x: 0; y: Math.max(0, shotWin.visY) + Math.max(0, shotWin.visH)
            width: parent.width
            height: Math.max(0, parent.height - y)
            color: Qt.rgba(0, 0, 0, 0.50)
        }
        // Left scrim
        Rectangle {
            visible: shotWin.hasSelection
            x: 0; y: Math.max(0, shotWin.visY)
            width: Math.max(0, shotWin.visX)
            height: Math.max(0, shotWin.visH)
            color: Qt.rgba(0, 0, 0, 0.50)
        }
        // Right scrim
        Rectangle {
            visible: shotWin.hasSelection
            x: Math.max(0, shotWin.visX) + Math.max(0, shotWin.visW)
            y: Math.max(0, shotWin.visY)
            width: Math.max(0, parent.width - x)
            height: Math.max(0, shotWin.visH)
            color: Qt.rgba(0, 0, 0, 0.50)
        }

        // Unified Region-Select & Annotation Interaction Layer
        MouseArea {
            id: dragLayer
            anchors.fill: parent
            cursorShape: shotWin.activeTool === "select" ? Qt.CrossCursor : Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            property real startX: 0
            property real startY: 0
            property bool moving: false
            property real moveOffX: 0
            property real moveOffY: 0

            onPressed: mouse => {
                shotWin.colorPickerOpen = false;
                if (shotWin.textEditing) {
                    shotWin.commitTextAnnotation();
                    return;
                }
                if (mouse.button === Qt.RightButton) {
                    ShellState.closeOverlay();
                    return;
                }

                if (shotWin.activeTool === "eyedrop") {
                    shotWin.pickColorAt(mouse.x, mouse.y);
                } else if (shotWin.activeTool === "text") {
                    shotWin.textEditX = mouse.x;
                    shotWin.textEditY = mouse.y;
                    shotWin.textEditing = true;
                    inlineTextInput.text = "";
                    inlineTextInput.forceActiveFocus();
                } else if (shotWin.activeTool === "number") {
                    shotWin.annotations = [...shotWin.annotations, {
                        tool: "number",
                        x: mouse.x,
                        y: mouse.y,
                        num: shotWin.nextMarkerNumber(),
                        color: shotWin.activeColor,
                        radius: shotWin.strokeWidth <= 3 ? 12 : (shotWin.strokeWidth <= 6 ? 15 : 19)
                    }];
                    shotWin.redoStack = [];
                    annoCanvas.requestPaint();
                } else if (shotWin.activeTool === "select") {
                    if (shotWin.hasSelection
                        && mouse.x >= shotWin.selX && mouse.x <= shotWin.selX + shotWin.selW
                        && mouse.y >= shotWin.selY && mouse.y <= shotWin.selY + shotWin.selH) {
                        moving = true;
                        moveOffX = mouse.x - shotWin.selX;
                        moveOffY = mouse.y - shotWin.selY;
                    } else {
                        moving = false;
                        startX = mouse.x;
                        startY = mouse.y;
                        shotWin.springEnabled = false;
                        shotWin.selX = mouse.x;
                        shotWin.selY = mouse.y;
                        shotWin.selW = 0;
                        shotWin.selH = 0;
                        shotWin.hasSelection = true;
                        shotWin.springEnabled = true;
                    }
                } else if (shotWin.activeTool === "eraser") {
                    shotWin.eraseAt(mouse.x, mouse.y);
                } else if (shotWin.activeTool === "pen" || shotWin.activeTool === "highlighter") {
                    shotWin.currentStroke = {
                        tool: shotWin.activeTool,
                        color: shotWin.activeColor,
                        width: shotWin.activeTool === "highlighter" ? Math.max(14, shotWin.strokeWidth * 3) : shotWin.strokeWidth,
                        points: [[mouse.x, mouse.y]]
                    };
                    annoCanvas.requestPaint();
                } else {
                    shotWin.shapeSpringEnabled = false;
                    shotWin.shapeTargetX2 = mouse.x;
                    shotWin.shapeTargetY2 = mouse.y;
                    shotWin.shapeSpringEnabled = true;
                    shotWin.currentStroke = {
                        tool: shotWin.activeTool,
                        color: shotWin.activeColor,
                        width: shotWin.strokeWidth,
                        x1: mouse.x, y1: mouse.y,
                        x2: mouse.x, y2: mouse.y
                    };
                    annoCanvas.requestPaint();
                }
            }

            onPositionChanged: mouse => {
                if (!pressed) return;
                if (shotWin.activeTool === "select") {
                    if (moving) {
                        shotWin.selX = Math.max(0, Math.min(rootItem.width - shotWin.selW, mouse.x - moveOffX));
                        shotWin.selY = Math.max(0, Math.min(rootItem.height - shotWin.selH, mouse.y - moveOffY));
                    } else {
                        const cx = Math.max(0, Math.min(rootItem.width, mouse.x));
                        const cy = Math.max(0, Math.min(rootItem.height, mouse.y));
                        shotWin.selX = Math.min(startX, cx);
                        shotWin.selY = Math.min(startY, cy);
                        shotWin.selW = Math.abs(cx - startX);
                        shotWin.selH = Math.abs(cy - startY);
                    }
                } else if (shotWin.activeTool === "eraser") {
                    shotWin.eraseAt(mouse.x, mouse.y);
                } else if (shotWin.currentStroke) {
                    if (shotWin.currentStroke.points) {
                        shotWin.currentStroke.points.push([mouse.x, mouse.y]);
                        annoCanvas.requestPaint();
                    } else {
                        shotWin.currentStroke.x2 = mouse.x;
                        shotWin.currentStroke.y2 = mouse.y;
                        shotWin.shapeTargetX2 = mouse.x;
                        shotWin.shapeTargetY2 = mouse.y;
                    }
                }
            }

            onReleased: {
                if (shotWin.currentStroke) {
                    shotWin.annotations = [...shotWin.annotations, shotWin.currentStroke];
                    shotWin.redoStack = [];
                    shotWin.currentStroke = null;
                    annoCanvas.requestPaint();
                }
            }
        }

        // Crisp M3E Selection Border + Corner Accent Handles (wobbly spring-driven)
        Rectangle {
            visible: shotWin.hasSelection && shotWin.visW > 2 && shotWin.visH > 2
            x: shotWin.visX
            y: shotWin.visY
            width: Math.max(0, shotWin.visW)
            height: Math.max(0, shotWin.visH)
            color: "transparent"
            border.width: 2
            border.color: Theme.primary
            radius: 6

            Rectangle { x: -2; y: -2; width: 16; height: 4; radius: 2; color: "#FFFFFF" }
            Rectangle { x: -2; y: -2; width: 4; height: 16; radius: 2; color: "#FFFFFF" }
            Rectangle { x: parent.width - 14; y: -2; width: 16; height: 4; radius: 2; color: "#FFFFFF" }
            Rectangle { x: parent.width - 2; y: -2; width: 4; height: 16; radius: 2; color: "#FFFFFF" }
            Rectangle { x: -2; y: parent.height - 2; width: 16; height: 4; radius: 2; color: "#FFFFFF" }
            Rectangle { x: -2; y: parent.height - 14; width: 4; height: 16; radius: 2; color: "#FFFFFF" }
            Rectangle { x: parent.width - 14; y: parent.height - 2; width: 16; height: 4; radius: 2; color: "#FFFFFF" }
            Rectangle { x: parent.width - 2; y: parent.height - 14; width: 4; height: 16; radius: 2; color: "#FFFFFF" }
        }

        // Live dimensions badge (`W × H`) floating above the selection
        Rectangle {
            visible: shotWin.hasSelection && shotWin.visW > 12 && shotWin.visH > 12
            x: Math.max(10, Math.min(rootItem.width - width - 10, shotWin.visX))
            y: shotWin.visY > 82 ? (shotWin.visY - 32) : (shotWin.visY + 10)
            height: 24
            width: dimTxt.implicitWidth + 16
            radius: 12
            color: Theme.glassSurfaceHigh
            border.width: 1
            border.color: Theme.glassBorder

            Text {
                id: dimTxt
                anchors.centerIn: parent
                text: Math.round(shotWin.selW) + " × " + Math.round(shotWin.selH)
                color: Theme.fgSurface
                font.family: Theme.fontSans
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        // =====================================================================
        // TOP FLOATING M3E ANNOTATION TOOLBAR
        // =====================================================================
        Rectangle {
            id: annoBar
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 18
            height: 46
            width: annoRow.implicitWidth + 20
            radius: 23
            color: Theme.glassSurfaceHigh
            border.width: 1
            border.color: Theme.glassBorder

            MouseArea { anchors.fill: parent }

            RowLayout {
                id: annoRow
                anchors.centerIn: parent
                spacing: 4

                // Close
                Rectangle {
                    Layout.preferredWidth: 32; Layout.preferredHeight: 32; radius: 10
                    color: closeToolM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                    Text { anchors.centerIn: parent; text: "󰅖"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                    MouseArea { id: closeToolM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.closeOverlay() }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Theme.glassBorder; Layout.leftMargin: 2; Layout.rightMargin: 2 }

                // Undo / Redo
                Rectangle {
                    Layout.preferredWidth: 32; Layout.preferredHeight: 32; radius: 10
                    color: undoM.containsMouse && shotWin.annotations.length > 0 ? Theme.surfaceContainerHighest : "transparent"
                    opacity: shotWin.annotations.length > 0 ? 1.0 : 0.35
                    Text { anchors.centerIn: parent; text: "󰕌"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                    MouseArea { id: undoM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: shotWin.undoAnnotation() }
                }

                Rectangle {
                    Layout.preferredWidth: 32; Layout.preferredHeight: 32; radius: 10
                    color: redoM.containsMouse && shotWin.redoStack.length > 0 ? Theme.surfaceContainerHighest : "transparent"
                    opacity: shotWin.redoStack.length > 0 ? 1.0 : 0.35
                    Text { anchors.centerIn: parent; text: "󰑎"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                    MouseArea { id: redoM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: shotWin.redoAnnotation() }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Theme.glassBorder; Layout.leftMargin: 2; Layout.rightMargin: 2 }

                // Drawing tools
                Repeater {
                    model: [
                        { id: "select",      icon: "󰆾" },
                        { id: "pen",         icon: "󰏫" },
                        { id: "highlighter", icon: "󰸱" },
                        { id: "line",        icon: "󰕞" },
                        { id: "arrow",       icon: "󰁛" },
                        { id: "rect",        icon: "󰄱" },
                        { id: "ellipse",     icon: "󰝦" },
                        { id: "text",        icon: "󰗊" },
                        { id: "number",      icon: "󰎠" },
                        { id: "eraser",      icon: "󰇾" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: shotWin.activeTool === modelData.id
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: 11
                        color: active ? Theme.primary : (tM.containsMouse ? Theme.surfaceContainerHighest : "transparent")
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            color: active ? Theme.fgPrimary : Theme.fgSurface
                            font.family: Theme.fontMono
                            font.pixelSize: 16
                        }

                        MouseArea {
                            id: tM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shotWin.activeTool = modelData.id
                        }
                    }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Theme.glassBorder; Layout.leftMargin: 2; Layout.rightMargin: 2 }

                // Color swatch picker button
                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 9
                    color: shotWin.activeColor
                    border.width: 2
                    border.color: shotWin.colorPickerOpen ? Theme.primary : Theme.glassBorder

                    Rectangle {
                        anchors.centerIn: parent
                        width: shotWin.strokeWidth <= 3 ? 6 : (shotWin.strokeWidth <= 6 ? 9 : 12)
                        height: width
                        radius: width / 2
                        color: shotWin.activeColor === "#111827" ? "#FFFFFF" : "#111827"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shotWin.colorPickerOpen = !shotWin.colorPickerOpen
                    }
                }

                // Stroke size cycle (S / M / L)
                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 9
                    color: szM.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: shotWin.strokeWidth <= 3 ? "S" : (shotWin.strokeWidth <= 6 ? "M" : "L")
                        color: Theme.fgSurface
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: szM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shotWin.strokeWidth = shotWin.strokeWidth <= 3 ? 6 : (shotWin.strokeWidth <= 6 ? 10 : 3)
                    }
                }
            }
        }

        // Inline floating TextInput when placing text annotations
        Rectangle {
            visible: shotWin.textEditing
            x: Math.max(8, Math.min(rootItem.width - width - 8, shotWin.textEditX - 6))
            y: Math.max(8, Math.min(rootItem.height - height - 8, shotWin.textEditY - 4))
            width: Math.max(120, inlineTextInput.implicitWidth + 24)
            height: inlineTextInput.implicitHeight + 12
            radius: 10
            color: Qt.rgba(0, 0, 0, 0.55)
            border.width: 1.5
            border.color: shotWin.activeColor

            TextInput {
                id: inlineTextInput
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                color: shotWin.activeColor
                font.family: Theme.fontSans
                font.pixelSize: shotWin.strokeWidth <= 3 ? 18 : (shotWin.strokeWidth <= 6 ? 26 : 36)
                font.weight: Font.Bold
                onAccepted: shotWin.commitTextAnnotation()
                Keys.onEscapePressed: {
                    text = "";
                    shotWin.textEditing = false;
                    rootItem.forceActiveFocus();
                }
            }
        }

        // Floating Color Palette + Custom Hue Picker + Eyedropper Popover
        Rectangle {
            visible: shotWin.colorPickerOpen
            anchors.top: annoBar.bottom
            anchors.horizontalCenter: annoBar.horizontalCenter
            anchors.topMargin: 8
            height: palCol.implicitHeight + 20
            width: Math.max(264, palCol.implicitWidth + 24)
            radius: 18
            color: Theme.glassSurfaceHigh
            border.width: 1
            border.color: Theme.glassBorder

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: palCol
                anchors.centerIn: parent
                spacing: 10

                // Row 1: Preset swatches + Eyedropper button
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: shotWin.paletteColors
                        delegate: Rectangle {
                            required property string modelData
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            radius: 11
                            color: modelData
                            border.width: shotWin.activeColor.toUpperCase() === modelData.toUpperCase() ? 2.5 : 1
                            border.color: shotWin.activeColor.toUpperCase() === modelData.toUpperCase() ? Theme.primary : Theme.glassBorder
                            scale: cM.containsMouse ? 1.15 : 1.0
                            Behavior on scale { SpringAnimation { spring: Motion.spatialSpring; damping: Motion.spatialDamping } }

                            MouseArea {
                                id: cM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    shotWin.activeColor = modelData;
                                    shotWin.colorPickerOpen = false;
                                }
                            }
                        }
                    }

                    // Eyedropper button
                    Rectangle {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        radius: 8
                        color: shotWin.activeTool === "eyedrop" ? Theme.primary : (eyeM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                        Text {
                            anchors.centerIn: parent
                            text: "󰈊"
                            color: shotWin.activeTool === "eyedrop" ? Theme.fgPrimary : Theme.fgSurface
                            font.family: Theme.fontMono
                            font.pixelSize: 14
                        }
                        MouseArea {
                            id: eyeM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (shotWin.activeTool !== "eyedrop") {
                                    shotWin.prevToolBeforeEyedrop = shotWin.activeTool === "select" ? "pen" : shotWin.activeTool;
                                }
                                shotWin.activeTool = "eyedrop";
                                shotWin.colorPickerOpen = false;
                            }
                        }
                    }
                }

                // Row 2: Rainbow Hue Bar (click/drag for any custom color)
                Rectangle {
                    id: hueBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 16
                    radius: 8
                    border.width: 1
                    border.color: Theme.glassBorder
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.00; color: "#FF0000" }
                        GradientStop { position: 0.17; color: "#FFFF00" }
                        GradientStop { position: 0.33; color: "#00FF00" }
                        GradientStop { position: 0.50; color: "#00FFFF" }
                        GradientStop { position: 0.67; color: "#0000FF" }
                        GradientStop { position: 0.83; color: "#FF00FF" }
                        GradientStop { position: 1.00; color: "#FF0000" }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function pickHue(mx) {
                            const h = Math.max(0.0, Math.min(1.0, mx / Math.max(1, hueBar.width)));
                            const c = Qt.hsla(h, 0.92, 0.55, 1.0);
                            const toHex = v => Math.round(v * 255).toString(16).padStart(2, "0").toUpperCase();
                            shotWin.activeColor = "#" + toHex(c.r) + toHex(c.g) + toHex(c.b);
                        }
                        onPressed: mouse => pickHue(mouse.x)
                        onPositionChanged: mouse => { if (pressed) pickHue(mouse.x); }
                    }
                }

                // Row 3: Custom Hex input
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        radius: 6
                        color: shotWin.activeColor
                        border.width: 1
                        border.color: Theme.glassBorder
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        radius: 8
                        color: Theme.surfaceContainerHigh
                        border.width: 1
                        border.color: hexInput.activeFocus ? Theme.primary : Theme.glassBorder

                        TextInput {
                            id: hexInput
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            text: shotWin.activeColor
                            color: Theme.fgSurface
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            onEditingFinished: {
                                const v = text.trim();
                                if (/^#[0-9a-fA-F]{6}$/.test(v)) {
                                    shotWin.activeColor = v.toUpperCase();
                                }
                            }
                            onAccepted: {
                                const v = text.trim();
                                if (/^#[0-9a-fA-F]{6}$/.test(v)) {
                                    shotWin.activeColor = v.toUpperCase();
                                    shotWin.colorPickerOpen = false;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Error pill (only shown if grim failed)
        Rectangle {
            visible: shotWin.errorMsg.length > 0
            anchors.top: annoBar.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 10
            height: 32
            width: errTxt.implicitWidth + 24
            radius: 16
            color: Theme.alpha(Theme.error, 0.22)
            border.width: 1
            border.color: Theme.error

            Text {
                id: errTxt
                anchors.centerIn: parent
                text: shotWin.errorMsg
                color: Theme.error
                font.family: Theme.fontSans
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        // Floating Expressive Shell / M3E Bottom Action Toolbar
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 28
            height: 52
            width: barRow.implicitWidth + 18
            radius: 26
            color: Theme.glassSurfaceHigh
            border.width: 1
            border.color: Theme.glassBorder

            MouseArea { anchors.fill: parent }

            RowLayout {
                id: barRow
                anchors.centerIn: parent
                spacing: 8

                // Full screen button
                Rectangle {
                    Layout.preferredHeight: 36
                    Layout.preferredWidth: fullRow.implicitWidth + 22
                    radius: 18
                    color: fullM.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    Row {
                        id: fullRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "󰊓"; color: Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                        Text { text: "Full screen"; color: Theme.fgSurface; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.Medium }
                    }
                    MouseArea {
                        id: fullM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shotWin.selectFullScreen()
                    }
                }

                // Copy button
                Rectangle {
                    Layout.preferredHeight: 36
                    Layout.preferredWidth: copyRow.implicitWidth + 22
                    radius: 18
                    color: copyM.containsMouse ? Theme.primaryContainer : Theme.surfaceContainerHigh
                    Row {
                        id: copyRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "󰆏"; color: copyM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurface; font.family: Theme.fontMono; font.pixelSize: 15 }
                        Text { text: "Copy"; color: copyM.containsMouse ? Theme.fgPrimaryContainer : Theme.fgSurface; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                    MouseArea {
                        id: copyM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shotWin.capture("copy")
                    }
                }

                // Save button (primary M3E action)
                Rectangle {
                    Layout.preferredHeight: 36
                    Layout.preferredWidth: saveRow.implicitWidth + 22
                    radius: 18
                    color: Theme.primary
                    Row {
                        id: saveRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "󰆓"; color: Theme.fgPrimary; font.family: Theme.fontMono; font.pixelSize: 15 }
                        Text { text: "Save"; color: Theme.fgPrimary; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shotWin.capture("save")
                    }
                }

                // Cancel button
                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 18
                    color: cancelM.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                    Text { anchors.centerIn: parent; text: "󰅖"; color: Theme.fgSurfaceVariant; font.family: Theme.fontMono; font.pixelSize: 16 }
                    MouseArea {
                        id: cancelM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.closeOverlay()
                    }
                }
            }
        }
    }
}
