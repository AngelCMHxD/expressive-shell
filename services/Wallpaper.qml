pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

Singleton {
    id: root

    property string wallpaperDir: ShellState.resolvedWallpapersDir
    property var wallpapers: []
    property string currentWallpaper: ShellState.currentWallpaper

    onWallpaperDirChanged: {
        if (!scanProc.running) {
            _scanBuf = [];
            scanProc.running = true;
        }
    }

    // Performance toggle:
    // false = static WallpaperLayer (shows static 1st frame of GIFs, 0% CPU / best battery)
    // true  = animated awww daemon + transitions
    property bool useAwww: ShellState.useAwww

    // True only once awww-daemon has actually rendered the current wallpaper
    // so WallpaperLayer never vanishes early and flashes blank/old backgrounds.
    property bool awwwReady: false

    // Built-in wallpaper rotation
    property bool autoRotate: ShellState.autoRotate
    readonly property int rotateIntervalSec: ShellState.rotateIntervalSec
    readonly property string rotateOrder: ShellState.rotateOrder

    onCurrentWallpaperChanged: {
        if (currentWallpaper && ShellState.currentWallpaper !== currentWallpaper) {
            ShellState.currentWallpaper = currentWallpaper;
        }
    }
    onUseAwwwChanged: {
        if (ShellState.useAwww !== useAwww) {
            ShellState.useAwww = useAwww;
        }
    }
    onAutoRotateChanged: {
        if (ShellState.autoRotate !== autoRotate) {
            ShellState.autoRotate = autoRotate;
        }
    }

    property var _scanBuf: []
    property string _pendingAwwwPath: ""
    property bool _pendingAwwwInstant: false

    Process {
        id: scanProc
        command: [
            "sh", "-c",
            "find \"$1\" -maxdepth 2 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.jxl' \\) 2>/dev/null | sort",
            "_",
            root.wallpaperDir
        ]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const p = line.trim();
                if (p.length > 0) root._scanBuf.push(p);
            }
        }
        onExited: {
            root.wallpapers = root._scanBuf;
            root._scanBuf = [];
            if (!root.currentWallpaper && root.wallpapers.length > 0) {
                root.currentWallpaper = root.wallpapers[0];
            }
        }
    }

    // Tracked awww process so we know the exact moment awww finishes drawing
    Process {
        id: awwwProc
        onExited: code => {
            if (code === 0 && root.useAwww) {
                awwwCommitTimer.restart();
            }
        }
    }

    // Give awww-daemon a moment to commit its first frame to Umbriel before revealing it
    Timer {
        id: awwwCommitTimer
        interval: 150
        onTriggered: {
            if (root.useAwww) root.awwwReady = true;
        }
    }

    // Wait for static WallpaperLayer to paint before stopping awww-daemon
    Timer {
        id: stopAwwwTimer
        interval: 260
        onTriggered: {
            if (!root.useAwww) {
                Quickshell.execDetached(["sh", "-c", "pkill -x awww-daemon 2>/dev/null || true"]);
            }
        }
    }

    // Read previously applied wallpaper from colors.json if available
    FileView {
        id: stateFile
        path: ShellState.configDir + "/colors.json"
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (parsed && parsed.wallpaper) {
                    root.currentWallpaper = parsed.wallpaper;
                }
            } catch (e) {}
        }
    }

    function refreshList() {
        _scanBuf = [];
        if (!scanProc.running) scanProc.running = true;
    }

    function isAnimatedFile(path) {
        if (!path) return false;
        const lower = path.toLowerCase();
        return lower.endsWith(".gif") || lower.endsWith(".webp");
    }

    function displayName(path) {
        if (!path) return "";
        const base = path.split("/").pop() || path;
        return base.replace(/\.[^.]+$/, "");
    }

    function runAwww(path, instant) {
        stopAwwwTimer.stop();
        const isPixelArt = path.toLowerCase().endsWith(".gif");
        const filterArg = isPixelArt ? "--filter Nearest" : "--filter Lanczos3";
        const transitionArgs = instant
            ? "--transition-type none"
            : "--transition-type grow --transition-fps 60 --transition-duration 0.55";
        if (awwwProc.running) awwwProc.running = false;
        awwwProc.command = [
            "sh", "-c",
            "if ! pgrep -x awww-daemon >/dev/null; then " +
            "  awww-daemon --no-cache -q >/dev/null 2>&1 & " +
            "  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do " +
            "    awww query >/dev/null 2>&1 && break; sleep 0.05; " +
            "  done; " +
            "fi; " +
            "awww img \"$1\" " + filterArg + " " + transitionArgs,
            "_",
            path
        ];
        awwwProc.running = true;
    }

    function applyWallpaper(path, updateColors) {
        if (!path) return;
        currentWallpaper = path;

        if (useAwww) {
            runAwww(path, !awwwReady);
        } else {
            awwwReady = false;
            stopAwwwTimer.restart();
        }

        if (updateColors !== false) {
            const script = Quickshell.shellPath("scripts/apply-theme.py");
            const mode = ShellState.darkMode ? "dark" : "light";
            Quickshell.execDetached(["python3", script, path, mode]);
        }
    }

    function toggleAwww() {
        useAwww = !useAwww;
        awwwCommitTimer.stop();
        if (useAwww) {
            // Keep static WallpaperLayer visible until awww renders the current frame seamlessly
            awwwReady = false;
            if (currentWallpaper) runAwww(currentWallpaper, true);
        } else {
            // Show static WallpaperLayer immediately, then stop awww-daemon once painted
            awwwReady = false;
            stopAwwwTimer.restart();
        }
    }

    function randomNext() {
        if (wallpapers.length === 0) return;
        if (wallpapers.length === 1) {
            applyWallpaper(wallpapers[0], true);
            return;
        }
        const candidates = wallpapers.filter(w => w !== currentWallpaper);
        const pick = candidates[Math.floor(Math.random() * candidates.length)];
        applyWallpaper(pick, true);
    }

    function nextWallpaper() {
        if (wallpapers.length === 0) return;
        if (rotateOrder === "alphabetical") {
            const idx = wallpapers.indexOf(currentWallpaper);
            const nextIdx = (idx >= 0) ? ((idx + 1) % wallpapers.length) : 0;
            applyWallpaper(wallpapers[nextIdx], true);
        } else {
            randomNext();
        }
    }

    Timer {
        interval: Math.max(30, root.rotateIntervalSec) * 1000
        running: root.autoRotate && root.wallpapers.length > 1
        repeat: true
        onTriggered: root.nextWallpaper()
    }

    // Re-sync Umbriel dark/light colors when darkMode toggles
    Connections {
        target: ShellState
        function onDarkModeChanged() {
            if (root.currentWallpaper) {
                const script = Quickshell.shellPath("scripts/apply-theme.py");
                const mode = ShellState.darkMode ? "dark" : "light";
                Quickshell.execDetached(["python3", script, root.currentWallpaper, mode]);
            }
        }
    }

    Timer {
        interval: Math.max(10, root.rotateIntervalSec) * 1000
        running: root.autoRotate && root.wallpapers.length > 1
        repeat: true
        onTriggered: root.randomNext()
    }
}
