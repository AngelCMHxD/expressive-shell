pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var workspaces: []
    property var windows: []
    property bool overviewOpen: false
    property var keyboardLayouts: []
    property int currentKeyboardLayoutIndex: 0

    readonly property bool hasMultipleKeyboardLayouts: keyboardLayouts.length > 1
    readonly property string currentKeyboardLayoutName: (keyboardLayouts.length > 0 && currentKeyboardLayoutIndex >= 0 && currentKeyboardLayoutIndex < keyboardLayouts.length)
        ? String(keyboardLayouts[currentKeyboardLayoutIndex])
        : ""
    readonly property string currentKeyboardLayoutCode: layoutShortCode(currentKeyboardLayoutName)

    // Live subscription to Umbriel JSON-line events
    Process {
        id: subProc
        command: ["umbriel", "subscribe", "workspaces,windows,overview,keyboard_layout"]
        running: true

        stdout: SplitParser {
            onRead: line => {
                if (!line || !line.trim()) return;
                try {
                    const msg = JSON.parse(line);
                    if (msg.event === "workspaces" && Array.isArray(msg.data)) {
                        root.workspaces = msg.data;
                    } else if (msg.event === "windows" && Array.isArray(msg.data)) {
                        root.windows = msg.data;
                    } else if (msg.event === "overview") {
                        root.overviewOpen = Boolean(msg.data && msg.data.open);
                    } else if (msg.event === "keyboard_layout" && msg.data) {
                        if (Array.isArray(msg.data.names)) {
                            root.keyboardLayouts = msg.data.names;
                        }
                        if (typeof msg.data.current_index === "number") {
                            root.currentKeyboardLayoutIndex = msg.data.current_index;
                        }
                    }
                } catch (e) {
                    console.warn("Umbriel: JSON parse error:", e);
                }
            }
        }

        onExited: (code, status) => {
            reconnectTimer.restart();
        }
    }

    Timer {
        id: reconnectTimer
        interval: 1500
        onTriggered: subProc.running = true
    }

    // Helpers
    function msg(args) {
        Quickshell.execDetached(["umbriel", "msg", ...args]);
    }

    function switchWorkspace(indexOrName) {
        msg(["workspace-switch", String(indexOrName)]);
    }

    function nextWorkspace() {
        msg(["workspace-next"]);
    }

    function previousWorkspace() {
        msg(["workspace-previous"]);
    }

    function focusWindow(winId) {
        msg(["window-focus", String(winId)]);
    }

    function toggleOverview() {
        msg(["overview-toggle"]);
    }

    function toggleScratchpad(name) {
        msg(["scratchpad-toggle", String(name)]);
    }

    function nextKeyboardLayout() {
        msg(["keyboard-layout-next"]);
    }

    function selectKeyboardLayout(targetIndex) {
        const n = keyboardLayouts.length;
        if (n <= 1) return;
        const steps = ((targetIndex - currentKeyboardLayoutIndex) % n + n) % n;
        if (steps <= 0) return;
        if (steps === 1) {
            nextKeyboardLayout();
            return;
        }
        Quickshell.execDetached([
            "sh", "-c",
            "i=0; while [ \"$i\" -lt " + steps + " ]; do umbriel msg keyboard-layout-next; i=$((i+1)); done"
        ]);
    }

    function layoutShortCode(name) {
        if (!name) return "";
        const s = String(name).trim();
        const low = s.toLowerCase();

        // Specific country / regional overrides first (matches Expressive Shell e.g. GB, US, LA, BR)
        if (low.indexOf("uk") !== -1 || low.indexOf("united kingdom") !== -1 || low.indexOf("british") !== -1) return "GB";
        if (low.indexOf("english (us") !== -1 || low === "us" || low.indexOf("american") !== -1) return "US";
        if (low.indexOf("latin american") !== -1) {
            const hasOtherSpanish = keyboardLayouts.some(l => {
                const ll = String(l).toLowerCase();
                return ll.indexOf("spanish") !== -1 && ll.indexOf("latin american") === -1;
            });
            return hasOtherSpanish ? "LA" : "ES";
        }
        if (low.indexOf("brazil") !== -1) return "BR";
        if (low.indexOf("canadian") !== -1) return "CA";
        if (low.indexOf("swiss") !== -1) return "CH";
        if (low.indexOf("belgian") !== -1) return "BE";

        const map = [
            ["english", "US"],
            ["spanish", "ES"],
            ["español", "ES"],
            ["french", "FR"],
            ["français", "FR"],
            ["german", "DE"],
            ["deutsch", "DE"],
            ["italian", "IT"],
            ["portuguese", "PT"],
            ["japanese", "あ"],
            ["日本語", "あ"],
            ["korean", "한"],
            ["chinese", "中"],
            ["russian", "RU"],
            ["ukrainian", "UA"],
            ["polish", "PL"],
            ["dutch", "NL"],
            ["swedish", "SE"],
            ["norwegian", "NO"],
            ["danish", "DK"],
            ["finnish", "FI"],
            ["turkish", "TR"],
            ["czech", "CZ"],
            ["hungarian", "HU"],
            ["romanian", "RO"],
            ["greek", "EL"],
            ["hebrew", "HE"],
            ["arabic", "AR"],
            ["vietnamese", "VI"],
            ["thai", "TH"],
            ["hindi", "HI"],
            ["esperanto", "EO"],
            ["colemak", "CM"],
            ["dvorak", "DV"]
        ];
        for (let i = 0; i < map.length; i++) {
            if (low.indexOf(map[i][0]) !== -1) return map[i][1];
        }
        return s.replace(/[^A-Za-z0-9]/g, "").slice(0, 2).toUpperCase() || s.slice(0, 2).toUpperCase();
    }

    function workspacesForOutput(outputName) {
        return workspaces.filter(ws => !outputName || ws.output === outputName);
    }

    function windowsInWorkspace(wsId) {
        return windows
            .filter(w => w.workspace === wsId && !w.scratchpad)
            .sort((a, b) => {
                const colA = (a.column !== undefined && a.column >= 0) ? a.column : 999;
                const colB = (b.column !== undefined && b.column >= 0) ? b.column : 999;
                if (colA !== colB) return colA - colB;
                const rowA = (a.row !== undefined && a.row >= 0) ? a.row : 999;
                const rowB = (b.row !== undefined && b.row >= 0) ? b.row : 999;
                if (rowA !== rowB) return rowA - rowB;
                return String(a.id).localeCompare(String(b.id));
            });
    }

    function scratchpadWindows(name) {
        return windows.filter(w => w.scratchpad && (!name || w.scratchpad === name));
    }

    function hasMaximizedOnOutput(outputName) {
        return windows.some(w =>
            w.visible &&
            (!outputName || w.output === outputName) &&
            (w.maximized || w.maximized_to_edges || w.fullscreen)
        );
    }

    function iconForAppId(appId) {
        if (!appId) return Quickshell.iconPath("application-x-executable", true);

        const overrides = {
            "com.discord.libdiscord": "discord",
            "com.mitchellh.ghostty": "com.mitchellh.ghostty",
            "helium": "helium-browser",
            "dev.zed.Zed": "zed",
            "md.obsidian.Obsidian": "obsidian",
            "spotify": "spotify-launcher",
            "slick": "slack"
        };

        const entry = DesktopEntries.heuristicLookup(appId);
        if (entry && entry.icon) {
            const p = Quickshell.iconPath(entry.icon, true);
            if (p) return p;
        }

        if (overrides[appId]) {
            const p = Quickshell.iconPath(overrides[appId], true);
            if (p) return p;
        }

        const direct = Quickshell.iconPath(appId, true) || Quickshell.iconPath(appId.toLowerCase(), true);
        return direct || Quickshell.iconPath("application-x-executable", true);
    }

    function launchAppId(appId) {
        if (appId === "com.discord.libdiscord") {
            toggleScratchpad("discord");
            return;
        }
        const existing = windows.find(w => w.app_id === appId);
        if (existing) {
            focusWindow(existing.id);
            return;
        }
        const entry = DesktopEntries.heuristicLookup(appId);
        if (entry) {
            entry.execute();
        } else {
            Quickshell.execDetached(["sh", "-c", appId]);
        }
    }
}
