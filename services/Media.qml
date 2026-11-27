pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root

    readonly property var activePlayer: {
        const list = Mpris.players.values;
        if (!list || list.length === 0) return null;
        for (let i = 0; i < list.length; i++) {
            if (list[i].isPlaying) return list[i];
        }
        return list[0];
    }

    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool isPlaying: activePlayer ? activePlayer.isPlaying : false
    readonly property string title: activePlayer ? (activePlayer.trackTitle || activePlayer.identity || "Unknown") : ""
    readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
    readonly property string artUrl: activePlayer ? (activePlayer.trackArtUrl || "") : ""
    readonly property string playerIdentity: activePlayer ? (activePlayer.identity || "") : ""
    readonly property string playerDesktopEntry: activePlayer ? (activePlayer.desktopEntry || "") : ""
    readonly property string playerIconSource: {
        if (!activePlayer) return "";
        const candidates = [playerDesktopEntry, playerIdentity];
        for (let i = 0; i < candidates.length; i++) {
            const raw = String(candidates[i] || "").trim();
            if (!raw) continue;
            const low = raw.toLowerCase();
            if (low.indexOf("helium") !== -1 || low.indexOf("chromium") !== -1) {
                const hp = Quickshell.iconPath("helium-browser", true) || Quickshell.iconPath("chromium", true);
                if (hp) return hp;
            }
            if (low.indexOf("spotify") !== -1) {
                const sp = Quickshell.iconPath("spotify-launcher", true) || Quickshell.iconPath("spotify", true);
                if (sp) return sp;
            }
            const entry = DesktopEntries.heuristicLookup(raw);
            if (entry && entry.icon) {
                const ep = Quickshell.iconPath(entry.icon, true);
                if (ep) return ep;
            }
            const direct = Quickshell.iconPath(raw, true) || Quickshell.iconPath(low, true);
            if (direct) return direct;
        }
        return "";
    }
    readonly property real length: activePlayer ? activePlayer.length : 0

    property real livePosition: 0
    readonly property real progress: length > 0 ? Math.max(0, Math.min(1, livePosition / length)) : 0

    function syncPosition() {
        livePosition = activePlayer ? activePlayer.position : 0;
    }

    onActivePlayerChanged: syncPosition()

    Timer {
        interval: 1000
        running: root.hasPlayer && root.isPlaying
        repeat: true
        onTriggered: {
            if (root.activePlayer) {
                root.activePlayer.positionChanged();
                root.livePosition = root.activePlayer.position;
            }
        }
    }

    function togglePlay() {
        if (activePlayer) activePlayer.togglePlaying();
    }

    function next() {
        if (activePlayer && activePlayer.canGoNext) activePlayer.next();
    }

    function previous() {
        if (activePlayer && activePlayer.canGoPrevious) activePlayer.previous();
    }

    function seekToFraction(frac) {
        if (!activePlayer || !activePlayer.canSeek || length <= 0) return;
        const target = Math.max(0, Math.min(length, frac * length));
        activePlayer.position = target;
        livePosition = target;
    }
}
