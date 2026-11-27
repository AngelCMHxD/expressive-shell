pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string cachePath: (Quickshell.env("HOME") || "/home/angel") + "/.cache/expressive-shell/calendar-events.json"

    property string status: "no_accounts" // "ok" | "no_accounts" | "error"
    property string message: ""
    property var accounts: []
    property var eventsByDate: ({})
    property bool syncing: false

    function dateKey(year, month0, day) {
        const y = String(year);
        const m = String(month0 + 1).padStart(2, "0");
        const d = String(day).padStart(2, "0");
        return y + "-" + m + "-" + d;
    }

    function eventsForDate(year, month0, day) {
        if (day <= 0) return [];
        const key = dateKey(year, month0, day);
        return eventsByDate[key] || [];
    }

    function applyJson(raw) {
        try {
            const data = JSON.parse(raw);
            if (!data || typeof data !== "object") return;
            status = String(data.status || "no_accounts");
            message = String(data.message || "");
            accounts = Array.isArray(data.accounts) ? data.accounts : [];
            eventsByDate = (data.eventsByDate && typeof data.eventsByDate === "object") ? data.eventsByDate : {};
        } catch (e) {
            console.warn("CalendarEvents: parse error:", e);
        }
    }

    function refresh() {
        if (fetchProc.running) return;
        syncing = true;
        fetchProc.running = true;
    }

    function openOnlineAccounts() {
        Quickshell.execDetached([
            "sh", "-c",
            "command -v gnome-online-accounts-gtk >/dev/null 2>&1 && exec gnome-online-accounts-gtk; " +
            "command -v gnome-control-center >/dev/null 2>&1 && exec gnome-control-center online-accounts; " +
            "xdg-open https://calendar.google.com"
        ]);
    }

    FileView {
        id: cacheFile
        path: root.cachePath
        onLoaded: root.applyJson(text())
    }

    Process {
        id: fetchProc
        command: ["python3", Quickshell.shellPath("scripts/fetch-calendar.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text && text.trim().length > 0) {
                    root.applyJson(text.trim());
                }
            }
        }
        onExited: root.syncing = false
    }

    Timer {
        interval: 900000 // 15 minutes
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
