pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string homeDir: Quickshell.env("HOME") || "/home/angel"
    readonly property string configDir: homeDir + "/.config/expressive-shell"
    readonly property string statePath: configDir + "/settings.json"

    // Persisted shell settings
    property bool darkMode: true
    property bool use24HourClock: false
    property int batteryWarnThreshold: 20
    property int batteryCriticalThreshold: 10
    property string dockMode: "always"            // "always" | "popup" | "off"
    property bool desktopWidgetsVisible: true
    property bool polkitEnabled: true
    property bool idleEnabled: true
    property int idleLockSec: 300
    property int idleSleepSec: 900
    property bool hasSwayidle: false
    property bool hasGoaCalendar: false
    property bool hasGrim: false
    property bool hasAwww: false
    property bool dnd: false
    property bool useAwww: false
    property bool autoRotate: false
    property int rotateIntervalSec: 300
    property string rotateOrder: "random"         // "random" | "alphabetical"
    property string matugenScheme: "scheme-tonal-spot"
    property string currentWallpaper: ""

    // User-configurable paths (supports leading `~`)
    property string screenshotsDir: "~/Pictures/Screenshots"
    property string wallpapersDir: "~/Pictures/Wallpapers"
    property string userAvatarPath: "~/.face"

    readonly property string resolvedScreenshotsDir: expandPath(screenshotsDir || "~/Pictures/Screenshots")
    readonly property string resolvedWallpapersDir: expandPath(wallpapersDir || "~/Pictures/Wallpapers")
    readonly property string resolvedUserAvatarPath: expandPath(userAvatarPath || "~/.face")

    // Pinned app IDs for the Expressive-style bottom taskbar
    property var pinnedApps: [
        "helium",
        "com.mitchellh.ghostty",
        "dev.zed.Zed",
        "md.obsidian.Obsidian",
        "spotify",
        "com.discord.libdiscord"
    ]

    // Enabled Noctalia-compatible app template names (opt-in, all disabled by default)
    property var enabledTemplates: []
    property var availableTemplates: []
    property bool syncingTemplates: false
    property bool _autoSyncedTemplates: false

    // Hidden system tray app IDs (persisted in settings.json)
    property var hiddenTrayIds: []

    // Configurable Control Center tiles & TopBar right-side icon bar (persisted)
    readonly property var allQsTileIds: ["wifi", "bluetooth", "mic", "theme", "dnd", "ppd", "screenshot", "widgets", "dock"]
    property var qsTiles: ["wifi", "bluetooth", "mic", "theme", "dnd", "ppd", "screenshot"]

    readonly property var allTopBarItemIds: ["media", "tray", "keyboard", "notifications", "status"]
    property var topBarItems: ["media", "tray", "keyboard", "notifications", "status"]

    // Transient runtime state (not persisted)
    property bool locked: false
    property string activeOverlay: ""
    property string previousOverlay: ""
    property real currentCardW: 0
    property real currentCardH: 0
    property real currentCardRight: 12
    property real morphFromW: 0
    property real morphFromH: 0
    property real morphFromRight: 12
    property string qsInitialPage: ""

    function reportOverlayGeometry(name, w, h, rightMargin) {
        if (activeOverlay === name && w > 40 && h > 40) {
            currentCardW = w;
            currentCardH = h;
            currentCardRight = rightMargin;
        }
    }

    function overlaysShareRegion(a, b) {
        if (!a || !b || a === b) return false;
        const topRight = ["quicksettings", "notifications", "media", "keyboard"];
        const bottomCenter = ["launcher", "wallpapers"];
        return (topRight.indexOf(a) !== -1 && topRight.indexOf(b) !== -1)
            || (bottomCenter.indexOf(a) !== -1 && bottomCenter.indexOf(b) !== -1);
    }

    function overlaySlideDir(fromName, toName) {
        const groups = [
            ["media", "keyboard", "notifications", "quicksettings"],
            ["launcher", "wallpapers"]
        ];
        for (let i = 0; i < groups.length; i++) {
            const a = groups[i].indexOf(fromName);
            const b = groups[i].indexOf(toName);
            if (a !== -1 && b !== -1 && a !== b) return b > a ? 1 : -1;
        }
        return 1;
    }

    // Shared M3E right-click System Tray context menu
    property bool trayMenuOpen: false
    property var trayMenuItem: null
    property string trayMenuId: ""
    property real trayMenuX: 0

    function openTrayMenu(item, itemId, x) {
        trayMenuItem = item;
        trayMenuId = String(itemId || "");
        trayMenuX = x;
        trayMenuOpen = Boolean(item);
    }

    function closeTrayMenu() {
        trayMenuOpen = false;
    }

    function isQsTileEnabled(tileId) {
        return qsTiles.indexOf(tileId) !== -1;
    }

    function toggleQsTile(tileId) {
        if (isQsTileEnabled(tileId)) {
            qsTiles = qsTiles.filter(id => id !== tileId);
        } else {
            qsTiles = [...qsTiles, tileId];
        }
    }

    function moveQsTile(tileId, dir) {
        const idx = qsTiles.indexOf(tileId);
        if (idx === -1) return;
        const target = idx + dir;
        if (target < 0 || target >= qsTiles.length) return;
        const copy = qsTiles.slice();
        const tmp = copy[idx];
        copy[idx] = copy[target];
        copy[target] = tmp;
        qsTiles = copy;
    }

    function isTopBarItemEnabled(itemId) {
        return topBarItems.indexOf(itemId) !== -1;
    }

    function toggleTopBarItem(itemId) {
        if (isTopBarItemEnabled(itemId)) {
            topBarItems = topBarItems.filter(id => id !== itemId);
        } else {
            topBarItems = [...topBarItems, itemId];
        }
    }

    function moveTopBarItem(itemId, dir) {
        const idx = topBarItems.indexOf(itemId);
        if (idx === -1) return;
        const target = idx + dir;
        if (target < 0 || target >= topBarItems.length) return;
        const copy = topBarItems.slice();
        const tmp = copy[idx];
        copy[idx] = copy[target];
        copy[target] = tmp;
        topBarItems = copy;
    }

    // Shared right-click app context menu (used by BottomDock & LauncherPopup)
    property bool appMenuOpen: false
    property string appMenuId: ""
    property string appMenuName: ""
    property real appMenuX: 0
    property real appMenuY: 0
    property bool appMenuFromBottom: false

    function openAppMenu(appId, appName, x, y, fromBottom) {
        appMenuId = String(appId || "");
        appMenuName = String(appName || appId || "App");
        appMenuX = x;
        appMenuY = y;
        appMenuFromBottom = Boolean(fromBottom);
        appMenuOpen = appMenuId.length > 0;
    }

    function closeAppMenu() {
        appMenuOpen = false;
    }

    function isAppPinned(appId) {
        const key = String(appId || "").toLowerCase();
        if (!key) return false;
        return pinnedApps.some(p => String(p).toLowerCase() === key);
    }

    function togglePinApp(appId) {
        const raw = String(appId || "").trim();
        if (!raw) return;
        const key = raw.toLowerCase();
        if (isAppPinned(raw)) {
            pinnedApps = pinnedApps.filter(p => String(p).toLowerCase() !== key);
        } else {
            pinnedApps = [...pinnedApps, raw];
        }
    }

    function isTemplateEnabled(name) {
        return enabledTemplates.some(t => String(t) === String(name));
    }

    function isTrayHidden(trayId) {
        const key = String(trayId || "").toLowerCase();
        if (!key) return false;
        return hiddenTrayIds.some(t => String(t).toLowerCase() === key);
    }

    function toggleHideTray(trayId) {
        const raw = String(trayId || "").trim();
        if (!raw) return;
        const key = raw.toLowerCase();
        if (isTrayHidden(raw)) {
            hiddenTrayIds = hiddenTrayIds.filter(t => String(t).toLowerCase() !== key);
        } else {
            hiddenTrayIds = [...hiddenTrayIds, raw];
        }
    }

    function toggleTemplate(name) {
        const s = String(name || "").trim();
        if (!s) return;
        if (isTemplateEnabled(s)) {
            enabledTemplates = enabledTemplates.filter(t => String(t) !== s);
            Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/apply-theme.py"), "--undo", s]);
        } else {
            enabledTemplates = [...enabledTemplates, s];
        }
    }

    Process {
        id: listTemplatesProc
        command: [
            "python3", "-c",
            "import json, tomllib\n" +
            "from pathlib import Path\n" +
            "roots = [\n" +
            "    ('state', Path.home() / '.local' / 'state' / 'expressive-shell' / 'templates'),\n" +
            "    ('user', Path.home() / '.config' / 'expressive-shell' / 'templates'),\n" +
            "]\n" +
            "valid = {'builtin.toml', 'templates.toml', 'template.toml'}\n" +
            "out = []\n" +
            "seen = set()\n" +
            "for tag, d in roots:\n" +
            "    if not d.is_dir(): continue\n" +
            "    for m in sorted(d.rglob('*.toml')):\n" +
            "        if m.name not in valid: continue\n" +
            "        try:\n" +
            "            rel = m.relative_to(d)\n" +
            "            if len(rel.parts) > 3: continue\n" +
            "            doc = tomllib.loads(m.read_text(encoding='utf-8'))\n" +
            "        except Exception: continue\n" +
            "        src = rel.parts[0] if len(rel.parts) > 1 else tag\n" +
            "        cat = doc.get('catalog') if isinstance(doc.get('catalog'), dict) else {}\n" +
            "        if cat:\n" +
            "            for cid, meta in cat.items():\n" +
            "                if not isinstance(meta, dict) or cid in seen: continue\n" +
            "                seen.add(cid)\n" +
            "                doc_url = str(meta.get('documentation_url') or '')\n" +
            "                if not doc_url and src == 'community-templates' and len(rel.parts) >= 2:\n" +
            "                    doc_url = 'https://github.com/noctalia-dev/community-templates/tree/main/' + rel.parts[1]\n" +
            "                out.append({\n" +
            "                    'id': cid,\n" +
            "                    'name': str(meta.get('name') or cid),\n" +
            "                    'category': str(meta.get('category') or src),\n" +
            "                    'docUrl': doc_url\n" +
            "                })\n" +
            "        else:\n" +
            "            for k, v in (doc.get('templates') or {}).items():\n" +
            "                if isinstance(v, dict) and k not in seen:\n" +
            "                    seen.add(k)\n" +
            "                    out.append({'id': k, 'name': k, 'category': src, 'docUrl': ''})\n" +
            "out.sort(key=lambda x: x['name'].lower())\n" +
            "print(json.dumps(out))"
        ]
        stdout: SplitParser {
            onRead: line => {
                if (!line || !line.trim()) return;
                try {
                    const arr = JSON.parse(line);
                    if (Array.isArray(arr)) {
                        root.availableTemplates = arr;
                        if (arr.length === 0 && !root._autoSyncedTemplates) {
                            root._autoSyncedTemplates = true;
                            root.syncTemplates();
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: syncTemplatesProc
        command: ["python3", Quickshell.shellPath("scripts/sync-templates.py")]
        onExited: {
            root.syncingTemplates = false;
            root.refreshTemplates();
        }
    }

    function syncTemplates() {
        if (syncTemplatesProc.running) return;
        syncingTemplates = true;
        syncTemplatesProc.running = true;
    }

    function refreshTemplates() {
        if (!listTemplatesProc.running) listTemplatesProc.running = true;
    }

    function applyTemplatesNow() {
        writeStateNow();
        if (!currentWallpaper) return;
        const script = Quickshell.shellPath("scripts/apply-theme.py");
        Quickshell.execDetached(["python3", script, currentWallpaper, darkMode ? "dark" : "light"]);
    }

    property bool _loaded: false
    property bool _applyingFile: false
    readonly property bool ready: _loaded

    function expandPath(p) {
        const s = String(p || "").trim();
        if (s === "~") return homeDir;
        if (s.startsWith("~/")) return homeDir + s.slice(1);
        return s;
    }

    function compactPath(p) {
        const s = String(p || "").trim();
        if (s === homeDir) return "~";
        if (s.startsWith(homeDir + "/")) return "~" + s.slice(homeDir.length);
        return s;
    }

    // Native file/folder picker via zenity (lives on ShellState so closing the shade never cancels it)
    property string _pickerTarget: ""
    Process {
        id: pathPickerProc
        stdout: SplitParser {
            onRead: line => {
                const chosen = root.compactPath(line.trim());
                if (!chosen) return;
                if (root._pickerTarget === "avatar") root.userAvatarPath = chosen;
                else if (root._pickerTarget === "screenshots") root.screenshotsDir = chosen;
                else if (root._pickerTarget === "wallpapers") root.wallpapersDir = chosen;
            }
        }
        onExited: root._pickerTarget = ""
    }

    function pickAvatarFile() {
        if (pathPickerProc.running) return;
        _pickerTarget = "avatar";
        pathPickerProc.command = [
            "zenity", "--file-selection",
            "--title=Select profile picture",
            "--filename=" + resolvedUserAvatarPath,
            "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.gif *.bmp"
        ];
        pathPickerProc.running = true;
    }

    function pickScreenshotsFolder() {
        if (pathPickerProc.running) return;
        _pickerTarget = "screenshots";
        pathPickerProc.command = [
            "zenity", "--file-selection", "--directory",
            "--title=Select screenshots folder",
            "--filename=" + resolvedScreenshotsDir + "/"
        ];
        pathPickerProc.running = true;
    }

    function pickWallpapersFolder() {
        if (pathPickerProc.running) return;
        _pickerTarget = "wallpapers";
        pathPickerProc.command = [
            "zenity", "--file-selection", "--directory",
            "--title=Select wallpapers folder",
            "--filename=" + resolvedWallpapersDir + "/"
        ];
        pathPickerProc.running = true;
    }

    // Load & hot-reload state.json
    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const raw = text();
            if (raw && raw.trim().length > 0) {
                try {
                    const data = JSON.parse(raw);
                    root._applyingFile = true;
                    if (typeof data.darkMode === "boolean") root.darkMode = data.darkMode;
                    if (typeof data.use24HourClock === "boolean") root.use24HourClock = data.use24HourClock;
                    if (typeof data.batteryWarnThreshold === "number" && data.batteryWarnThreshold >= 5 && data.batteryWarnThreshold <= 50) {
                        root.batteryWarnThreshold = Math.round(data.batteryWarnThreshold);
                    }
                    if (typeof data.batteryCriticalThreshold === "number" && data.batteryCriticalThreshold >= 2 && data.batteryCriticalThreshold <= 30) {
                        root.batteryCriticalThreshold = Math.round(data.batteryCriticalThreshold);
                    }
                    if (data.dockMode === "always" || data.dockMode === "popup" || data.dockMode === "off") {
                        root.dockMode = data.dockMode;
                    }
                    if (typeof data.desktopWidgetsVisible === "boolean") root.desktopWidgetsVisible = data.desktopWidgetsVisible;
                    if (typeof data.polkitEnabled === "boolean") root.polkitEnabled = data.polkitEnabled;
                    if (typeof data.idleEnabled === "boolean") root.idleEnabled = data.idleEnabled;
                    if (typeof data.idleLockSec === "number" && data.idleLockSec >= 0) root.idleLockSec = Math.round(data.idleLockSec);
                    if (typeof data.idleSleepSec === "number" && data.idleSleepSec >= 0) root.idleSleepSec = Math.round(data.idleSleepSec);
                    if (typeof data.dnd === "boolean") root.dnd = data.dnd;
                    if (typeof data.useAwww === "boolean") root.useAwww = data.useAwww;
                    if (typeof data.autoRotate === "boolean") root.autoRotate = data.autoRotate;
                    if (typeof data.rotateIntervalSec === "number" && data.rotateIntervalSec >= 30) {
                        root.rotateIntervalSec = Math.round(data.rotateIntervalSec);
                    }
                    if (data.rotateOrder === "random" || data.rotateOrder === "alphabetical") {
                        root.rotateOrder = data.rotateOrder;
                    }
                    if (typeof data.matugenScheme === "string" && data.matugenScheme.startsWith("scheme-")) {
                        root.matugenScheme = data.matugenScheme;
                    }
                    if (typeof data.currentWallpaper === "string") root.currentWallpaper = data.currentWallpaper;
                    if (typeof data.screenshotsDir === "string" && data.screenshotsDir.trim().length > 0) {
                        root.screenshotsDir = data.screenshotsDir.trim();
                    }
                    if (typeof data.wallpapersDir === "string" && data.wallpapersDir.trim().length > 0) {
                        root.wallpapersDir = data.wallpapersDir.trim();
                    }
                    if (typeof data.userAvatarPath === "string" && data.userAvatarPath.trim().length > 0) {
                        root.userAvatarPath = data.userAvatarPath.trim();
                    }
                    if (Array.isArray(data.pinnedApps) && data.pinnedApps.length > 0) {
                        root.pinnedApps = data.pinnedApps;
                    }
                    if (Array.isArray(data.enabledTemplates)) {
                        root.enabledTemplates = data.enabledTemplates;
                    }
                    if (Array.isArray(data.hiddenTrayIds)) {
                        root.hiddenTrayIds = data.hiddenTrayIds;
                    }
                    if (Array.isArray(data.qsTiles)) {
                        root.qsTiles = data.qsTiles.filter(id => root.allQsTileIds.indexOf(id) !== -1);
                    }
                    if (Array.isArray(data.topBarItems)) {
                        root.topBarItems = data.topBarItems.filter(id => root.allTopBarItemIds.indexOf(id) !== -1);
                    }
                    root._applyingFile = false;
                } catch (e) {
                    root._applyingFile = false;
                    console.warn("ShellState: failed to parse state.json:", e);
                }
            }
            root._loaded = true;
        }
        onLoadFailed: {
            // First run: create state.json with defaults
            root._loaded = true;
            saveTimer.restart();
        }
    }

    Timer {
        id: saveTimer
        interval: 220
        onTriggered: root.writeStateNow()
    }

    function scheduleSave() {
        if (!_loaded || _applyingFile) return;
        saveTimer.restart();
    }

    function writeStateNow() {
        const payload = JSON.stringify({
            darkMode: root.darkMode,
            use24HourClock: root.use24HourClock,
            batteryWarnThreshold: root.batteryWarnThreshold,
            batteryCriticalThreshold: root.batteryCriticalThreshold,
            dockMode: root.dockMode,
            desktopWidgetsVisible: root.desktopWidgetsVisible,
            polkitEnabled: root.polkitEnabled,
            idleEnabled: root.idleEnabled,
            idleLockSec: root.idleLockSec,
            idleSleepSec: root.idleSleepSec,
            dnd: root.dnd,
            useAwww: root.useAwww,
            autoRotate: root.autoRotate,
            rotateIntervalSec: root.rotateIntervalSec,
            rotateOrder: root.rotateOrder,
            matugenScheme: root.matugenScheme,
            currentWallpaper: root.currentWallpaper,
            screenshotsDir: root.screenshotsDir,
            wallpapersDir: root.wallpapersDir,
            userAvatarPath: root.userAvatarPath,
            pinnedApps: root.pinnedApps,
            enabledTemplates: root.enabledTemplates,
            hiddenTrayIds: root.hiddenTrayIds,
            qsTiles: root.qsTiles,
            topBarItems: root.topBarItems
        }, null, 2) + "\n";

        Quickshell.execDetached([
            "python3", "-c",
            "import os, sys; p = sys.argv[1]; os.makedirs(os.path.dirname(p), exist_ok=True); tmp = p + '.tmp'; open(tmp, 'w').write(sys.argv[2]); os.replace(tmp, p)",
            root.statePath,
            payload
        ]);
    }

    onDarkModeChanged: scheduleSave()
    onUse24HourClockChanged: scheduleSave()
    onBatteryWarnThresholdChanged: scheduleSave()
    onBatteryCriticalThresholdChanged: scheduleSave()
    onDockModeChanged: scheduleSave()
    Process {
        id: depCheckProc
        command: [
            "sh", "-c",
            "printf '%s|%s|%s|%s\\n' " +
            "\"$(command -v swayidle >/dev/null 2>&1 && echo 1 || echo 0)\" " +
            "\"$([ -x /usr/lib/goa-daemon ] && (command -v gnome-online-accounts-gtk >/dev/null 2>&1 || command -v gnome-control-center >/dev/null 2>&1) && echo 1 || echo 0)\" " +
            "\"$(command -v grim >/dev/null 2>&1 && echo 1 || echo 0)\" " +
            "\"$(command -v awww >/dev/null 2>&1 && echo 1 || echo 0)\""
        ]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split("|");
                if (parts.length >= 4) {
                    root.hasSwayidle = parts[0] === "1";
                    root.hasGoaCalendar = parts[1] === "1";
                    root.hasGrim = parts[2] === "1";
                    root.hasAwww = parts[3] === "1";
                }
            }
        }
    }

    function refreshDeps() {
        if (!depCheckProc.running) depCheckProc.running = true;
    }

    Timer {
        interval: 20000
        running: true
        repeat: true
        onTriggered: root.refreshDeps()
    }

    function syncIdleDaemon() {
        if (!_loaded || _applyingFile) return;
        Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/idle-manager.py")]);
    }

    onDesktopWidgetsVisibleChanged: scheduleSave()
    onPolkitEnabledChanged: scheduleSave()
    onIdleEnabledChanged: { scheduleSave(); idleSyncTimer.restart(); }
    onIdleLockSecChanged: { scheduleSave(); idleSyncTimer.restart(); }
    onIdleSleepSecChanged: { scheduleSave(); idleSyncTimer.restart(); }

    Timer {
        id: idleSyncTimer
        interval: 350
        onTriggered: root.syncIdleDaemon()
    }
    onDndChanged: scheduleSave()
    onUseAwwwChanged: scheduleSave()
    onAutoRotateChanged: scheduleSave()
    onRotateIntervalSecChanged: scheduleSave()
    onRotateOrderChanged: scheduleSave()
    onMatugenSchemeChanged: {
        scheduleSave();
        if (_loaded && !_applyingFile && currentWallpaper) {
            applyTemplatesNow();
        }
    }
    onCurrentWallpaperChanged: scheduleSave()
    onScreenshotsDirChanged: scheduleSave()
    onWallpapersDirChanged: scheduleSave()
    onUserAvatarPathChanged: scheduleSave()
    onPinnedAppsChanged: scheduleSave()
    onEnabledTemplatesChanged: scheduleSave()
    onHiddenTrayIdsChanged: scheduleSave()
    onQsTilesChanged: scheduleSave()
    onTopBarItemsChanged: scheduleSave()

    function toggleOverlay(name) {
        qsInitialPage = "";
        morphFromW = currentCardW;
        morphFromH = currentCardH;
        morphFromRight = currentCardRight;
        previousOverlay = activeOverlay;
        activeOverlay = (activeOverlay === name) ? "" : name;
        if (activeOverlay === "quicksettings" || activeOverlay === "wallpapers") {
            refreshDeps();
        }
    }

    function openQuickSettingsPage(page) {
        qsInitialPage = page || "";
        morphFromW = currentCardW;
        morphFromH = currentCardH;
        morphFromRight = currentCardRight;
        previousOverlay = activeOverlay;
        activeOverlay = "quicksettings";
    }

    function closeOverlay() {
        previousOverlay = activeOverlay;
        activeOverlay = "";
    }

    function lock() {
        activeOverlay = "";
        locked = true;
    }

    function cycleDockMode() {
        if (dockMode === "always") dockMode = "popup";
        else if (dockMode === "popup") dockMode = "off";
        else dockMode = "always";
    }
}
