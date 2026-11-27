pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../theme"

Singleton {
    id: root

    property var history: []
    property var toasts: []
    property int nextId: 1
    readonly property int count: history.length

    signal toastAdded(var entry)
    signal toastDismissRequested(int uid)

    function resolvePath(raw) {
        if (!raw || raw.length === 0) return "";
        if (raw.startsWith("image://") || raw.startsWith("file://") || raw.startsWith("http")) return raw;
        if (raw.startsWith("/")) return "file://" + raw;
        return Quickshell.iconPath(raw, true) || "";
    }

    function resolveAppIcon(appIcon, appName) {
        const direct = resolvePath(appIcon);
        if (direct) return direct;
        if (appName && appName.length > 0) {
            const entry = DesktopEntries.heuristicLookup(appName);
            if (entry && entry.icon) {
                const p = Quickshell.iconPath(entry.icon, true);
                if (p) return p;
            }
            const byName = Quickshell.iconPath(appName.toLowerCase(), true);
            if (byName) return byName;
        }
        return "";
    }

    NotificationServer {
        id: server
        bodySupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;
            const aName = notif.appName || "Notification";
            const ctxImg = root.resolvePath(notif.image || "");
            const appBadge = root.resolveAppIcon(notif.appIcon || "", aName);

            // Extract any inline <img src="..."> attachment from HTML body
            let rawBody = notif.body || "";
            let bodyImg = "";
            const imgMatch = rawBody.match(/<img[^>]+src=["']([^"']+)["'][^>]*>/i);
            if (imgMatch && imgMatch[1]) {
                bodyImg = root.resolvePath(imgMatch[1]);
                rawBody = rawBody.replace(imgMatch[0], "").trim();
            }
            // Strip basic HTML tags for crisp plain text display
            const cleanBody = rawBody.replace(/<[^>]+>/g, "").replace(/\s+\n/g, "\n").trim();

            // Collect clickable notification actions (e.g. Play, Reply, Mark as read)
            const actList = [];
            const rawActs = notif.actions || [];
            for (let i = 0; i < rawActs.length; i++) {
                const a = rawActs[i];
                if (!a) continue;
                const label = String(a.text || "").trim();
                if (!label || a.identifier === "default") continue;
                actList.push({ identifier: String(a.identifier || ""), text: label });
            }

            const entry = {
                uid: root.nextId++,
                notifObj: notif,
                appName: aName,
                iconSource: ctxImg || appBadge,
                appIconSource: appBadge,
                appBadgeSource: ctxImg ? appBadge : "",
                attachmentImage: bodyImg,
                contextImage: ctxImg,
                isContextImage: ctxImg.length > 0,
                summary: notif.summary || "",
                body: cleanBody,
                actions: actList,
                time: Qt.formatDateTime(new Date(), "h:mm"),
                urgency: notif.urgency
            };
            // Don't re-pop toasts for notifications replayed from the previous reload generation
            root.addEntry(entry, !notif.lastGeneration);
        }
    }

    function invokeAction(uid, identifier) {
        const target = history.find(n => n.uid === uid);
        if (!target || !target.notifObj || !target.notifObj.actions) return;
        const acts = target.notifObj.actions;
        for (let i = 0; i < acts.length; i++) {
            if (acts[i] && String(acts[i].identifier) === String(identifier)) {
                try { acts[i].invoke(); } catch (e) {}
                break;
            }
        }
    }

    function addEntry(entry, showToast) {
        history = [entry, ...history].slice(0, 50);
        if (showToast !== false && !ShellState.dnd) {
            toasts = [entry, ...toasts];
            toastAdded(entry);
            while (toasts.length > 6) {
                const oldest = toasts[toasts.length - 1];
                toasts = toasts.slice(0, -1);
                toastDismissRequested(oldest.uid);
            }
        }
    }

    function pushTest(summary, body) {
        const icon = resolveAppIcon("dialog-information", "");
        addEntry({
            uid: nextId++,
            notifObj: null,
            appName: "Expressive Shell",
            iconSource: icon,
            appIconSource: icon,
            appBadgeSource: "",
            attachmentImage: "",
            contextImage: "",
            isContextImage: false,
            summary: summary || "Test Notification",
            body: body || "Notifications & pop-in toasts are working!",
            actions: [],
            time: Qt.formatDateTime(new Date(), "h:mm"),
            urgency: 1
        });
    }

    function pushMock(payloadJson) {
        try {
            const p = JSON.parse(payloadJson);
            const aName = p.appName || "Mock App";
            const appIcon = resolveAppIcon(p.appIcon || "", aName);
            const ctxImg = resolvePath(p.contextImage || "");
            const attImg = resolvePath(p.attachmentImage || "");
            addEntry({
                uid: nextId++,
                notifObj: null,
                appName: aName,
                iconSource: ctxImg || appIcon,
                appIconSource: appIcon,
                appBadgeSource: ctxImg ? appIcon : "",
                attachmentImage: attImg,
                contextImage: ctxImg,
                isContextImage: ctxImg.length > 0,
                summary: p.summary || "",
                body: p.body || "",
                actions: Array.isArray(p.actions) ? p.actions : [],
                time: p.time || Qt.formatDateTime(new Date(), "h:mm"),
                urgency: 1
            }, p.showToast !== false);
        } catch (e) {
            console.warn("Notifications.pushMock parse error:", e);
        }
    }

    function dismissToast(uid) {
        toasts = toasts.filter(t => t.uid !== uid);
        toastDismissRequested(uid);
    }

    function dismiss(uid) {
        const target = history.find(n => n.uid === uid);
        if (target && target.notifObj) {
            try {
                target.notifObj.tracked = false;
                target.notifObj.dismiss();
            } catch (e) {}
        }
        history = history.filter(n => n.uid !== uid);
        dismissToast(uid);
    }

    function dismissApp(appKey) {
        const key = String(appKey || "").toLowerCase();
        const matching = history.filter(n => String(n.appName || "Notification").toLowerCase() === key);
        for (const target of matching) {
            if (target.notifObj) {
                try {
                    target.notifObj.tracked = false;
                    target.notifObj.dismiss();
                } catch (e) {}
            }
            dismissToast(target.uid);
        }
        history = history.filter(n => String(n.appName || "Notification").toLowerCase() !== key);
    }

    function clearAll() {
        for (const n of history) {
            if (n.notifObj) {
                try {
                    n.notifObj.tracked = false;
                    n.notifObj.dismiss();
                } catch (e) {}
            }
        }
        // Also sweep any tracked notifications persisted across reloads
        const tracked = server.trackedNotifications ? server.trackedNotifications.values : [];
        for (let i = tracked.length - 1; i >= 0; i--) {
            try {
                tracked[i].tracked = false;
                tracked[i].dismiss();
            } catch (e) {}
        }
        for (const t of toasts) {
            toastDismissRequested(t.uid);
        }
        history = [];
        toasts = [];
    }
}
